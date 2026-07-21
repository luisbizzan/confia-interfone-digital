import { createProviderInputFingerprint } from "../providers/contracts.ts";
import { FakeMessagingProvider } from "../providers/fake/fake-messaging-provider.ts";
import {
  MESSAGING_SCENARIOS,
  type MessagingScenario,
} from "../providers/fake/scenarios.ts";
import { HttpError } from "./http.ts";

type InvitationRecord = Record<string, unknown>;
export type DispatchResult = Readonly<
  {
    providerCode: string;
    status: string;
    providerMessageId: string;
    previewLink?: string;
  }
>;

export async function dispatchFakeInvitation(
  record: InvitationRecord,
  rawToken: string,
  correlationId: string,
): Promise<DispatchResult> {
  const scenarioValue =
    Deno.env.get("VERIFIED_ACCESS_FAKE_MESSAGING_SCENARIO") ??
      "MESSAGE_SUCCESS";
  if (!MESSAGING_SCENARIOS.includes(scenarioValue as MessagingScenario)) {
    throw new HttpError(500, "INTERNAL_ERROR");
  }
  const invitationId = required(record.invitationId);
  const participantSlotId = required(record.participantSlotId);
  const requestId = required(record.requestId);
  const condominiumId = required(record.condominiumId);
  const generation = Number(record.tokenVersion);
  const previewEnabled =
    Deno.env.get("VERIFIED_ACCESS_FAKE_PREVIEW_ENABLED") === "true";
  const base = Deno.env.get("VERIFIED_ACCESS_PUBLIC_BASE_URL") ??
    "https://local.invalid/verified-access/register";
  const previewLink = `${base}#invitation=${encodeURIComponent(rawToken)}`;
  const reference = `invitation:${invitationId}:generation:${generation}`;
  const inputFingerprint = await createProviderInputFingerprint(
    "sendInvitation",
    {
      channel: "WHATSAPP",
      destinationReferenceFingerprint: "LOCAL_FAKE_DESTINATION",
      templateCode: "VERIFIED_ACCESS_INVITATION",
      messagePayloadFingerprint: reference,
      opaqueInvitationLinkReference: reference,
    },
  );
  const provider = new FakeMessagingProvider({
    scenario: scenarioValue as MessagingScenario,
  });
  const result = await provider.sendInvitation({
    context: {
      condominiumId,
      requestId,
      participantSlotId,
      invitationId,
      correlationId,
      idempotencyKey: required(record.commandId),
      inputFingerprint,
      requestedAt: new Date().toISOString(),
    },
    channel: "WHATSAPP",
    ephemeralDestination: "LOCAL_FAKE_DESTINATION",
    templateCode: "VERIFIED_ACCESS_INVITATION",
    condominiumDisplayName: "Condominium",
    accessWindowLabel: "AUTHORIZED_WINDOW",
    opaqueInvitationLink: previewLink,
  });
  if (!result.ok) {
    const status =
      result.error.code === "TIMEOUT" || result.error.code === "UNAVAILABLE"
        ? 503
        : 502;
    throw new HttpError(status, `MESSAGING_${result.error.code}`);
  }
  return {
    providerCode: result.value.providerCode,
    status: result.value.status,
    providerMessageId: result.value.providerMessageId,
    ...(previewEnabled ? { previewLink } : {}),
  };
}

function required(value: unknown): string {
  if (typeof value !== "string" || value.length === 0) {
    throw new HttpError(500, "INTERNAL_ERROR");
  }
  return value;
}
