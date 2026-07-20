import type { Clock } from "../clock.ts";
import { VirtualClock } from "../clock.ts";
import {
  deriveFakeIdempotencyScope,
  deriveFakeIdentifier,
  type InvitationMessageInput,
  type MessageDelivery,
  type MessageDeliveryStatus,
  type ProviderContext,
  type ProviderReadContext,
  type StatusMessageInput,
} from "../contracts.ts";
import type { MessagingProvider } from "../messaging-provider.ts";
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
import type { MessagingScenario } from "./scenarios.ts";

export type FakeMessagingProviderOptions = Readonly<{
  scenario: MessagingScenario;
  providerCode?: string;
  store?: FakeProviderStore;
  clock?: Clock;
  latencyMs?: number;
  maxRecords?: number;
}>;

export class FakeMessagingProvider implements MessagingProvider {
  readonly #scenario: MessagingScenario;
  readonly #providerCode: string;
  readonly #store: FakeProviderStore;
  readonly #clock: Clock;
  readonly #latencyMs: number;

  constructor(options: FakeMessagingProviderOptions) {
    this.#scenario = options.scenario;
    this.#providerCode = options.providerCode ?? "FAKE_MESSAGING";
    this.#store = options.store ??
      new InMemoryFakeProviderStore(options.maxRecords ?? 1_000);
    this.#clock = options.clock ?? new VirtualClock("2026-01-01T00:00:00.000Z");
    this.#latencyMs = validateLatency(options.latencyMs ?? 0);
  }

  sendInvitation(
    input: InvitationMessageInput,
  ): Promise<ProviderResult<MessageDelivery>> {
    return this.#send("sendInvitation", input.context);
  }

  sendStatusUpdate(
    input: StatusMessageInput,
  ): Promise<ProviderResult<MessageDelivery>> {
    return this.#send("sendStatusUpdate", input.context);
  }

  async getDeliveryStatus(
    providerMessageId: string,
    context: ProviderReadContext,
  ): Promise<ProviderResult<MessageDeliveryStatus>> {
    await this.#clock.sleep(this.#latencyMs);
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
    context: ProviderContext,
  ): Promise<ProviderResult<MessageDelivery>> {
    await this.#clock.sleep(this.#latencyMs);
    const invalid = validateContext(context, this.#providerCode);
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
    const stored = readIdempotentResult<MessageDelivery>(
      this.#store,
      key,
      context.inputFingerprint,
      context.correlationId,
      this.#providerCode,
    );
    if (stored) {
      return stored;
    }
    const failure = this.#scenarioFailure(context.correlationId);
    if (failure) {
      return storeIdempotentResult(
        this.#store,
        key,
        context.inputFingerprint,
        failure,
        this.#clock.now().toISOString(),
        context.correlationId,
        this.#providerCode,
      );
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

function validateContext(
  context: ProviderContext,
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
  const match = new RegExp(`^${prefix}_([0-9a-f]{64})_[0-9a-f]{64}$`).exec(
    value,
  );
  return match?.[1];
}
