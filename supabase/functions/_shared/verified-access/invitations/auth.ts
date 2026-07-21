import { HttpError } from "./http.ts";

export type AuthDependencies = {
  fetch: typeof fetch;
  supabaseUrl: string;
  anonKey: string;
};

export function runtimeDependencies(): AuthDependencies {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseUrl || !anonKey) throw new HttpError(500, "INTERNAL_ERROR");
  return { fetch, supabaseUrl, anonKey };
}

export async function callAuthenticatedRpc(
  request: Request,
  rpcName: string,
  args: Record<string, unknown>,
  dependencies = runtimeDependencies(),
) {
  const match = request.headers.get("Authorization")?.match(
    /^Bearer\s+([^\s]+)$/i,
  );
  if (!match) throw new HttpError(401, "AUTHENTICATION_REQUIRED");
  const headers = {
    apikey: dependencies.anonKey,
    Authorization: `Bearer ${match[1]}`,
  };
  const user = await dependencies.fetch(
    `${dependencies.supabaseUrl}/auth/v1/user`,
    { headers },
  );
  if (!user.ok) throw new HttpError(401, "AUTHENTICATION_REQUIRED");
  const response = await dependencies.fetch(
    `${dependencies.supabaseUrl}/rest/v1/rpc/${rpcName}`,
    {
      method: "POST",
      headers: { ...headers, "Content-Type": "application/json" },
      body: JSON.stringify(args),
    },
  );
  const payload = await response.json().catch(() => null);
  if (!response.ok) {
    const code = typeof payload?.message === "string"
      ? payload.message.split(":", 1)[0]
      : "INTERNAL_ERROR";
    const statuses: Record<string, number> = {
      AUTHENTICATION_REQUIRED: 401,
      FEATURE_DISABLED: 403,
      UNIT_NOT_AUTHORIZED: 403,
      REQUEST_NOT_FOUND: 404,
      SLOT_NOT_FOUND: 404,
      INVITATION_TARGET_NOT_FOUND: 404,
      INVITATION_NOT_FOUND: 404,
      IDEMPOTENCY_CONFLICT: 409,
      COMMAND_IN_PROGRESS: 409,
      REQUEST_STATE_CONFLICT: 409,
      SLOT_STATE_CONFLICT: 409,
      INVITATION_STATE_CONFLICT: 409,
      POLICY_NOT_AVAILABLE: 422,
      INVITATION_EXPIRED: 422,
      INVITATION_PAYLOAD_INVALID: 400,
      INVITATION_TOKEN_HASH_INVALID: 400,
    };
    throw new HttpError(
      statuses[code] ?? 500,
      statuses[code] ? code : "INTERNAL_ERROR",
    );
  }
  return payload;
}
