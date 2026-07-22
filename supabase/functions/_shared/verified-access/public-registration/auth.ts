import { HttpError } from "./http.ts";

export type RpcDependencies = {
  fetch: typeof fetch;
  supabaseUrl: string;
  serviceRoleKey: string;
};

export function runtimeRpcDependencies(): RpcDependencies {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    throw new HttpError(500, "INTERNAL_ERROR");
  }
  return { fetch, supabaseUrl, serviceRoleKey };
}

export async function callPublicRpc(
  name: string,
  args: Record<string, unknown>,
  dependencies = runtimeRpcDependencies(),
): Promise<Record<string, unknown>> {
  const response = await dependencies.fetch(
    `${dependencies.supabaseUrl}/rest/v1/rpc/${name}`,
    {
      method: "POST",
      headers: {
        apikey: dependencies.serviceRoleKey,
        Authorization: `Bearer ${dependencies.serviceRoleKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(args),
    },
  );
  const payload = await response.json().catch(() => null);
  if (!response.ok) {
    const internalCode = typeof payload?.message === "string"
      ? payload.message.split(":", 1)[0]
      : "INTERNAL_ERROR";
    const status = internalCode === "IDEMPOTENCY_CONFLICT" ||
        internalCode === "COMMAND_IN_PROGRESS"
      ? 409
      : internalCode === "PUBLIC_REGISTRATION_PAYLOAD_INVALID"
      ? 400
      : internalCode === "FEATURE_DISABLED"
      ? 404
      : 500;
    throw new HttpError(
      status,
      status === 500 ? "INTERNAL_ERROR" : internalCode,
    );
  }
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    throw new HttpError(500, "INTERNAL_ERROR");
  }
  const record = payload as Record<string, unknown>;
  if (record.rateLimited === true) {
    throw new HttpError(
      429,
      "RATE_LIMITED",
      Number(record.retryAfterSeconds) || 60,
    );
  }
  if (
    record.resultCode === "PUBLIC_ACCESS_UNAVAILABLE" ||
    record.resultCode === "REGISTRATION_UNAVAILABLE"
  ) {
    throw new HttpError(404, "ACCESS_UNAVAILABLE");
  }
  return record;
}
