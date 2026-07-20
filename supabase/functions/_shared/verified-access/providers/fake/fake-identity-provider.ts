import type { Clock } from "../clock.ts";
import { VirtualClock } from "../clock.ts";
import {
  deriveFakeIdempotencyScope,
  deriveFakeIdentifier,
  type IdentityCancellation,
  type IdentityCapabilities,
  type IdentityResult,
  type IdentitySession,
  type IdentitySessionInput,
  type ProviderMutationContext,
  type ProviderReadContext,
} from "../contracts.ts";
import type { IdentityProvider } from "../identity-provider.ts";
import {
  providerFailure,
  type ProviderResult,
  providerSuccess,
} from "../result.ts";
import {
  type FakeProviderStore,
  InMemoryFakeProviderStore,
  readIdempotentResult,
  storeIdempotentResult,
} from "./fake-provider-store.ts";
import type { IdentityScenario } from "./scenarios.ts";

export type FakeIdentityProviderOptions = Readonly<{
  scenario: IdentityScenario;
  providerCode?: string;
  store?: FakeProviderStore;
  clock?: Clock;
  latencyMs?: number;
  maxRecords?: number;
}>;

export class FakeIdentityProvider implements IdentityProvider {
  readonly #scenario: IdentityScenario;
  readonly #providerCode: string;
  readonly #store: FakeProviderStore;
  readonly #clock: Clock;
  readonly #latencyMs: number;

  constructor(options: FakeIdentityProviderOptions) {
    this.#scenario = options.scenario;
    this.#providerCode = options.providerCode ?? "FAKE_IDENTITY";
    this.#store = options.store ??
      new InMemoryFakeProviderStore(options.maxRecords ?? 1_000);
    this.#clock = options.clock ?? new VirtualClock("2026-01-01T00:00:00.000Z");
    this.#latencyMs = validateLatency(options.latencyMs ?? 0);
  }

  capabilities(): IdentityCapabilities {
    return {
      documentVerification: true,
      liveness: true,
      faceMatchOneToOne: true,
      polling: true,
      cancellation: true,
    };
  }

  async createSession(
    input: IdentitySessionInput,
  ): Promise<ProviderResult<IdentitySession>> {
    await this.#clock.sleep(this.#latencyMs);
    const invalid = validateMutationContext(input.context, this.#providerCode);
    if (invalid) {
      return invalid;
    }
    const idempotencyScope = await deriveFakeIdempotencyScope(
      this.#providerCode,
      "createSession",
      input.context.condominiumId,
      input.context.idempotencyKey,
    );
    const key = {
      providerCode: this.#providerCode,
      operation: "createSession",
      condominiumId: input.context.condominiumId,
      idempotencyKey: idempotencyScope,
    };
    const stored = readIdempotentResult<IdentitySession>(
      this.#store,
      key,
      input.context.inputFingerprint,
      input.context.correlationId,
      this.#providerCode,
    );
    if (stored) {
      return stored;
    }

    const scenarioFailure = this.#scenarioFailure(input.context.correlationId);
    if (scenarioFailure) {
      return storeIdempotentResult(
        this.#store,
        key,
        input.context.inputFingerprint,
        scenarioFailure,
        this.#clock.now().toISOString(),
        input.context.correlationId,
        this.#providerCode,
      );
    }

    const createdAt = this.#clock.now();
    const providerSessionId = await deriveFakeIdentifier(
      "fake_identity",
      this.#providerCode,
      "createSession",
      input.context.condominiumId,
      input.context.idempotencyKey,
      input.context.inputFingerprint,
    );
    const result = providerSuccess<IdentitySession>({
      providerSessionId,
      providerCode: this.#providerCode,
      status: "PENDING",
      correlationId: input.context.correlationId,
      createdAt: createdAt.toISOString(),
      expiresAt: new Date(createdAt.getTime() + 15 * 60_000).toISOString(),
      metadataSanitized: { scenario: this.#scenario },
    });
    return storeIdempotentResult(
      this.#store,
      key,
      input.context.inputFingerprint,
      result,
      createdAt.toISOString(),
      input.context.correlationId,
      this.#providerCode,
    );
  }

  async getResult(
    providerSessionId: string,
    context: ProviderReadContext,
  ): Promise<ProviderResult<IdentityResult>> {
    await this.#clock.sleep(this.#latencyMs);
    const idempotencyScope = parseFakeIdentifier(
      providerSessionId,
      "fake_identity",
    );
    if (!idempotencyScope) {
      return providerFailure({
        code: "NOT_FOUND",
        retryable: false,
        correlationId: context.correlationId,
        providerCode: this.#providerCode,
      });
    }
    const session = this.#store.get<IdentitySession>({
      providerCode: this.#providerCode,
      operation: "createSession",
      condominiumId: context.condominiumId,
      idempotencyKey: idempotencyScope,
    });
    if (
      !session?.result.ok ||
      session.result.value.providerSessionId !== providerSessionId
    ) {
      return providerFailure({
        code: "NOT_FOUND",
        retryable: false,
        correlationId: context.correlationId,
        providerCode: this.#providerCode,
      });
    }
    const scenarioFailure = this.#scenarioFailure(context.correlationId);
    if (scenarioFailure) {
      return scenarioFailure;
    }
    return providerSuccess(
      identityResultForScenario(
        this.#scenario,
        providerSessionId,
        this.#providerCode,
        context.correlationId,
        this.#clock.now(),
      ),
    );
  }

