export type RegistrationContext = {
  condominiumName: string;
  requestType: string;
  startsAt: string;
  endsAt: string;
  timezone: string;
  sessionStatus: "ACTIVE" | "COMPLETED";
};

export type RegistrationPayload = {
  idempotencyKey: string;
  nationality: "BR" | "FOREIGN";
  fullName: string;
  dateOfBirth: string;
  documentType: "CPF" | "RNM" | "PASSPORT" | null;
  documentValue: string | null;
  issuerCountry: string | null;
  phone: string | null;
  guardianName: string | null;
  guardianRelationship: string | null;
  privacyNoticeVersion: string;
  termsVersion: string;
  privacyAcknowledged: boolean;
  termsAccepted: boolean;
};

const SESSION_KEY = "verified-access-public-session";

export class PublicApiError extends Error {
  constructor(public readonly code: string, public readonly status: number) {
    super(code);
  }
}

export async function exchangeInvitation(invitationToken: string, idempotencyKey: string) {
  const response = await request<{ sessionToken: string; context: RegistrationContext }>("verified-access-public-invitation-exchange", {
    method: "POST",
    body: JSON.stringify({ invitationToken, idempotencyKey }),
  });
  sessionStorage.setItem(SESSION_KEY, response.sessionToken);
  return response.context;
}

export function registrationContext() {
  return authenticated<RegistrationContext>("verified-access-public-registration-get", { method: "GET" });
}

export function startRegistration(idempotencyKey: string) {
  return authenticated("verified-access-public-registration-start", { method: "POST", body: JSON.stringify({ idempotencyKey }) });
}

export function submitRegistration(payload: RegistrationPayload) {
  return authenticated("verified-access-public-registration-submit", { method: "POST", body: JSON.stringify(payload) });
}

export function registrationStatus() {
  return authenticated<{ sessionStatus: string; registrationStatus: string; submittedAt?: string }>("verified-access-public-registration-status", { method: "GET" });
}

export function clearSession() {
  sessionStorage.removeItem(SESSION_KEY);
}

async function authenticated<T = Record<string, unknown>>(path: string, init: RequestInit): Promise<T> {
  const token = sessionStorage.getItem(SESSION_KEY);
  if (!token) throw new PublicApiError("ACCESS_UNAVAILABLE", 404);
  return request<T>(path, { ...init, headers: { ...init.headers, Authorization: `Bearer ${token}` } });
}

async function request<T>(path: string, init: RequestInit): Promise<T> {
  const base = process.env.NEXT_PUBLIC_VERIFIED_ACCESS_EDGE_BASE_URL?.replace(/\/$/, "");
  if (!base) throw new PublicApiError("CONFIGURATION_UNAVAILABLE", 500);
  const response = await fetch(`${base}/${path}`, {
    ...init,
    cache: "no-store",
    headers: { "Content-Type": "application/json", "X-Correlation-Id": `web-${crypto.randomUUID()}`, ...init.headers },
  });
  const payload = await response.json().catch(() => null);
  if (!response.ok) throw new PublicApiError(payload?.error?.code ?? "INTERNAL_ERROR", response.status);
  return payload.data as T;
}
