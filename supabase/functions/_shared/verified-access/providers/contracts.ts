import type { SanitizedMetadata } from "./result.ts";

export type CorrelationId = string;
export type IdempotencyKey = string;
export type IsoTimestamp = string;

export type ProviderInputFingerprint = Readonly<{
  version: 1;
  value: string;
}>;

export type ProviderContext = Readonly<{
  condominiumId: string;
  requestId: string;
  participantId: string;
  correlationId: CorrelationId;
  idempotencyKey: IdempotencyKey;
  inputFingerprint: ProviderInputFingerprint;
  requestedAt: IsoTimestamp;
}>;

export type ProviderReadContext = Pick<
  ProviderContext,
  "condominiumId" | "requestId" | "participantId" | "correlationId"
>;

export type ProviderMutationContext =
  & ProviderReadContext
  & Readonly<{
    idempotencyKey: IdempotencyKey;
    inputFingerprint: ProviderInputFingerprint;
    requestedAt: IsoTimestamp;
  }>;

export type IdentityCapabilities = Readonly<{
  documentVerification: boolean;
  liveness: boolean;
  faceMatchOneToOne: boolean;
  polling: boolean;
  cancellation: boolean;
}>;

export type IdentityRequestedCheck =
  | "DOCUMENT_VERIFICATION"
  | "LIVENESS"
  | "FACE_MATCH_ONE_TO_ONE";

export type IdentitySessionInput = Readonly<{
  context: ProviderContext;
  documentType: "CPF" | "RNM" | "PASSPORT_WITH_ISSUER";
  issuerCountry?: string;
  requestedChecks: readonly IdentityRequestedCheck[];
  sensitiveInputReference: string;
  callbackReference?: string;
}>;

export type IdentitySession = Readonly<{
  providerSessionId: string;
  providerCode: string;
  status: "PENDING";
  correlationId: CorrelationId;
  createdAt: IsoTimestamp;
  expiresAt: IsoTimestamp;
  metadataSanitized?: SanitizedMetadata;
}>;

export type ProviderIdentityLevel =
  | "UNVERIFIED"
  | "CONTACT_VERIFIED"
  | "LIVENESS_VERIFIED"
  | "IDENTITY_VERIFIED";

export type IdentityAssuranceLevel = ProviderIdentityLevel | "MANUAL_VERIFIED";

export type IdentityResult = Readonly<{
  providerSessionId: string;
  providerCode: string;
  correlationId: CorrelationId;
  status: "VERIFIED" | "INCONCLUSIVE" | "TECHNICAL_ERROR" | "EXPIRED";
  level: ProviderIdentityLevel;
  documentStatus: "NOT_PERFORMED" | "VALID" | "INVALID" | "INCONCLUSIVE";
  livenessStatus: "NOT_PERFORMED" | "PASSED" | "FAILED" | "INCONCLUSIVE";
  faceMatchStatus: "NOT_PERFORMED" | "MATCH" | "NO_MATCH" | "INCONCLUSIVE";
  reasonCode: string;
  occurredAt: IsoTimestamp;
  expiresAt?: IsoTimestamp;
  metadataSanitized?: SanitizedMetadata;
}>;

export type IdentityCancellation = Readonly<{
  providerSessionId: string;
  status: "CANCELLED" | "ALREADY_TERMINAL";
  correlationId: CorrelationId;
  occurredAt: IsoTimestamp;
}>;

export type BackgroundCapabilities = Readonly<{
  coverageCodes: readonly string[];
  polling: boolean;
}>;

export type BackgroundCheckInput = Readonly<{
  context: ProviderContext;
  verifiedIdentityReference: string;
  scopeCodes: readonly string[];
  approvalReference: string;
  cutoffAt: IsoTimestamp;
}>;

export type BackgroundCheckRequest = Readonly<{
  providerRequestId: string;
  providerCode: string;
  status: "PENDING";
  correlationId: CorrelationId;
  requestedAt: IsoTimestamp;
  metadataSanitized?: SanitizedMetadata;
}>;

export type BackgroundCheckResult = Readonly<{
  providerRequestId: string;
  providerCode: string;
  correlationId: CorrelationId;
  status:
    | "NEGATIVE_CERTIFICATE"
    | "ADVERSE_INFORMATION_REVIEW"
    | "MANUAL_CONFIRMATION_REQUIRED"
    | "INCONCLUSIVE"
    | "PROVIDER_ERROR"
    | "EXPIRED";
  reasonCode: string;
  coverageCodes: readonly string[];
  occurredAt: IsoTimestamp;
  expiresAt?: IsoTimestamp;
  metadataSanitized?: SanitizedMetadata;
}>;

