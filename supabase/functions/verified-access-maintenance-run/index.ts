const JOBS = {
  expire_invitations: "verified_access_expire_invitations",
  expire_public_sessions: "verified_access_expire_public_sessions",
  purge_public_commands: "verified_access_purge_public_commands",
  purge_rate_limit_buckets: "verified_access_purge_rate_limit_buckets",
  reconcile_public_registration_state:
    "verified_access_reconcile_public_registration_state",
  process_outbox: "verified_access_process_outbox",
  apply_retention_policy: "verified_access_apply_retention_policy",
} as const;

type JobName = keyof typeof JOBS;
type Environment = {
  get(name: string): string | undefined;
};
type RateLimiter = {
  take(now: number): boolean;
};

export type MaintenanceDependencies = {
  env?: Environment;
  fetch?: typeof fetch;
  now?: () => number;
  rateLimiter?: RateLimiter;
};

const defaultRateLimiter = createRateLimiter(10, 60_000);

export function createRateLimiter(
  limit: number,
  windowMs: number,
): RateLimiter {
  let windowStartedAt = 0;
  let count = 0;
  return {
    take(now: number) {
      if (windowStartedAt === 0 || now - windowStartedAt >= windowMs) {
        windowStartedAt = now;
        count = 0;
      }
      count += 1;
      return count <= limit;
    },
  };
}

export async function handleRequest(
  request: Request,
  dependencies: MaintenanceDependencies = {},
): Promise<Response> {
  const env = dependencies.env ?? Deno.env;
  const requestFetch = dependencies.fetch ?? fetch;
  const now = dependencies.now ?? Date.now;
  const rateLimiter = dependencies.rateLimiter ?? defaultRateLimiter;
  const headers = { "Content-Type": "application/json" };

  if (request.method !== "POST") {
    return new Response(
      JSON.stringify({ error: { code: "METHOD_NOT_ALLOWED" } }),
      { status: 405, headers },
    );
  }

  const expectedSecret = env.get("VERIFIED_ACCESS_MAINTENANCE_SECRET");
  const suppliedSecret = request.headers.get("x-maintenance-secret");
  if (
    expectedSecret === undefined ||
    expectedSecret.length < 32 ||
    suppliedSecret === null ||
    !constantTimeEqual(expectedSecret, suppliedSecret)
  ) {
    return new Response(
      JSON.stringify({ error: { code: "MAINTENANCE_UNAUTHORIZED" } }),
      { status: 401, headers },
    );
  }

  if (!rateLimiter.take(now())) {
    return new Response(
      JSON.stringify({ error: { code: "MAINTENANCE_RATE_LIMITED" } }),
      { status: 429, headers: { ...headers, "Retry-After": "60" } },
    );
  }

  try {
    const input = await strictInput(request);
    const supabaseUrl = requiredEnvironment(env, "SUPABASE_URL");
    const serviceRoleKey = requiredEnvironment(
      env,
      "SUPABASE_SERVICE_ROLE_KEY",
    );
    const correlationId = request.headers.get("x-correlation-id") ??
      crypto.randomUUID();
    if (!validCorrelationId(correlationId)) {
      return new Response(
        JSON.stringify({ error: { code: "MAINTENANCE_INPUT_INVALID" } }),
        { status: 400, headers },
      );
    }

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 25_000);
    let rpcResponse: Response;
    try {
      rpcResponse = await requestFetch(
        `${supabaseUrl}/rest/v1/rpc/${JOBS[input.job]}`,
        {
          method: "POST",
          headers: {
            apikey: serviceRoleKey,
            Authorization: `Bearer ${serviceRoleKey}`,
            "Content-Type": "application/json",
            "x-correlation-id": correlationId,
          },
          body: JSON.stringify({
            p_batch_size: input.batchSize,
            p_dry_run: input.dryRun,
            p_correlation_id: correlationId,
          }),
          signal: controller.signal,
        },
      );
    } finally {
      clearTimeout(timeout);
    }

    if (!rpcResponse.ok) {
      return new Response(
        JSON.stringify({ error: { code: "MAINTENANCE_JOB_FAILED" } }),
        { status: 502, headers },
      );
    }

    const result = sanitizeResult(await rpcResponse.json());
    return new Response(
      JSON.stringify({ data: result, correlationId }),
      { status: 200, headers },
    );
  } catch {
    return new Response(
      JSON.stringify({ error: { code: "MAINTENANCE_REQUEST_FAILED" } }),
      { status: 400, headers },
    );
  }
}

