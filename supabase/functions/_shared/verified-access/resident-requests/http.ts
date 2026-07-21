export const MAX_BODY_BYTES = 16 * 1024;

export class HttpError extends Error {
  constructor(public status: number, public code: string) {
    super(code);
  }
}

export function jsonResponse(
  body: unknown,
  status = 200,
  request?: Request,
  allowedOrigins = "",
) {
  const headers = new Headers({ "Content-Type": "application/json" });
  const origin = request?.headers.get("Origin");
  if (
    origin &&
    allowedOrigins.split(",").map((value) => value.trim()).includes(origin)
  ) {
    headers.set("Access-Control-Allow-Origin", origin);
    headers.set("Vary", "Origin");
  }
  return new Response(JSON.stringify(body), { status, headers });
}

export function preflightResponse(request: Request, allowedOrigins = "") {
  const origin = request.headers.get("Origin");
  if (
    !origin ||
    !allowedOrigins.split(",").map((value) => value.trim()).includes(origin)
  ) {
    throw new HttpError(403, "ORIGIN_NOT_ALLOWED");
  }
  return new Response(null, {
    status: 204,
    headers: {
      "Access-Control-Allow-Origin": origin,
      "Access-Control-Allow-Headers":
        "authorization, content-type, x-correlation-id",
      "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
      "Access-Control-Max-Age": "600",
      "Vary": "Origin",
    },
  });
}

export function correlationId(request: Request) {
  const supplied = request.headers.get("x-correlation-id");
  if (supplied) {
    if (!/^[A-Za-z0-9._:-]{8,128}$/.test(supplied)) {
      throw new HttpError(400, "REQUEST_PAYLOAD_INVALID");
    }
    return supplied;
  }
  return crypto.randomUUID();
}

export async function strictJsonObject(
  request: Request,
  allowedKeys: readonly string[],
) {
  const contentType = request.headers.get("content-type")?.split(";", 1)[0]
    .trim().toLowerCase();
  if (contentType !== "application/json") {
    throw new HttpError(400, "REQUEST_PAYLOAD_INVALID");
  }

  const declaredLength = Number(request.headers.get("content-length") ?? "0");
  if (Number.isFinite(declaredLength) && declaredLength > MAX_BODY_BYTES) {
    throw new HttpError(413, "REQUEST_PAYLOAD_TOO_LARGE");
  }

  const text = await request.text();
  if (new TextEncoder().encode(text).byteLength > MAX_BODY_BYTES) {
    throw new HttpError(413, "REQUEST_PAYLOAD_TOO_LARGE");
  }

  let value: unknown;
  try {
    value = JSON.parse(text);
  } catch {
    throw new HttpError(400, "REQUEST_PAYLOAD_INVALID");
  }
  if (!isRecord(value)) {
    throw new HttpError(400, "REQUEST_PAYLOAD_INVALID");
  }

  const allowed = new Set(allowedKeys);
  if (Object.keys(value).some((key) => !allowed.has(key))) {
    throw new HttpError(400, "REQUEST_PAYLOAD_INVALID");
  }
  return value;
}

export function strictQuery(request: Request, allowedKeys: readonly string[]) {
  const url = new URL(request.url);
  const allowed = new Set(allowedKeys);
  for (const key of url.searchParams.keys()) {
    if (!allowed.has(key)) {
      throw new HttpError(400, "REQUEST_PAYLOAD_INVALID");
    }
  }
  return url.searchParams;
}

export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function handleError(
  error: unknown,
  request: Request,
  allowedOrigins = "",
) {
  if (error instanceof HttpError) {
    return jsonResponse(
      { error: { code: error.code } },
      error.status,
      request,
      allowedOrigins,
    );
  }
  return jsonResponse(
    { error: { code: "INTERNAL_ERROR" } },
    500,
    request,
    allowedOrigins,
  );
}