export type MessageChannel = "SMS" | "WHATSAPP" | "EMAIL";

export type InvitationMessageInput = Readonly<{
  context: ProviderContext;
  channel: MessageChannel;
  ephemeralDestination: string;
  templateCode: string;
  condominiumDisplayName: string;
  hostDisplayName?: string;
  accessWindowLabel: string;
  opaqueInvitationLink: string;
}>;

export type StatusMessageInput = Readonly<{
  context: ProviderContext;
  channel: MessageChannel;
  ephemeralDestination: string;
  templateCode: string;
  operationalStatusCode: string;
}>;

export type MessageDelivery = Readonly<{
  providerMessageId: string;
  providerCode: string;
  status: "ACCEPTED" | "DELIVERED";
  correlationId: CorrelationId;
  acceptedAt: IsoTimestamp;
  deliveredAt?: IsoTimestamp;
  metadataSanitized?: SanitizedMetadata;
}>;

export type MessageDeliveryStatus = Readonly<{
  providerMessageId: string;
  status: "PENDING" | "DELIVERED" | "FAILED" | "EXPIRED";
  correlationId: CorrelationId;
  reasonCode?: string;
  occurredAt: IsoTimestamp;
}>;

export type CreateSessionFingerprintInput = Readonly<{
  documentType: IdentitySessionInput["documentType"];
  issuerCountry?: string;
  requestedChecks: readonly IdentityRequestedCheck[];
  sensitiveInputReferenceFingerprint: string;
  callbackReference?: string;
}>;

export type CancelSessionFingerprintInput = Readonly<{
  providerSessionId: string;
}>;

export type RequestCheckFingerprintInput = Readonly<{
  verifiedIdentityReferenceFingerprint: string;
  scopeCodes: readonly string[];
  approvalReference: string;
  cutoffAt: IsoTimestamp;
}>;

export type SendInvitationFingerprintInput = Readonly<{
  channel: MessageChannel;
  destinationReferenceFingerprint: string;
  templateCode: string;
  messagePayloadFingerprint: string;
  opaqueInvitationLinkReference: string;
}>;

export type SendStatusUpdateFingerprintInput = Readonly<{
  channel: MessageChannel;
  destinationReferenceFingerprint: string;
  templateCode: string;
  operationalStatusCode: string;
  messagePayloadFingerprint: string;
}>;

export type ProviderFingerprintOperation =
  | "createSession"
  | "cancelSession"
  | "requestCheck"
  | "sendInvitation"
  | "sendStatusUpdate";

export type ProviderFingerprintInputMap = Readonly<{
  createSession: CreateSessionFingerprintInput;
  cancelSession: CancelSessionFingerprintInput;
  requestCheck: RequestCheckFingerprintInput;
  sendInvitation: SendInvitationFingerprintInput;
  sendStatusUpdate: SendStatusUpdateFingerprintInput;
}>;

type CanonicalValue =
  | null
  | boolean
  | number
  | string
  | readonly CanonicalValue[]
  | { readonly [key: string]: CanonicalValue | undefined };

export async function createProviderInputFingerprint<
  Operation extends ProviderFingerprintOperation,
>(
  operation: Operation,
  input: ProviderFingerprintInputMap[Operation],
): Promise<ProviderInputFingerprint> {
  const payload = selectFingerprintPayload(operation, input);
  return {
    version: 1,
    value: await sha256Hex(canonicalJson(payload)),
  };
}

export async function deriveFakeIdentifier(
  prefix: string,
  providerCode: string,
  operation: string,
  condominiumId: string,
  idempotencyKey: IdempotencyKey,
  inputFingerprint: ProviderInputFingerprint,
): Promise<string> {
  const scope = await deriveFakeIdempotencyScope(
    providerCode,
    operation,
    condominiumId,
    idempotencyKey,
  );
  const value = await sha256Hex(
    canonicalJson({
      condominiumId,
      idempotencyKey,
      inputFingerprint: inputFingerprint.value,
      inputFingerprintVersion: inputFingerprint.version,
      operation,
      providerCode,
    }),
  );
  return `${prefix}_${scope}_${value}`;
}

