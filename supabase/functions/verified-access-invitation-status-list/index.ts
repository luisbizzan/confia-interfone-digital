import {
  type AuthDependencies,
  callAuthenticatedRpc,
} from "../_shared/verified-access/invitations/auth.ts";
import {
  LIST_QUERY_KEYS,
  listArgs,
} from "../_shared/verified-access/invitations/contracts.ts";
import {
  handleError,
  jsonResponse,
  preflightResponse,
  strictQuery,
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
    if (request.method !== "GET") {
      return jsonResponse(
        { error: { code: "METHOD_NOT_ALLOWED" } },
        405,
        request,
        origins,
      );
    }
    const query = strictQuery(request, LIST_QUERY_KEYS);
    const payload = await callAuthenticatedRpc(
      request,
      "verified_access_list_resident_invitation_status",
      listArgs(query.get("requestId")),
      dependencies,
    );
    return jsonResponse({ data: payload }, 200, request, origins);
  } catch (error) {
    return handleError(error, request, origins);
  }
}
if (import.meta.main) Deno.serve((request) => handleRequest(request));
