import {
  type AuthDependencies,
  callAuthenticatedRpc,
} from "../_shared/verified-access/resident-requests/auth.ts";
import { requiredUuid } from "../_shared/verified-access/resident-requests/contracts.ts";
import {
  handleError,
  jsonResponse,
  preflightResponse,
  strictQuery,
} from "../_shared/verified-access/resident-requests/http.ts";

export async function handleRequest(
  request: Request,
  dependencies?: AuthDependencies,
) {
  const allowedOrigins = Deno.env.get("VERIFIED_ACCESS_ALLOWED_ORIGINS") ?? "";
  try {
    if (request.method === "OPTIONS") {
      return preflightResponse(request, allowedOrigins);
    }
    if (request.method !== "GET") {
      return jsonResponse(
        { error: { code: "METHOD_NOT_ALLOWED" } },
        405,
        request,
        allowedOrigins,
      );
    }
    const query = strictQuery(request, ["unitId"]);
    const payload = await callAuthenticatedRpc(
      request,
      "verified_access_list_resident_service_types",
      {
        p_unit_id: requiredUuid(query.get("unitId")),
      },
      dependencies,
    );
    return jsonResponse({ data: payload }, 200, request, allowedOrigins);
  } catch (error) {
    return handleError(error, request, allowedOrigins);
  }
}

if (import.meta.main) Deno.serve((request) => handleRequest(request));
