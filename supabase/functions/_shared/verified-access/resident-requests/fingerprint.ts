export function canonicalCreateFingerprintInput(args: Record<string, unknown>) {
  return {
    unitId: args.p_unit_id,
    requestType: args.p_request_type,
    serviceTypeCode: normalize(args.p_service_type_code, true),
    serviceDescription: normalize(args.p_service_description),
    accessStartsAt: args.p_access_starts_at,
    accessEndsAt: args.p_access_ends_at,
    purpose: normalize(args.p_purpose),
    operationalNote: normalize(args.p_operational_note),
    participantSlots: args.p_participant_slots,
  };
}

export function canonicalCancelFingerprintInput(args: Record<string, unknown>) {
  return { requestId: args.p_request_id, reasonCode: args.p_reason_code };
}

function normalize(value: unknown, uppercase = false) {
  if (typeof value !== "string") return null;
  const normalized = value.trim().replace(/[\t ]+/g, " ");
  if (!normalized) return null;
  return uppercase ? normalized.toUpperCase() : normalized;
}
