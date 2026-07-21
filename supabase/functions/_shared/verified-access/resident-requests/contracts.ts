import { HttpError, isRecord } from "./http.ts";

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export const CREATE_KEYS = [
  "unitId",
  "requestType",
  "serviceTypeCode",
  "serviceDescription",
  "accessStartsAt",
  "accessEndsAt",
  "purpose",
  "operationalNote",
  "participantSlots",
  "clientRequestId",
] as const;
export const CANCEL_KEYS = [
  "requestId",
  "idempotencyKey",
  "reasonCode",
] as const;

export function createArgs(
  value: Record<string, unknown>,
  correlationId: string,
) {
  const unitId = requiredUuid(value.unitId);
  const requestType = requiredString(value.requestType);
  const accessStartsAt = requiredTimestamp(value.accessStartsAt);
  const accessEndsAt = requiredTimestamp(value.accessEndsAt);
  const participantSlots = value.participantSlots;
  const clientRequestId = requiredString(value.clientRequestId);
  if (!Number.isInteger(participantSlots) || (participantSlots as number) < 1) {
    invalid();
  }
  if (clientRequestId.length < 16 || clientRequestId.length > 128) invalid();
  if (!["VISITOR", "SERVICE_PROVIDER"].includes(requestType)) invalid();
  return {
    p_unit_id: unitId,
    p_request_type: requestType,
    p_service_type_code: optionalString(value.serviceTypeCode),
    p_service_description: optionalString(value.serviceDescription),
    p_access_starts_at: accessStartsAt,
    p_access_ends_at: accessEndsAt,
    p_purpose: optionalString(value.purpose),
    p_operational_note: optionalString(value.operationalNote),
    p_participant_slots: participantSlots,
    p_client_request_id: clientRequestId,
    p_correlation_id: correlationId,
  };
}

export function cancelArgs(
  value: Record<string, unknown>,
  correlationId: string,
) {
  const idempotencyKey = requiredString(value.idempotencyKey);
  if (idempotencyKey.length < 16 || idempotencyKey.length > 128) invalid();
  const reasonCode = value.reasonCode === undefined
    ? "RESIDENT_CANCELLED"
    : requiredString(value.reasonCode);
  if (reasonCode !== "RESIDENT_CANCELLED") invalid();
  return {
    p_request_id: requiredUuid(value.requestId),
    p_idempotency_key: idempotencyKey,
    p_reason_code: reasonCode,
    p_correlation_id: correlationId,
  };
}

export function requiredUuid(value: unknown) {
  const result = requiredString(value);
  if (!UUID.test(result)) invalid();
  return result;
}

export function optionalTimestamp(value: string | null) {
  if (value === null || value === "") return null;
  return requiredTimestamp(value);
}

export function optionalUuid(value: string | null) {
  if (value === null || value === "") return null;
  return requiredUuid(value);
}

export function optionalInteger(value: string | null, fallback: number) {
  if (value === null || value === "") return fallback;
  if (!/^\d+$/.test(value)) invalid();
  return Number(value);
}

export function assertObject(
  value: unknown,
): asserts value is Record<string, unknown> {
  if (!isRecord(value)) invalid();
}

function requiredTimestamp(value: unknown) {
  const result = requiredString(value);
  if (
    !/^\d{4}-\d{2}-\d{2}T.*(?:Z|[+-]\d{2}:\d{2})$/.test(result) ||
    Number.isNaN(Date.parse(result))
  ) invalid();
  return new Date(result).toISOString();
}

function requiredString(value: unknown) {
  if (typeof value !== "string" || value.length === 0) invalid();
  for (const character of value) {
    const code = character.charCodeAt(0);
    if (code <= 31 || code === 127) invalid();
  }
  return value;
}

function optionalString(value: unknown) {
  if (value === undefined || value === null || value === "") return null;
  return requiredString(value);
}

function invalid(): never {
  throw new HttpError(400, "REQUEST_PAYLOAD_INVALID");
}