async function strictInput(request: Request): Promise<{
  job: JobName;
  batchSize: number;
  dryRun: boolean;
}> {
  const contentType = request.headers.get("content-type")?.split(";")[0].trim();
  const contentLength = Number(request.headers.get("content-length") ?? "0");
  if (
    contentType !== "application/json" ||
    !Number.isFinite(contentLength) ||
    contentLength > 4_096
  ) {
    throw new Error("invalid request");
  }

  const text = await request.text();
  if (new TextEncoder().encode(text).byteLength > 4_096) {
    throw new Error("invalid request");
  }
  const body: unknown = JSON.parse(text);
  if (
    body === null ||
    Array.isArray(body) ||
    typeof body !== "object"
  ) {
    throw new Error("invalid request");
  }

  const record = body as Record<string, unknown>;
  const keys = Object.keys(record).sort();
  if (keys.join(",") !== "batchSize,dryRun,job") {
    throw new Error("invalid request");
  }
  if (
    typeof record.job !== "string" ||
    !(record.job in JOBS) ||
    typeof record.batchSize !== "number" ||
    !Number.isInteger(record.batchSize) ||
    record.batchSize < 1 ||
    record.batchSize > 500 ||
    typeof record.dryRun !== "boolean"
  ) {
    throw new Error("invalid request");
  }

  return {
    job: record.job as JobName,
    batchSize: record.batchSize,
    dryRun: record.dryRun,
  };
}

function sanitizeResult(value: unknown): Record<string, unknown> {
  if (value === null || Array.isArray(value) || typeof value !== "object") {
    throw new Error("invalid result");
  }
  const record = value as Record<string, unknown>;
  const allowed = new Set([
    "job",
    "dryRun",
    "processed",
    "skipped",
    "failed",
    "remaining",
  ]);
  if (Object.keys(record).some((key) => !allowed.has(key))) {
    throw new Error("invalid result");
  }
  if (
    typeof record.job !== "string" ||
    typeof record.dryRun !== "boolean" ||
    !validCounter(record.processed) ||
    !validCounter(record.skipped) ||
    !validCounter(record.failed) ||
    !validCounter(record.remaining)
  ) {
    throw new Error("invalid result");
  }
  return record;
}

function validCounter(value: unknown): value is number {
  return typeof value === "number" && Number.isInteger(value) && value >= 0;
}

function validCorrelationId(value: string): boolean {
  return value.length >= 8 &&
    value.length <= 128 &&
    value === value.trim() &&
    !Array.from(value).some((character) => {
      const code = character.charCodeAt(0);
      return code <= 31 || code === 127;
    });
}

function requiredEnvironment(env: Environment, name: string): string {
  const value = env.get(name);
  if (value === undefined || value.length === 0) {
    throw new Error("missing environment");
  }
  return value;
}

function constantTimeEqual(left: string, right: string): boolean {
  const encoder = new TextEncoder();
  const leftBytes = encoder.encode(left);
  const rightBytes = encoder.encode(right);
  let difference = leftBytes.length ^ rightBytes.length;
  const length = Math.max(leftBytes.length, rightBytes.length);
  for (let index = 0; index < length; index += 1) {
    difference |= (leftBytes[index] ?? 0) ^ (rightBytes[index] ?? 0);
  }
  return difference === 0;
}

if (import.meta.main) {
  Deno.serve((request) => handleRequest(request));
}
