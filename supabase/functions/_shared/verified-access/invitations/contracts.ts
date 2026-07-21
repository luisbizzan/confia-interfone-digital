import { HttpError } from "./http.ts";

export const ISSUE_KEYS = ["participantSlotId", "idempotencyKey"] as const;
export const RESEND_KEYS = ["invitationId", "idempotencyKey"] as const;
export const REVOKE_KEYS = [
  "invitationId",
  "idempotencyKey",
  "reasonCode",
] as const;
export const LIST_QUERY_KEYS = ["requestId"] as const;

export function issueArgs(
  body: Record<string, unknown>,
  tokenHash: string,
  correlationId: string,
) {
  return {
    p_participant_slot_id: uuid(body.participantSlotId),
    p_token_hash: tokenHash,
    p_idempotency_key: key(body.idempotencyKey),
    p_correlation_id: correlationId,
  };
}

export function resendArgs(
  body: Record<string, unknown>,
  tokenHash: string,
  correlationId: string,
) {
  return {
    p_invitation_id: uuid(body.invitationId),
    p_token_hash: tokenHash,
    p_idempotency_key: key(body.idempotencyKey),
    p_correlation_id: correlationId,
  };
}

export function revokeArgs(
  body: Record<string, unknown>,
  correlationId: string,
) {
  const reasonCode = body.reasonCode ?? "RESIDENT_REVOKED";
  if (reasonCode !== "RESIDENT_REVOKED") invalid();
  return {
    p_invitation_id: uuid(body.invitationId),
    p_idempotency_key: key(body.idempotencyKey),
    p_reason_code: reasonCode,
    p_correlation_id: correlationId,
  };
}

export function listArgs(requestId: unknown) {
  return { p_request_id: uuid(requestId) };
}

function uuid(value: unknown): string {
  if (
    typeof value !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(value)
  ) invalid();
  return value as string;
}

function key(value: unknown): string {
  if (typeof value !== "string" || !/^[A-Za-z0-9._:-]{16,128}$/.test(value)) {
    invalid();
  }
  return value as string;
}

function invalid(): never {
  throw new HttpError(400, "INVITATION_PAYLOAD_INVALID");
}
