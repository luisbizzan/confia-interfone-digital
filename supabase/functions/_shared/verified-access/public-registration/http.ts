export class HttpError extends Error {
  constructor(
    public readonly status: number,
    public readonly code: string,
    public readonly retryAfter?: number,
  ) {
    super(code);
  }
}

const BODY_LIMIT = 16 * 1024;

export function allowedOrigin(request: Request): string | null {
  const origin = request.headers.get("Origin");
  const allowed = (Deno.env.get("VERIFIED_ACCESS_PUBLIC_ALLOWED_ORIGINS") ?? "")
    .split(",").map((value) => value.trim()).filter(Boolean);
  return origin && allowed.includes(origin) ? origin : null;
}

export function securityHeaders(request: Request): Headers {
  const headers = new Headers({
    "Cache-Control": "no-store, max-age=0",
    "Pragma": "no-cache",
    "Referrer-Policy": "no-referrer",
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
    "Content-Security-Policy":
      "default-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'",
    "Vary": "Origin",
  });
  const origin = allowedOrigin(request);
  if (origin) {
    headers.set("Access-Control-Allow-Origin", origin);
    headers.set("Access-Control-Allow-Credentials", "true");
  }
  return headers;
}

export function jsonResponse(
  request: Request,
  body: unknown,
  status = 200,
  retryAfter?: number,
): Response {
  const headers = securityHeaders(request);
  headers.set("Content-Type", "application/json; charset=utf-8");
  if (retryAfter) headers.set("Retry-After", String(retryAfter));
  return new Response(JSON.stringify(body), { status, headers });
}

export function preflightResponse(request: Request): Response {
  const origin = allowedOrigin(request);
  if (!origin) {
    return jsonResponse(
      request,
      { error: { code: "ACCESS_UNAVAILABLE" } },
      403,
    );
  }
  const headers = securityHeaders(request);
  headers.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  headers.set(
    "Access-Control-Allow-Headers",
    "authorization, content-type, x-correlation-id",
  );
  headers.set("Access-Control-Max-Age", "600");
  return new Response(null, { status: 204, headers });
}

export async function strictJsonObject(
  request: Request,
  allowedKeys: readonly string[],
): Promise<Record<string, unknown>> {
  const declared = Number(request.headers.get("Content-Length") ?? "0");
  if (Number.isFinite(declared) && declared > BODY_LIMIT) {
    throw new HttpError(413, "PAYLOAD_TOO_LARGE");
  }
  const bytes = new Uint8Array(await request.arrayBuffer());
  if (bytes.byteLength > BODY_LIMIT) {
    throw new HttpError(413, "PAYLOAD_TOO_LARGE");
  }
  let value: unknown;
  try {
    value = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  } catch {
    throw new HttpError(400, "PAYLOAD_INVALID");
  }
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new HttpError(400, "PAYLOAD_INVALID");
  }
  const allowed = new Set(allowedKeys);
  if (Object.keys(value).some((key) => !allowed.has(key))) {
    throw new HttpError(400, "PAYLOAD_INVALID");
  }
  return value as Record<string, unknown>;
}

export function correlationId(request: Request): string {
  const supplied = request.headers.get("X-Correlation-Id")?.trim();
  if (supplied && /^[A-Za-z0-9._:-]{8,128}$/.test(supplied)) return supplied;
  return `public-${crypto.randomUUID()}`;
}

export function handleError(error: unknown, request: Request): Response {
  if (error instanceof HttpError) {
    const publicCode = error.status === 429
      ? "RATE_LIMITED"
      : error.status >= 500
      ? "INTERNAL_ERROR"
      : error.code;
    return jsonResponse(
      request,
      { error: { code: publicCode } },
      error.status,
      error.retryAfter,
    );
  }
  return jsonResponse(request, { error: { code: "INTERNAL_ERROR" } }, 500);
}
