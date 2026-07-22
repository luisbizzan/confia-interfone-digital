import { keyedFingerprint, sha256Fingerprint } from "./crypto.ts";
import { HttpError } from "./http.ts";

export function bearerToken(request: Request): string {
  const match = request.headers.get("Authorization")?.match(
    /^Bearer\s+([A-Za-z0-9_-]{43})$/,
  );
  if (!match) throw new HttpError(404, "ACCESS_UNAVAILABLE");
  return match[1];
}

export function clientAddress(request: Request): string {
  const forwarded = request.headers.get("X-Forwarded-For")?.split(",", 1)[0]
    .trim();
  const value = forwarded || request.headers.get("CF-Connecting-IP")?.trim() ||
    "unknown";
  return value.slice(0, 128);
}

export async function sessionCredentials(
  request: Request,
  rateKey: string,
): Promise<{ sessionHash: string; rateFingerprint: string }> {
  const raw = bearerToken(request);
  return {
    sessionHash: await sha256Fingerprint(raw),
    rateFingerprint: await keyedFingerprint(rateKey, "session-rate", raw),
  };
}
