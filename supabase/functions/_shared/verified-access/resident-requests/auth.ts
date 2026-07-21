import { HttpError } from "./http.ts";

export type AuthDependencies = {
  fetch: typeof fetch;
  supabaseUrl: string;
  anonKey: string;
};

export function runtimeDependencies(): AuthDependencies {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseUrl || !anonKey) {
    throw new HttpError(500, "INTERNAL_ERROR");
  }
  return { fetch, supabaseUrl, anonKey };
}

export async function callAuthenticatedRpc(
  request: Request,
  rpcName: string,
  args: Record<string, unknown>,
  dependencies = runtimeDependencies(),
) {
  const authorization = request.headers.get("Authorization");
  const match = authorization?.match(/^Bearer\s+([^\s]+)$/i);
  if (!match) {
    throw new HttpError(401, "AUTHENTICATION_REQUIRED");
  }
  const token = match[1];
  const authHeaders = {
    apikey: dependencies.anonKey,
    Authorization: `Bearer ${token}`,
  };
  const userResponse = await dependencies.fetch(
    `${dependencies.supabaseUrl}/auth/v1/user`,
    {
      headers: authHeaders,
    },
  );
  if (!userResponse.ok) {
    throw new HttpError(401, "AUTHENTICATION_REQUIRED");
  }

  const rpcResponse = await dependencies.fetch(
    `${dependencies.supabaseUrl}/rest/v1/rpc/${rpcName}`,
    {
      method: "POST",
      headers: { ...authHeaders, "Content-Type": "application/json" },
      body: JSON.stringify(args),
    },
  );
  const payload = await rpcResponse.json().catch(() => null);
  if (!rpcResponse.ok) {
    const code = typeof payload?.message === "string"
      ? payload.message.split(":", 1)[0]
      : "INTERNAL_ERROR";
    throw mapRpcError(code);
  }
  return payload;
}

function mapRpcError(code: string) {
  const statuses: Record<string, number> = {
    AUTHENTICATION_REQUIRED: 401,
    FEATURE_DISABLED: 403,
    UNIT_NOT_AUTHORIZED: 403,
    REQUEST_NOT_FOUND: 404,
    IDEMPOTENCY_CONFLICT: 409,
    COMMAND_IN_PROGRESS: 409,
    REQUEST_STATE_CONFLICT: 409,
    POLICY_NOT_AVAILABLE: 422,
    SERVICE_TYPE_NOT_AVAILABLE: 422,
    ACCESS_WINDOW_INVALID: 422,
    PARTICIPANT_LIMIT_INVALID: 422,
    REQUEST_PAYLOAD_INVALID: 400,
  };
  return new HttpError(
    statuses[code] ?? 500,
    statuses[code] ? code : "INTERNAL_ERROR",
  );
}
