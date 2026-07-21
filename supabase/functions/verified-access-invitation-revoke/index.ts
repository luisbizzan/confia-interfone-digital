import {
  type AuthDependencies,
  callAuthenticatedRpc,
} from "../_shared/verified-access/invitations/auth.ts";
import {
  REVOKE_KEYS,
  revokeArgs,
} from "../_shared/verified-access/invitations/contracts.ts";
import {
  correlationId,
  handleError,
  jsonResponse,
  preflightResponse,
  strictJsonObject,
} from "../_shared/verified-access/invitations/http.ts";

export async function handleRequest(
  request: Request,
  dependencies?: AuthDependencies,
) {
  const origins = Deno.env.get("VERIFIED_ACCESS_ALLOWED_ORIGINS") ?? "";
  try {
    if (request.method === "OPTIONS") {
      return preflightResponse(request, origins);
    }
    if (request.method !== "POST") {
      return jsonResponse(
        { error: { code: "METHOD_NOT_ALLOWED" } },
        405,
        request,
        origins,
      );
    }
    const body = await strictJsonObject(request, REVOKE_KEYS);
    const payload = await callAuthenticatedRpc(
      request,
      "verified_access_revoke_resident_invitation",
      revokeArgs(body, correlationId(request)),
      dependencies,
    );
    return jsonResponse({ data: payload }, 200, request, origins);
  } catch (error) {
    return handleError(error, request, origins);
  }
}
if (import.meta.main) Deno.serve((request) => handleRequest(request));
