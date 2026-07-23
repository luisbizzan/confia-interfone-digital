import { HttpError } from "./http.ts";

export const EXCHANGE_KEYS = ["invitationToken", "idempotencyKey"] as const;
export const START_KEYS = ["idempotencyKey"] as const;
export const SUBMIT_KEYS = [
  "idempotencyKey",
  "nationality",
  "fullName",
  "dateOfBirth",
  "documentType",
  "documentValue",
  "issuerCountry",
  "phone",
  "guardianName",
  "guardianRelationship",
  "privacyNoticeVersion",
  "termsVersion",
  "privacyAcknowledged",
  "termsAccepted",
] as const;

export type RegistrationInput = {
  idempotencyKey: string;
  nationality: "BR" | "FOREIGN";
  fullName: string;
  dateOfBirth: string;
  documentType: "CPF" | "RNM" | "PASSPORT" | null;
  documentValue: string | null;
  issuerCountry: string | null;
  phone: string | null;
  isMinor: boolean;
  guardianName: string | null;
  guardianRelationship: string | null;
  privacyNoticeVersion: string;
  termsVersion: string;
};

export function requiredIdempotencyKey(value: unknown): string {
  if (typeof value !== "string" || !/^[A-Za-z0-9._:-]{16,128}$/.test(value)) {
    invalid();
  }
  return value as string;
}

export function requiredInvitationToken(value: unknown): string {
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]{43}$/.test(value)) {
    invalid();
  }
  return value as string;
}

export function validateRegistrationInput(
  body: Record<string, unknown>,
  now = new Date(),
): RegistrationInput {
  const idempotencyKey = requiredIdempotencyKey(body.idempotencyKey);
  if (body.nationality !== "BR" && body.nationality !== "FOREIGN") invalid();
  const nationality = body.nationality as "BR" | "FOREIGN";
  const fullName = text(body.fullName, 3, 160);
  const dateOfBirth = isoDate(body.dateOfBirth, now);
  const isMinor = ageOn(dateOfBirth, now) < 18;
  const privacyNoticeVersion = version(body.privacyNoticeVersion);
  const termsVersion = version(body.termsVersion);
  if (body.privacyAcknowledged !== true || body.termsAccepted !== true) {
    invalid();
  }

  let documentType = body.documentType as RegistrationInput["documentType"];
  let documentValue = typeof body.documentValue === "string"
    ? body.documentValue.trim().toUpperCase()
    : null;
  let issuerCountry = typeof body.issuerCountry === "string"
    ? body.issuerCountry.trim().toUpperCase()
    : null;
  if (nationality === "BR") {
    if (!documentValue && isMinor) {
      documentType = null;
      issuerCountry = null;
    } else {
      if (
        documentType !== "CPF" || !documentValue || !validCpf(documentValue)
      ) invalid();
      documentValue = digits(documentValue);
      issuerCountry = null;
    }
  } else {
    if (documentType === "RNM") {
      if (!documentValue || !/^[A-Z][0-9]{6}[A-Z0-9]$/.test(documentValue)) {
        invalid();
      }
      issuerCountry = null;
    } else if (documentType === "PASSPORT") {
      if (
        !documentValue || !/^[A-Z0-9]{6,12}$/.test(documentValue) ||
        !issuerCountry || !/^[A-Z]{2}$/.test(issuerCountry)
      ) invalid();
    } else invalid();
  }

  const guardianName = optionalText(body.guardianName, 3, 160);
  const guardianRelationship = optionalText(body.guardianRelationship, 2, 80);
  if (isMinor && (!guardianName || !guardianRelationship)) invalid();
  if (!isMinor && (guardianName || guardianRelationship)) invalid();
  const phone = normalizePhone(body.phone, nationality);

  return {
    idempotencyKey,
    nationality,
    fullName,
    dateOfBirth,
    documentType,
    documentValue,
    issuerCountry,
    phone,
    isMinor,
    guardianName,
    guardianRelationship,
    privacyNoticeVersion,
    termsVersion,
  };
}

export function validCpf(value: string): boolean {
  const cpf = digits(value);
  if (cpf.length !== 11 || /^(\d)\1{10}$/.test(cpf)) return false;
  const digit = (length: number) => {
    let sum = 0;
    for (let index = 0; index < length; index++) {
      sum += Number(cpf[index]) * (length + 1 - index);
    }
    const result = 11 - (sum % 11);
    return result >= 10 ? 0 : result;
  };
  return digit(9) === Number(cpf[9]) && digit(10) === Number(cpf[10]);
}

export function ageOn(dateValue: string, now: Date): number {
  const [year, month, day] = dateValue.split("-").map(Number);
  let age = now.getUTCFullYear() - year;
  if (
    now.getUTCMonth() + 1 < month ||
    (now.getUTCMonth() + 1 === month && now.getUTCDate() < day)
  ) age--;
  return age;
}

function isoDate(value: unknown, now: Date): string {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    invalid();
  }
  const parsed = new Date(`${value}T00:00:00.000Z`);
  if (
    !Number.isFinite(parsed.getTime()) ||
    parsed.toISOString().slice(0, 10) !== value || parsed > now
  ) invalid();
  return value;
}

function normalizePhone(
  value: unknown,
  nationality: "BR" | "FOREIGN",
): string | null {
  if (value === undefined || value === null || value === "") return null;
  if (typeof value !== "string") invalid();
  let normalized = value.replace(/[\s().-]/g, "");
  if (!normalized.startsWith("+") && nationality === "BR") {
    normalized = `+55${normalized}`;
  }
  if (!/^\+[1-9][0-9]{7,14}$/.test(normalized)) invalid();
  return normalized;
}

function version(value: unknown): string {
  if (typeof value !== "string" || !/^[A-Za-z0-9._:-]{3,64}$/.test(value)) {
    invalid();
  }
  return value as string;
}

function text(value: unknown, minimum: number, maximum: number): string {
  if (typeof value !== "string") invalid();
  const normalized = value.trim().replace(/\s+/g, " ");
  const hasControlCharacter = Array.from(normalized).some((character) => {
    const code = character.charCodeAt(0);
    return code < 32 || code === 127;
  });
  if (
    normalized.length < minimum || normalized.length > maximum ||
    hasControlCharacter
  ) invalid();
  return normalized;
}

function optionalText(
  value: unknown,
  minimum: number,
  maximum: number,
): string | null {
  if (value === undefined || value === null || value === "") return null;
  return text(value, minimum, maximum);
}

function digits(value: string): string {
  return value.replace(/\D/g, "");
}

function invalid(): never {
  throw new HttpError(400, "PAYLOAD_INVALID");
}
