import type { Clock } from "../clock.ts";
import { VirtualClock } from "../clock.ts";
import {
  type BackgroundCapabilities,
  type BackgroundCheckInput,
  type BackgroundCheckRequest,
  type BackgroundCheckResult,
  deriveFakeIdempotencyScope,
  deriveFakeIdentifier,
  type ProviderReadContext,
} from "../contracts.ts";
import type { BackgroundCheckProvider } from "../background-check-provider.ts";
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
import type { BackgroundScenario } from "./scenarios.ts";

export type FakeBackgroundCheckProviderOptions = Readonly<{
  scenario: BackgroundScenario;
  providerCode?: string;
  store?: FakeProviderStore;
  clock?: Clock;
  latencyMs?: number;
  maxRecords?: number;
}>;

export class FakeBackgroundCheckProvider implements BackgroundCheckProvider {
  readonly #scenario: BackgroundScenario;
  readonly #providerCode: string;
  readonly #store: FakeProviderStore;
  readonly #clock: Clock;
  readonly #latencyMs: number;

  constructor(options: FakeBackgroundCheckProviderOptions) {
    this.#scenario = options.scenario;
    this.#providerCode = options.providerCode ?? "FAKE_BACKGROUND";
    this.#store = options.store ??
      new InMemoryFakeProviderStore(options.maxRecords ?? 1_000);
    this.#clock = options.clock ?? new VirtualClock("2026-01-01T00:00:00.000Z");
    this.#latencyMs = validateLatency(options.latencyMs ?? 0);
  }

  capabilities(): BackgroundCapabilities {
    return { coverageCodes: ["SYNTHETIC_SCOPE"], polling: true };
  }

  async requestCheck(
    input: BackgroundCheckInput,
  ): Promise<ProviderResult<BackgroundCheckRequest>> {
    await this.#clock.sleep(this.#latencyMs);
    const invalid = validateInput(input, this.#providerCode);
    if (invalid) {
      return invalid;
    }
    const idempotencyScope = await deriveFakeIdempotencyScope(
      this.#providerCode,
      "requestCheck",
      input.context.condominiumId,
      input.context.idempotencyKey,
    );
    const key = {
      providerCode: this.#providerCode,
      operation: "requestCheck",
      condominiumId: input.context.condominiumId,
      idempotencyKey: idempotencyScope,
    };
    const stored = readIdempotentResult<BackgroundCheckRequest>(
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
    const requestedAt = this.#clock.now().toISOString();
    const providerRequestId = await deriveFakeIdentifier(
      "fake_background",
      this.#providerCode,
      "requestCheck",
      input.context.condominiumId,
      input.context.idempotencyKey,
      input.context.inputFingerprint,
    );
    return storeIdempotentResult(
      this.#store,
      key,
      input.context.inputFingerprint,
      providerSuccess({
        providerRequestId,
        providerCode: this.#providerCode,
        status: "PENDING",
        correlationId: input.context.correlationId,
        requestedAt,
        metadataSanitized: { scenario: this.#scenario },
      }),
      requestedAt,
      input.context.correlationId,
      this.#providerCode,
    );
  }

  async getResult(
    providerRequestId: string,
    context: ProviderReadContext,
  ): Promise<ProviderResult<BackgroundCheckResult>> {
    await this.#clock.sleep(this.#latencyMs);
    const idempotencyScope = parseFakeIdentifier(
      providerRequestId,
      "fake_background",
    );
    if (!idempotencyScope) {
      return providerFailure({
        code: "NOT_FOUND",
        retryable: false,
        correlationId: context.correlationId,
        providerCode: this.#providerCode,
      });
    }
    const request = this.#store.get<BackgroundCheckRequest>({
      providerCode: this.#providerCode,
      operation: "requestCheck",
      condominiumId: context.condominiumId,
      idempotencyKey: idempotencyScope,
    });
    if (
      !request?.result.ok ||
      request.result.value.providerRequestId !== providerRequestId
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
    const now = this.#clock.now();
    return providerSuccess({
      providerRequestId,
      providerCode: this.#providerCode,
      correlationId: context.correlationId,
      status: backgroundStatus(this.#scenario),
      reasonCode: backgroundReasonCode(this.#scenario),
      coverageCodes: ["SYNTHETIC_SCOPE"],
      occurredAt: now.toISOString(),
      expiresAt: new Date(now.getTime() + 24 * 60 * 60_000).toISOString(),
      metadataSanitized: { scenario: this.#scenario },
    });
  }

  #scenarioFailure(correlationId: string): ProviderResult<never> | undefined {
    if (this.#scenario === "BACKGROUND_TIMEOUT") {
      return providerFailure({
        code: "TIMEOUT",
        retryable: true,
        correlationId,
        providerCode: this.#providerCode,
        retryAfterMs: 1_000,
      });
    }
    if (this.#scenario === "BACKGROUND_PROVIDER_ERROR") {
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

function backgroundStatus(
  scenario: BackgroundScenario,
): BackgroundCheckResult["status"] {
  switch (scenario) {
    case "BACKGROUND_SUCCESS":
      return "NEGATIVE_CERTIFICATE";
    case "BACKGROUND_ADVERSE_REVIEW":
      return "ADVERSE_INFORMATION_REVIEW";
    case "BACKGROUND_MANUAL_CONFIRMATION":
      return "MANUAL_CONFIRMATION_REQUIRED";
    case "BACKGROUND_INCONCLUSIVE":
      return "INCONCLUSIVE";
    case "BACKGROUND_TIMEOUT":
    case "BACKGROUND_PROVIDER_ERROR":
      throw new TypeError("Technical scenarios return ProviderFailure");
  }
}

function backgroundReasonCode(scenario: BackgroundScenario): string {
  switch (scenario) {
    case "BACKGROUND_SUCCESS":
      return "SYNTHETIC_NEGATIVE_CERTIFICATE";
    case "BACKGROUND_ADVERSE_REVIEW":
      return "SYNTHETIC_ADVERSE_REVIEW_REQUIRED";
    case "BACKGROUND_MANUAL_CONFIRMATION":
      return "SYNTHETIC_MANUAL_CONFIRMATION_REQUIRED";
    case "BACKGROUND_INCONCLUSIVE":
      return "SYNTHETIC_BACKGROUND_INCONCLUSIVE";
    case "BACKGROUND_TIMEOUT":
    case "BACKGROUND_PROVIDER_ERROR":
      throw new TypeError("Technical scenarios return ProviderFailure");
  }
}

function validateInput(
  input: BackgroundCheckInput,
  providerCode: string,
): ProviderResult<never> | undefined {
  const context = input.context;
  if (
    !context.condominiumId || !context.requestId || !context.participantId ||
    !context.correlationId || !context.idempotencyKey ||
    context.inputFingerprint.version !== 1 || !context.inputFingerprint.value ||
    !input.verifiedIdentityReference || !input.approvalReference ||
    input.scopeCodes.length === 0
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
