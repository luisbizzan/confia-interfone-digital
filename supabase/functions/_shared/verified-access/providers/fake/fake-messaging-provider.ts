import type { Clock } from "../clock.ts";
import { VirtualClock } from "../clock.ts";
import {
  deriveFakeIdempotencyScope,
  deriveFakeIdentifier,
  type InvitationMessageInput,
  type InvitationProviderContext,
  type MessageDelivery,
  type MessageDeliveryStatus,
  type MessagingProviderReadContext,
  type ProviderContext,
  type StatusMessageInput,
} from "../contracts.ts";
import type { MessagingProvider } from "../messaging-provider.ts";
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
import type { MessagingScenario } from "./scenarios.ts";

export type FakeMessagingProviderOptions = Readonly<{
  scenario: MessagingScenario;
  providerCode?: string;
  store?: FakeProviderStore;
  clock?: Clock;
  latencyMs?: number;
  failuresBeforeSuccess?: number;
  maxRecords?: number;
}>;

export class FakeMessagingProvider implements MessagingProvider {
  readonly #scenario: MessagingScenario;
  readonly #providerCode: string;
  readonly #store: FakeProviderStore;
  readonly #clock: Clock;
  readonly #latencyMs: number;
  readonly #failuresBeforeSuccess: number;

  constructor(options: FakeMessagingProviderOptions) {
    this.#scenario = options.scenario;
    this.#providerCode = options.providerCode ?? "FAKE_MESSAGING";
    this.#store = options.store ??
      new InMemoryFakeProviderStore(options.maxRecords ?? 1_000);
    this.#clock = options.clock ?? new VirtualClock("2026-01-01T00:00:00.000Z");
    this.#latencyMs = validateLatency(options.latencyMs ?? 0);
    this.#failuresBeforeSuccess = validateFailuresBeforeSuccess(
      options.failuresBeforeSuccess ?? 0,
    );
  }

  sendInvitation(
    input: InvitationMessageInput,
  ): Promise<ProviderResult<MessageDelivery>> {
    return this.#send("sendInvitation", input);
  }

  sendStatusUpdate(
    input: StatusMessageInput,
  ): Promise<ProviderResult<MessageDelivery>> {
    return this.#send("sendStatusUpdate", input);
  }

  async getDeliveryStatus(
    providerMessageId: string,
    context: MessagingProviderReadContext,
  ): Promise<ProviderResult<MessageDeliveryStatus>> {
    await this.#clock.sleep(this.#latencyMs);
    const invalid = validateReadContext(context, this.#providerCode);
    if (invalid) {
      return invalid;
    }
    if (!isNonEmptyString(providerMessageId)) {
      return invalidInput(context.correlationId, this.#providerCode);
    }
    const idempotencyScope = parseFakeIdentifier(
      providerMessageId,
      "fake_message",
    );
    if (!idempotencyScope) {
      return providerFailure({
        code: "NOT_FOUND",
        retryable: false,
        correlationId: context.correlationId,
        providerCode: this.#providerCode,
      });
    }
    const belongsToTenant = ([
      "sendInvitation",
      "sendStatusUpdate",
    ] as const).some((operation) => {
      const stored = this.#store.get<MessageDelivery>({
        providerCode: this.#providerCode,
        operation,
        condominiumId: context.condominiumId,
        idempotencyKey: idempotencyScope,
      });
      return stored?.result.ok === true &&
        stored.result.value.providerMessageId === providerMessageId;
    });
    if (!belongsToTenant) {
      return providerFailure({
        code: "NOT_FOUND",
        retryable: false,
        correlationId: context.correlationId,
        providerCode: this.#providerCode,
      });
    }
    const failure = this.#scenarioFailure(context.correlationId);
    if (failure) {
      return failure;
    }
    return providerSuccess({
      providerMessageId,
      status: this.#scenario === "MESSAGE_DUPLICATE" ? "PENDING" : "DELIVERED",
      correlationId: context.correlationId,
      occurredAt: this.#clock.now().toISOString(),
      reasonCode: this.#scenario === "MESSAGE_DUPLICATE"
        ? "SYNTHETIC_MESSAGE_ACCEPTED"
        : undefined,
    });
  }

  async #send(
    operation: "sendInvitation" | "sendStatusUpdate",
    input: InvitationMessageInput | StatusMessageInput,
  ): Promise<ProviderResult<MessageDelivery>> {
    await this.#clock.sleep(this.#latencyMs);
    const context = input.context;
    const invalid = operation === "sendInvitation"
      ? validateInvitationInput(
        input as InvitationMessageInput,
        this.#providerCode,
      )
      : validateStatusInput(input as StatusMessageInput, this.#providerCode);
    if (invalid) {
      return invalid;
    }
    const idempotencyScope = await deriveFakeIdempotencyScope(
      this.#providerCode,
      operation,
      context.condominiumId,
      context.idempotencyKey,
    );
    const key = {
      providerCode: this.#providerCode,
      operation,
      condominiumId: context.condominiumId,
      idempotencyKey: idempotencyScope,
    };
    const attempt = beginIdempotentAttempt<MessageDelivery>(
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
    const failure = this.#scenarioFailure(context.correlationId);
    if (failure) {
      return failure;
    }
    const acceptedAt = this.#clock.now().toISOString();
    const providerMessageId = await deriveFakeIdentifier(
      "fake_message",
      this.#providerCode,
      operation,
      context.condominiumId,
      context.idempotencyKey,
      context.inputFingerprint,
    );
    return storeIdempotentResult(
      this.#store,
      key,
      context.inputFingerprint,
      providerSuccess({
        providerMessageId,
        providerCode: this.#providerCode,
        status: this.#scenario === "MESSAGE_DUPLICATE"
          ? "ACCEPTED"
          : "DELIVERED",
        correlationId: context.correlationId,
        acceptedAt,
        deliveredAt: this.#scenario === "MESSAGE_DUPLICATE"
          ? undefined
          : acceptedAt,
        metadataSanitized: { scenario: this.#scenario },
      }),
      acceptedAt,
      context.correlationId,
      this.#providerCode,
    );
  }

  #scenarioFailure(correlationId: string): ProviderResult<never> | undefined {
    if (this.#scenario === "MESSAGE_TIMEOUT") {
      return providerFailure({
        code: "TIMEOUT",
        retryable: true,
        correlationId,
        providerCode: this.#providerCode,
        retryAfterMs: 1_000,
      });
    }
    if (this.#scenario === "MESSAGE_PROVIDER_ERROR") {
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

function validateMutationContext(
  context: ProviderContext | InvitationProviderContext,
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

function validateInvitationInput(
  input: InvitationMessageInput,
  providerCode: string,
): ProviderResult<never> | undefined {
  const invalidContext = validateMutationContext(input.context, providerCode);
  if (invalidContext) {
    return invalidContext;
  }
  if (
    !isNonEmptyString(input.ephemeralDestination) ||
    !isNonEmptyString(input.templateCode) ||
    !isNonEmptyString(input.condominiumDisplayName) ||
    !isNonEmptyString(input.accessWindowLabel) ||
    !isNonEmptyString(input.opaqueInvitationLink) ||
    (input.hostDisplayName !== undefined &&
      !isNonEmptyString(input.hostDisplayName))
  ) {
    return invalidInput(input.context.correlationId, providerCode);
  }
  return validateChannel(
    input.channel,
    input.context.correlationId,
    providerCode,
  );
}

function validateStatusInput(
  input: StatusMessageInput,
  providerCode: string,
): ProviderResult<never> | undefined {
  const invalidContext = validateMutationContext(input.context, providerCode);
  if (invalidContext) {
    return invalidContext;
  }
  if (
    !isNonEmptyString(input.ephemeralDestination) ||
    !isNonEmptyString(input.templateCode) ||
    !isNonEmptyString(input.operationalStatusCode)
  ) {
    return invalidInput(input.context.correlationId, providerCode);
  }
  return validateChannel(
    input.channel,
    input.context.correlationId,
    providerCode,
  );
}

function validateChannel(
  channel: unknown,
  correlationId: string,
  providerCode: string,
): ProviderResult<never> | undefined {
  if (!isNonEmptyString(channel)) {
    return invalidInput(correlationId, providerCode);
  }
  if (!["SMS", "WHATSAPP", "EMAIL"].includes(String(channel))) {
    return providerFailure({
      code: "UNSUPPORTED_CAPABILITY",
      retryable: false,
      correlationId,
      providerCode,
    });
  }
  return undefined;
}

function validateReadContext(
  context: MessagingProviderReadContext,
  providerCode: string,
): ProviderResult<never> | undefined {
  if (
    !isNonEmptyString(context.condominiumId) ||
    !isNonEmptyString(context.requestId) ||
    !("participantId" in context
      ? isNonEmptyString(context.participantId)
      : isNonEmptyString(context.participantSlotId) &&
        isNonEmptyString(context.invitationId)) ||
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
  const match = new RegExp(`^${prefix}_([0-9a-f]{64})_[0-9a-f]{64}$`).exec(
    value,
  );
  return match?.[1];
}
