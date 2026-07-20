export type SanitizedMetadata = Readonly<
  Record<string, string | number | boolean | null>
>;

export type ProviderErrorCode =
  | "INVALID_INPUT"
  | "UNSUPPORTED_CAPABILITY"
  | "UNAVAILABLE"
  | "TIMEOUT"
  | "RATE_LIMITED"
  | "AUTHENTICATION_FAILED"
  | "INVALID_PROVIDER_RESPONSE"
  | "NOT_FOUND"
  | "CONFLICT"
  | "CANCELLED";

export type ProviderError = Readonly<{
  code: ProviderErrorCode;
  retryable: boolean;
  correlationId: string;
  providerCode?: string;
  retryAfterMs?: number;
  metadataSanitized?: SanitizedMetadata;
}>;

export type ProviderSuccess<T> = Readonly<{
  ok: true;
  value: T;
}>;

export type ProviderFailure = Readonly<{
  ok: false;
  error: ProviderError;
}>;

export type ProviderResult<T> = ProviderSuccess<T> | ProviderFailure;

export function providerSuccess<T>(value: T): ProviderSuccess<T> {
  return { ok: true, value };
}

export function providerFailure(error: ProviderError): ProviderFailure {
  return { ok: false, error };
}
