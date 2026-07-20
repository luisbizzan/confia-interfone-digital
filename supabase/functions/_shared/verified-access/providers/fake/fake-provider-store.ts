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

export function readIdempotentResult<T>(
  store: FakeProviderStore,
  key: FakeProviderStoreKey,
  inputFingerprint: ProviderInputFingerprint,
  correlationId: string,
  providerCode: string,
): ProviderResult<T> | undefined {
  const stored = store.get<T>(key);
  if (!stored) {
    return undefined;
  }
  if (!sameFingerprint(stored.inputFingerprint, inputFingerprint)) {
    return providerFailure({
      code: "CONFLICT",
      retryable: false,
      correlationId,
      providerCode,
      metadataSanitized: { reasonCode: "IDEMPOTENCY_FINGERPRINT_MISMATCH" },
    });
  }
  return stored.result;
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

function serializeKey(key: FakeProviderStoreKey): string {
  return JSON.stringify([
    key.providerCode,
    key.operation,
    key.condominiumId,
    key.idempotencyKey,
  ]);
}
