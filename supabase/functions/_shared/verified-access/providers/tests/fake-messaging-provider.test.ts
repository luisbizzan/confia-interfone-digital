import {
  createProviderInputFingerprint,
  type InvitationMessageInput,
  type ProviderContext,
  type StatusMessageInput,
} from "../contracts.ts";
import { FakeMessagingProvider } from "../fake/fake-messaging-provider.ts";
import { MESSAGING_SCENARIOS } from "../fake/scenarios.ts";
import type { ProviderResult } from "../result.ts";

Deno.test("messaging fake covers every scenario without real transport", async () => {
  for (const scenario of MESSAGING_SCENARIOS) {
    const provider = new FakeMessagingProvider({ scenario });
    let thrown = false;
    let delivery:
      | Awaited<ReturnType<typeof provider.sendInvitation>>
      | undefined;
    try {
      delivery = await provider.sendInvitation(
        await invitationInput(`key-${scenario}`),
      );
    } catch {
      thrown = true;
    }
    assert(!thrown, `${scenario} threw an expected provider failure`);
    assert(delivery !== undefined);
    if (scenario === "MESSAGE_TIMEOUT") {
      assertFailureCode(delivery, "TIMEOUT");
      continue;
    }
    if (scenario === "MESSAGE_PROVIDER_ERROR") {
      assertFailureCode(delivery, "UNAVAILABLE");
      continue;
    }
    const sent = mustSuccess(delivery);
    const status = mustSuccess(
      await provider.getDeliveryStatus(
        sent.providerMessageId,
        {
          condominiumId: "condominium-message",
          requestId: "request-message",
          participantId: "participant-message",
          correlationId: `result-${scenario}`,
        },
      ),
    );
    assert(status.status === "DELIVERED" || status.status === "PENDING");
  }
});

Deno.test("message sends are idempotent per operation and reject conflicts", async () => {
  const provider = new FakeMessagingProvider({ scenario: "MESSAGE_DUPLICATE" });
  const invitation = await invitationInput("message-idempotency");
  const first = await provider.sendInvitation(invitation);
  const repeated = await provider.sendInvitation({
    ...invitation,
    context: { ...invitation.context, correlationId: "correlation-repeat" },
  });
  assertEquals(
    mustSuccess(first).providerMessageId,
    mustSuccess(repeated).providerMessageId,
  );

  const conflict = await provider.sendInvitation({
    ...invitation,
    context: {
      ...invitation.context,
      inputFingerprint: { version: 1, value: "changed-message-fingerprint" },
    },
  });
  assertFailureCode(conflict, "CONFLICT");

  const statusInput = await statusMessageInput("message-idempotency");
  const statusDelivery = mustSuccess(
    await provider.sendStatusUpdate(statusInput),
  );
  assert(
    statusDelivery.providerMessageId !== mustSuccess(first).providerMessageId,
  );
});

Deno.test("message identifiers and metadata contain no destination or payload", async () => {
  const provider = new FakeMessagingProvider({ scenario: "MESSAGE_SUCCESS" });
  const marker = "SYNTHETIC_PRIVATE_DESTINATION";
  const input = await invitationInput("message-pii-safety");
  const delivery = mustSuccess(
    await provider.sendInvitation({
      ...input,
      ephemeralDestination: marker,
    }),
  );
  const serialized = JSON.stringify(delivery);
  assert(!serialized.includes(marker));
  assert(!serialized.includes(input.opaqueInvitationLink));
});

Deno.test("message delivery lookup is tenant isolated", async () => {
  const provider = new FakeMessagingProvider({ scenario: "MESSAGE_SUCCESS" });
  const delivery = mustSuccess(
    await provider.sendInvitation(await invitationInput("tenant-isolation")),
  );
  assertFailureCode(
    await provider.getDeliveryStatus(delivery.providerMessageId, {
      condominiumId: "other-condominium",
      requestId: "request-message",
      participantId: "participant-message",
      correlationId: "cross-tenant-result",
    }),
    "NOT_FOUND",
  );
});

async function invitationInput(
  idempotencyKey: string,
): Promise<InvitationMessageInput> {
  const inputFingerprint = await createProviderInputFingerprint(
    "sendInvitation",
    {
      channel: "WHATSAPP",
      destinationReferenceFingerprint: "opaque-destination-fingerprint",
      templateCode: "SYNTHETIC_INVITATION",
      messagePayloadFingerprint: "opaque-message-payload-fingerprint",
      opaqueInvitationLinkReference: "opaque-link-reference",
    },
  );
  return {
    context: context(idempotencyKey, inputFingerprint),
    channel: "WHATSAPP",
    ephemeralDestination: "synthetic-destination",
    templateCode: "SYNTHETIC_INVITATION",
    condominiumDisplayName: "Synthetic Condominium",
    hostDisplayName: "Synthetic Host",
    accessWindowLabel: "Synthetic Window",
    opaqueInvitationLink: "synthetic-opaque-link",
  };
}

async function statusMessageInput(
  idempotencyKey: string,
): Promise<StatusMessageInput> {
  const inputFingerprint = await createProviderInputFingerprint(
    "sendStatusUpdate",
    {
      channel: "EMAIL",
      destinationReferenceFingerprint: "opaque-destination-fingerprint",
      templateCode: "SYNTHETIC_STATUS",
      operationalStatusCode: "SYNTHETIC_PENDING",
      messagePayloadFingerprint: "opaque-status-payload-fingerprint",
    },
  );
  return {
    context: context(idempotencyKey, inputFingerprint),
    channel: "EMAIL",
    ephemeralDestination: "synthetic-destination",
    templateCode: "SYNTHETIC_STATUS",
    operationalStatusCode: "SYNTHETIC_PENDING",
  };
}

function context(
  idempotencyKey: string,
  inputFingerprint: ProviderContext["inputFingerprint"],
): ProviderContext {
  return {
    condominiumId: "condominium-message",
    requestId: "request-message",
    participantId: "participant-message",
    correlationId: `correlation-${idempotencyKey}`,
    idempotencyKey,
    inputFingerprint,
    requestedAt: "2026-07-19T00:00:00.000Z",
  };
}

function mustSuccess<T>(result: ProviderResult<T>): T {
  if (!result.ok) {
    throw new Error(`Expected success, received ${result.error.code}`);
  }
  return result.value;
}

function assertFailureCode<T>(result: ProviderResult<T>, code: string): void {
  assert(!result.ok, `Expected ${code}, received success`);
  assertEquals(result.error.code, code);
}

function assert(
  condition: unknown,
  message = "Assertion failed",
): asserts condition {
  if (!condition) throw new Error(message);
}

function assertEquals<T>(actual: T, expected: T): void {
  if (!Object.is(actual, expected)) {
    throw new Error(`Expected ${String(expected)}, received ${String(actual)}`);
  }
}
