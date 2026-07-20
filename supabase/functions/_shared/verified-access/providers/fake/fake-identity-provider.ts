import type { Clock } from "../clock.ts";
import { VirtualClock } from "../clock.ts";
import {
  deriveFakeIdempotencyScope,
  deriveFakeIdentifier,
  type IdentityCancellation,
  type IdentityCapabilities,
  type IdentityRequestedCheck,
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
  beginIdempotentAttempt,
  type FakeProviderStore,
  InMemoryFakeProviderStore,
  storeIdempotentResult,
  validateFailuresBeforeSuccess,
} from "./fake-provider-store.ts";
import type { IdentityScenario } from "./scenarios.ts";

export type FakeIdentityProviderOptions = Readonly<{
  scenario: IdentityScenario;
  providerCode?: string;
  store?: FakeProviderStore;
  clock?: Clock;
  latencyMs?: number;
  failuresBeforeSuccess?: number;
  maxRecords?: number;
}>;

export class FakeIdentityProvider implements IdentityProvider {
  readonly #scenario: IdentityScenario;
  readonly #providerCode: string;
  readonly #store: FakeProviderStore;
  readonly #clock: Clock;
  readonly #latencyMs: number;
  readonly #failuresBeforeSuccess: number;

  constructor(options: FakeIdentityProviderOptions) {
    this.#scenario = options.scenario;
    this.#providerCode = options.providerCode ?? "FAKE_IDENTITY";
    this.#store = options.store ??
      new InMemoryFakeProviderStore(options.maxRecords ?? 1_000);
    this.#clock = options.clock ?? new VirtualClock("2026-01-01T00:00:00.000Z");
    this.#latencyMs = validateLatency(options.latencyMs ?? 0);
    this.#failuresBeforeSuccess = validateFailuresBeforeSuccess(
      options.failuresBeforeSuccess ?? 0,
    );
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
    const invalid = validateIdentitySessionInput(input, this.#providerCode);
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
    const attempt = beginIdempotentAttempt<IdentitySession>(
      this.#store,
      key,
      input.context.inputFingerprint,
      this.#failuresBeforeSuccess,
      this.#clock.now().toISOString(),
      input.context.correlationId,
      this.#providerCode,
    );
    if (attempt.action === "RETURN") {
      return attempt.result;
    }

    const scenarioFailure = this.#scenarioFailure(input.context.correlationId);
    if (scenarioFailure) {
      return scenarioFailure;
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
      metadataSanitized: {
        documentRequested: input.requestedChecks.includes(
          "DOCUMENT_VERIFICATION",
        ),
        faceMatchOneToOneRequested: input.requestedChecks.includes(
          "FACE_MATCH_ONE_TO_ONE",
        ),
        livenessRequested: input.requestedChecks.includes("LIVENESS"),
        scenario: this.#scenario,
      },
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
    const invalid = validateReadContext(context, this.#providerCode);
    if (invalid) {
      return invalid;
    }
    if (!isNonEmptyString(providerSessionId)) {
      return invalidInput(context.correlationId, this.#providerCode);
    }
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
        requestedChecksFromSession(session.result.value),
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
    if (!isNonEmptyString(providerSessionId)) {
      return invalidInput(context.correlationId, this.#providerCode);
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
    const attempt = beginIdempotentAttempt<IdentityCancellation>(
      this.#store,
      key,
      context.inputFingerprint,
      this.#failuresBeforeSuccess,
      this.#clock.now().toISOString(),
      context.correlationId,
      this.#providerCode,
    );
    if (attempt.action === "RETURN") {
      return attempt.result;
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
  requestedChecks: readonly IdentityRequestedCheck[],
): IdentityResult {
  const common = {
    providerSessionId,
    providerCode,
    correlationId,
    occurredAt: now.toISOString(),
    expiresAt: new Date(now.getTime() + 24 * 60 * 60_000).toISOString(),
    metadataSanitized: { scenario },
  } as const;
  let result: IdentityResult;
  switch (scenario) {
    case "IDENTITY_SUCCESS":
      result = {
        ...common,
        status: "VERIFIED",
        level: "IDENTITY_VERIFIED",
        documentStatus: "VALID",
        livenessStatus: "PASSED",
        faceMatchStatus: "MATCH",
        reasonCode: "IDENTITY_CHECKS_PASSED",
      };
      break;
    case "IDENTITY_INCONCLUSIVE":
      result = {
        ...common,
        status: "INCONCLUSIVE",
        level: "UNVERIFIED",
        documentStatus: "INCONCLUSIVE",
        livenessStatus: "INCONCLUSIVE",
        faceMatchStatus: "INCONCLUSIVE",
        reasonCode: "IDENTITY_INCONCLUSIVE",
      };
      break;
    case "DOCUMENT_INVALID_REVIEW":
      result = {
        ...common,
        status: "INCONCLUSIVE",
        level: "UNVERIFIED",
        documentStatus: "INVALID",
        livenessStatus: "NOT_PERFORMED",
        faceMatchStatus: "NOT_PERFORMED",
        reasonCode: "DOCUMENT_REVIEW_REQUIRED",
      };
      break;
    case "LIVENESS_INCONCLUSIVE":
      result = {
        ...common,
        status: "INCONCLUSIVE",
        level: "UNVERIFIED",
        documentStatus: "VALID",
        livenessStatus: "INCONCLUSIVE",
        faceMatchStatus: "NOT_PERFORMED",
        reasonCode: "LIVENESS_INCONCLUSIVE",
      };
      break;
    case "LIVENESS_FAILED_REVIEW":
      result = {
        ...common,
        status: "INCONCLUSIVE",
        level: "UNVERIFIED",
        documentStatus: "VALID",
        livenessStatus: "FAILED",
        faceMatchStatus: "NOT_PERFORMED",
        reasonCode: "LIVENESS_REVIEW_REQUIRED",
      };
      break;
    case "FACE_NO_MATCH_REVIEW":
      result = {
        ...common,
        status: "INCONCLUSIVE",
        level: "LIVENESS_VERIFIED",
        documentStatus: "VALID",
        livenessStatus: "PASSED",
        faceMatchStatus: "NO_MATCH",
        reasonCode: "FACE_MATCH_REVIEW_REQUIRED",
      };
      break;
    case "IDENTITY_TIMEOUT":
    case "IDENTITY_PROVIDER_ERROR":
      throw new TypeError("Technical scenarios return ProviderFailure");
  }
  return applyRequestedChecks(result, requestedChecks);
}

function applyRequestedChecks(
  result: IdentityResult,
  requestedChecks: readonly IdentityRequestedCheck[],
): IdentityResult {
  const requested = new Set(requestedChecks);
  const documentStatus = requested.has("DOCUMENT_VERIFICATION")
    ? result.documentStatus
    : "NOT_PERFORMED";
  const livenessStatus = requested.has("LIVENESS")
    ? result.livenessStatus
    : "NOT_PERFORMED";
  const faceMatchStatus = requested.has("FACE_MATCH_ONE_TO_ONE")
    ? result.faceMatchStatus
    : "NOT_PERFORMED";
  const level = documentStatus === "VALID" && livenessStatus === "PASSED" &&
      faceMatchStatus === "MATCH"
    ? "IDENTITY_VERIFIED"
    : livenessStatus === "PASSED"
    ? "LIVENESS_VERIFIED"
    : "UNVERIFIED";
  return {
    ...result,
    documentStatus,
    faceMatchStatus,
    level,
    livenessStatus,
  };
}

function requestedChecksFromSession(
  session: IdentitySession,
): IdentityRequestedCheck[] {
  const metadata = session.metadataSanitized;
  const checks: IdentityRequestedCheck[] = [];
  if (metadata?.documentRequested === true) {
    checks.push("DOCUMENT_VERIFICATION");
  }
  if (metadata?.livenessRequested === true) {
    checks.push("LIVENESS");
  }
  if (metadata?.faceMatchOneToOneRequested === true) {
    checks.push("FACE_MATCH_ONE_TO_ONE");
  }
  return checks;
}

function validateIdentitySessionInput(
  input: IdentitySessionInput,
  providerCode: string,
): ProviderResult<never> | undefined {
  const invalidContext = validateMutationContext(input.context, providerCode);
  if (invalidContext) {
    return invalidContext;
  }
  if (
    !isNonEmptyString(input.sensitiveInputReference) ||
    !isNonEmptyString(input.documentType) ||
    !Array.isArray(input.requestedChecks) ||
    input.requestedChecks.length === 0 ||
    input.requestedChecks.some((check) => !isNonEmptyString(check)) ||
    (input.callbackReference !== undefined &&
      !isNonEmptyString(input.callbackReference)) ||
    (input.documentType === "PASSPORT_WITH_ISSUER" &&
      !isNonEmptyString(input.issuerCountry))
  ) {
    return invalidInput(input.context.correlationId, providerCode);
  }
  if (
    !["CPF", "RNM", "PASSPORT_WITH_ISSUER"].includes(input.documentType) ||
    input.requestedChecks.some((check) =>
      ![
        "DOCUMENT_VERIFICATION",
        "LIVENESS",
        "FACE_MATCH_ONE_TO_ONE",
      ].includes(check)
    )
  ) {
    return unsupportedCapability(input.context.correlationId, providerCode);
  }
  return undefined;
}

function validateMutationContext(
  context: ProviderMutationContext,
  providerCode: string,
): ProviderResult<never> | undefined {
  if (
    validateReadContext(context, providerCode) ||
    !isNonEmptyString(context.idempotencyKey) ||
    context.inputFingerprint.version !== 1 ||
    !isNonEmptyString(context.inputFingerprint.value) ||
    !isValidTimestamp(context.requestedAt)
  ) {
    return invalidInput(context.correlationId, providerCode);
  }
  return undefined;
}

function validateReadContext(
  context: ProviderReadContext,
  providerCode: string,
): ProviderResult<never> | undefined {
  if (
    !isNonEmptyString(context.condominiumId) ||
    !isNonEmptyString(context.requestId) ||
    !isNonEmptyString(context.participantId) ||
    !isNonEmptyString(context.correlationId)
  ) {
    return invalidInput(context.correlationId, providerCode);
  }
  return undefined;
}

function invalidInput(
  correlationId: string,
  providerCode: string,
): ProviderResult<never> {
  return providerFailure({
    code: "INVALID_INPUT",
    retryable: false,
    correlationId,
    providerCode,
  });
}

function unsupportedCapability(
  correlationId: string,
  providerCode: string,
): ProviderResult<never> {
  return providerFailure({
    code: "UNSUPPORTED_CAPABILITY",
    retryable: false,
    correlationId,
    providerCode,
  });
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

function isValidTimestamp(value: unknown): value is string {
  return isNonEmptyString(value) && Number.isFinite(Date.parse(value));
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
