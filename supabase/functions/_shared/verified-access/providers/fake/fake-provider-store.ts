import type { ProviderInputFingerprint } from "../contracts.ts";
import { providerFailure, type ProviderResult } from "../result.ts";

export type FakeProviderStoreKey = Readonly<{
  providerCode: string;
  operation: string;
  condominiumId: string;
  idempotencyKey: string;
}>;

export type FakeProviderStoreEntry<T> = Readonly<{
  inputFingerprint: ProviderInputFingerprint;
  result: ProviderResult<T>;
  storedAt: string;
}>;

export type FakeProviderStorePutResult = "STORED" | "LIMIT_REACHED";

export type FakeProviderAttempt<T> =
  | Readonly<{ action: "PROCEED" }>
  | Readonly<{ action: "RETURN"; result: ProviderResult<T> }>;

export interface FakeProviderStore {
  get<T>(key: FakeProviderStoreKey): FakeProviderStoreEntry<T> | undefined;
  put<T>(
    key: FakeProviderStoreKey,
    entry: FakeProviderStoreEntry<T>,
  ): FakeProviderStorePutResult;
  clear(): void;
}

export class InMemoryFakeProviderStore implements FakeProviderStore {
  readonly #maxRecords: number;
  readonly #entries = new Map<string, FakeProviderStoreEntry<unknown>>();

  constructor(maxRecords = 1_000) {
    if (!Number.isInteger(maxRecords) || maxRecords <= 0) {
      throw new TypeError(
        "Fake provider store limit must be a positive integer",
      );
    }
    this.#maxRecords = maxRecords;
  }

  get<T>(key: FakeProviderStoreKey): FakeProviderStoreEntry<T> | undefined {
    return this.#entries.get(serializeKey(key)) as
      | FakeProviderStoreEntry<T>
      | undefined;
  }

  put<T>(
    key: FakeProviderStoreKey,
    entry: FakeProviderStoreEntry<T>,
  ): FakeProviderStorePutResult {
    const serializedKey = serializeKey(key);
    if (
      !this.#entries.has(serializedKey) &&
      this.#entries.size >= this.#maxRecords
    ) {
      return "LIMIT_REACHED";
    }
    this.#entries.set(serializedKey, entry);
    return "STORED";
  }

  clear(): void {
    this.#entries.clear();
  }
}

export function beginIdempotentAttempt<T>(
  store: FakeProviderStore,
  key: FakeProviderStoreKey,
  inputFingerprint: ProviderInputFingerprint,
  failuresBeforeSuccess: number,
  storedAt: string,
  correlationId: string,
  providerCode: string,
): FakeProviderAttempt<T> {
  const stored = store.get<T>(key);
  if (stored && !sameFingerprint(stored.inputFingerprint, inputFingerprint)) {
    return {
      action: "RETURN",
      result: providerFailure({
        code: "CONFLICT",
        retryable: false,
        correlationId,
        providerCode,
        metadataSanitized: { reasonCode: "IDEMPOTENCY_FINGERPRINT_MISMATCH" },
      }),
    };
  }
  if (stored?.result.ok) {
    return { action: "RETURN", result: stored.result };
  }

  const completedFailures = stored ? transientFailureAttempt(stored.result) : 0;
  if (completedFailures === undefined) {
    return { action: "RETURN", result: stored!.result };
  }
  if (completedFailures >= failuresBeforeSuccess) {
    return { action: "PROCEED" };
  }

  const attemptNumber = completedFailures + 1;
  const result = storeIdempotentResult<T>(
    store,
    key,
    inputFingerprint,
    providerFailure({
      code: "UNAVAILABLE",
      retryable: true,
      correlationId,
      providerCode,
      retryAfterMs: 1_000,
      metadataSanitized: {
        attemptNumber,
        reasonCode: "FAKE_FAILURE_BEFORE_SUCCESS",
      },
    }),
    storedAt,
    correlationId,
    providerCode,
  );
  return { action: "RETURN", result };
}

export function validateFailuresBeforeSuccess(value: number): number {
  if (!Number.isInteger(value) || value < 0) {
    throw new TypeError(
      "Fake provider failuresBeforeSuccess must be a non-negative integer",
    );
  }
  return value;
}

export function storeIdempotentResult<T>(
  store: FakeProviderStore,
  key: FakeProviderStoreKey,
  inputFingerprint: ProviderInputFingerprint,
  result: ProviderResult<T>,
  storedAt: string,
  correlationId: string,
  providerCode: string,
): ProviderResult<T> {
  const putResult = store.put(key, { inputFingerprint, result, storedAt });
  if (putResult === "LIMIT_REACHED") {
    return providerFailure({
      code: "UNAVAILABLE",
      retryable: false,
      correlationId,
      providerCode,
      metadataSanitized: { reasonCode: "FAKE_STORE_LIMIT_REACHED" },
    });
  }
  return result;
}

function sameFingerprint(
  left: ProviderInputFingerprint,
  right: ProviderInputFingerprint,
): boolean {
  return left.version === right.version && left.value === right.value;
}

function transientFailureAttempt<T>(
  result: ProviderResult<T>,
): number | undefined {
  if (result.ok) {
    return undefined;
  }
  const metadata = result.error.metadataSanitized;
  if (metadata?.reasonCode !== "FAKE_FAILURE_BEFORE_SUCCESS") {
    return undefined;
  }
  const attemptNumber = metadata.attemptNumber;
  return typeof attemptNumber === "number" &&
      Number.isInteger(attemptNumber) && attemptNumber > 0
    ? attemptNumber
    : undefined;
}

function serializeKey(key: FakeProviderStoreKey): string {
  return JSON.stringify([
    key.providerCode,
    key.operation,
    key.condominiumId,
    key.idempotencyKey,
  ]);
}