export function deriveFakeIdempotencyScope(
  providerCode: string,
  operation: string,
  condominiumId: string,
  idempotencyKey: IdempotencyKey,
): Promise<string> {
  return sha256Hex(
    canonicalJson({
      condominiumId,
      idempotencyKey,
      operation,
      providerCode,
    }),
  );
}

function selectFingerprintPayload<
  Operation extends ProviderFingerprintOperation,
>(
  operation: Operation,
  input: ProviderFingerprintInputMap[Operation],
): CanonicalValue {
  switch (operation) {
    case "createSession": {
      const value = input as CreateSessionFingerprintInput;
      assertAllowedKeys(value, [
        "callbackReference",
        "documentType",
        "issuerCountry",
        "requestedChecks",
        "sensitiveInputReferenceFingerprint",
      ]);
      return {
        callbackReference: value.callbackReference,
        documentType: value.documentType,
        issuerCountry: value.issuerCountry,
        requestedChecks: [...value.requestedChecks].sort(),
        sensitiveInputReferenceFingerprint:
          value.sensitiveInputReferenceFingerprint,
      };
    }
    case "cancelSession": {
      const value = input as CancelSessionFingerprintInput;
      assertAllowedKeys(value, ["providerSessionId"]);
      return { providerSessionId: value.providerSessionId };
    }
    case "requestCheck": {
      const value = input as RequestCheckFingerprintInput;
      assertAllowedKeys(value, [
        "approvalReference",
        "cutoffAt",
        "scopeCodes",
        "verifiedIdentityReferenceFingerprint",
      ]);
      return {
        approvalReference: value.approvalReference,
        cutoffAt: normalizeUtc(value.cutoffAt),
        scopeCodes: [...value.scopeCodes].sort(),
        verifiedIdentityReferenceFingerprint:
          value.verifiedIdentityReferenceFingerprint,
      };
    }
    case "sendInvitation": {
      const value = input as SendInvitationFingerprintInput;
      assertAllowedKeys(value, [
        "channel",
        "destinationReferenceFingerprint",
        "messagePayloadFingerprint",
        "opaqueInvitationLinkReference",
        "templateCode",
      ]);
      return {
        channel: value.channel,
        destinationReferenceFingerprint: value.destinationReferenceFingerprint,
        messagePayloadFingerprint: value.messagePayloadFingerprint,
        opaqueInvitationLinkReference: value.opaqueInvitationLinkReference,
        templateCode: value.templateCode,
      };
    }
    case "sendStatusUpdate": {
      const value = input as SendStatusUpdateFingerprintInput;
      assertAllowedKeys(value, [
        "channel",
        "destinationReferenceFingerprint",
        "messagePayloadFingerprint",
        "operationalStatusCode",
        "templateCode",
      ]);
      return {
        channel: value.channel,
        destinationReferenceFingerprint: value.destinationReferenceFingerprint,
        messagePayloadFingerprint: value.messagePayloadFingerprint,
        operationalStatusCode: value.operationalStatusCode,
        templateCode: value.templateCode,
      };
    }
  }
}

function assertAllowedKeys(
  input: object,
  allowedKeys: readonly string[],
): void {
  const allowed = new Set(allowedKeys);
  for (const key of Object.keys(input)) {
    if (!allowed.has(key)) {
      throw new TypeError(`Unknown fingerprint field: ${key}`);
    }
  }
}

function normalizeUtc(value: IsoTimestamp): IsoTimestamp {
  const date = new Date(value);
  if (!Number.isFinite(date.getTime())) {
    throw new TypeError("Fingerprint timestamp must be valid ISO 8601");
  }
  return date.toISOString();
}

function canonicalJson(value: CanonicalValue): string {
  if (
    value === null || typeof value === "boolean" || typeof value === "string"
  ) {
    return JSON.stringify(value);
  }
  if (typeof value === "number") {
    if (!Number.isFinite(value)) {
      throw new TypeError("Fingerprint numbers must be finite");
    }
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    return `[${value.map(canonicalJson).join(",")}]`;
  }
  const entries = Object.entries(value)
    .filter((entry): entry is [string, CanonicalValue] =>
      entry[1] !== undefined
    )
    .sort(([left], [right]) => left.localeCompare(right));
  return `{${
    entries.map(([key, item]) =>
      `${JSON.stringify(key)}:${canonicalJson(item)}`
    ).join(",")
  }}`;
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(
    new Uint8Array(digest),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
}

export type {
  ProviderError,
  ProviderErrorCode,
  ProviderFailure,
  ProviderResult,
  ProviderSuccess,
  SanitizedMetadata,
} from "./result.ts";