  async cancelSession(
    providerSessionId: string,
    context: ProviderMutationContext,
  ): Promise<ProviderResult<IdentityCancellation>> {
    await this.#clock.sleep(this.#latencyMs);
    const invalid = validateMutationContext(context, this.#providerCode);
    if (invalid) {
      return invalid;
    }
    const sessionScope = parseFakeIdentifier(
      providerSessionId,
      "fake_identity",
    );
    if (!sessionScope) {
      return providerFailure({
        code: "NOT_FOUND",
        retryable: false,
        correlationId: context.correlationId,
        providerCode: this.#providerCode,
      });
    }
    const session = this.#store.get<IdentitySession>({
      providerCode: this.#providerCode,
      operation: "createSession",
      condominiumId: context.condominiumId,
      idempotencyKey: sessionScope,
    });
    if (
      !session?.result.ok ||
      session.result.value.providerSessionId !== providerSessionId
    ) {
      return providerFailure({
        code: "NOT_FOUND",
        retryable: false,
        correlationId: context.correlationId,
        providerCode: this.#providerCode,
      });
    }
    const cancellationScope = await deriveFakeIdempotencyScope(
      this.#providerCode,
      "cancelSession",
      context.condominiumId,
      context.idempotencyKey,
    );
    const key = {
      providerCode: this.#providerCode,
      operation: "cancelSession",
      condominiumId: context.condominiumId,
      idempotencyKey: cancellationScope,
    };
    const stored = readIdempotentResult<IdentityCancellation>(
      this.#store,
      key,
      context.inputFingerprint,
      context.correlationId,
      this.#providerCode,
    );
    if (stored) {
      return stored;
    }
    const occurredAt = this.#clock.now().toISOString();
    return storeIdempotentResult(
      this.#store,
      key,
      context.inputFingerprint,
      providerSuccess({
        providerSessionId,
        status: "CANCELLED",
        correlationId: context.correlationId,
        occurredAt,
      }),
      occurredAt,
      context.correlationId,
      this.#providerCode,
    );
  }

  #scenarioFailure(correlationId: string): ProviderResult<never> | undefined {
    if (this.#scenario === "IDENTITY_TIMEOUT") {
      return providerFailure({
        code: "TIMEOUT",
        retryable: true,
        correlationId,
        providerCode: this.#providerCode,
        retryAfterMs: 1_000,
      });
    }
    if (this.#scenario === "IDENTITY_PROVIDER_ERROR") {
      return providerFailure({
        code: "UNAVAILABLE",
        retryable: true,
        correlationId,
        providerCode: this.#providerCode,
        retryAfterMs: 2_000,
      });
    }
    return undefined;
  }
}

function identityResultForScenario(
  scenario: IdentityScenario,
  providerSessionId: string,
  providerCode: string,
  correlationId: string,
  now: Date,
): IdentityResult {
  const common = {
    providerSessionId,
    providerCode,
    correlationId,
    occurredAt: now.toISOString(),
    expiresAt: new Date(now.getTime() + 24 * 60 * 60_000).toISOString(),
    metadataSanitized: { scenario },
  } as const;
  switch (scenario) {
    case "IDENTITY_SUCCESS":
      return {
        ...common,
        status: "VERIFIED",
        level: "IDENTITY_VERIFIED",
        documentStatus: "VALID",
        livenessStatus: "PASSED",
        faceMatchStatus: "MATCH",
        reasonCode: "IDENTITY_CHECKS_PASSED",
      };
    case "IDENTITY_INCONCLUSIVE":
      return {
        ...common,
        status: "INCONCLUSIVE",
        level: "UNVERIFIED",
        documentStatus: "INCONCLUSIVE",
        livenessStatus: "INCONCLUSIVE",
        faceMatchStatus: "INCONCLUSIVE",
        reasonCode: "IDENTITY_INCONCLUSIVE",
      };
    case "DOCUMENT_INVALID_REVIEW":
      return {
        ...common,
        status: "INCONCLUSIVE",
        level: "UNVERIFIED",
        documentStatus: "INVALID",
        livenessStatus: "NOT_PERFORMED",
        faceMatchStatus: "NOT_PERFORMED",
        reasonCode: "DOCUMENT_REVIEW_REQUIRED",
      };
    case "LIVENESS_INCONCLUSIVE":
      return {
        ...common,
        status: "INCONCLUSIVE",
        level: "UNVERIFIED",
        documentStatus: "VALID",
        livenessStatus: "INCONCLUSIVE",
        faceMatchStatus: "NOT_PERFORMED",
        reasonCode: "LIVENESS_INCONCLUSIVE",
      };
    case "LIVENESS_FAILED_REVIEW":
      return {
        ...common,
        status: "INCONCLUSIVE",
        level: "UNVERIFIED",
        documentStatus: "VALID",
        livenessStatus: "FAILED",
        faceMatchStatus: "NOT_PERFORMED",
        reasonCode: "LIVENESS_REVIEW_REQUIRED",
      };
    case "FACE_NO_MATCH_REVIEW":
      return {
        ...common,
        status: "INCONCLUSIVE",
        level: "LIVENESS_VERIFIED",
        documentStatus: "VALID",
        livenessStatus: "PASSED",
        faceMatchStatus: "NO_MATCH",
        reasonCode: "FACE_MATCH_REVIEW_REQUIRED",
      };
    case "IDENTITY_TIMEOUT":
    case "IDENTITY_PROVIDER_ERROR":
      throw new TypeError("Technical scenarios return ProviderFailure");
  }
}

function validateMutationContext(
  context: ProviderMutationContext,
  providerCode: string,
): ProviderResult<never> | undefined {
  if (
    !context.condominiumId || !context.requestId || !context.participantId ||
    !context.correlationId || !context.idempotencyKey ||
    context.inputFingerprint.version !== 1 || !context.inputFingerprint.value
  ) {
    return providerFailure({
      code: "INVALID_INPUT",
      retryable: false,
      correlationId: context.correlationId,
      providerCode,
    });
  }
  return undefined;
}

function validateLatency(latencyMs: number): number {
  if (!Number.isFinite(latencyMs) || latencyMs < 0) {
    throw new TypeError(
      "Fake provider latency must be finite and non-negative",
    );
  }
  return latencyMs;
}

function parseFakeIdentifier(
  value: string,
  prefix: string,
): string | undefined {
  return new RegExp(`^${prefix}_([0-9a-f]{64})_[0-9a-f]{64}$`).exec(value)?.[1];
}
