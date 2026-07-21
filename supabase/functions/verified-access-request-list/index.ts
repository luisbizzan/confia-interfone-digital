import {
  type AuthDependencies,
  callAuthenticatedRpc,
} from "../_shared/verified-access/resident-requests/auth.ts";
import {
  optionalInteger,
  optionalTimestamp,
  optionalUuid,
} from "../_shared/verified-access/resident-requests/contracts.ts";
import {
  handleError,
  jsonResponse,
  preflightResponse,
  strictQuery,
} from "../_shared/verified-access/resident-requests/http.ts";

const QUERY_KEYS = [
  "status",
  "requestType",
  "from",
  "to",
  "cursorCreatedAt",
  "cursorId",
  "limit",
] as const;

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
    const query = strictQuery(request, QUERY_KEYS);
    const payload = await callAuthenticatedRpc(
      request,
      "verified_access_list_resident_requests",
      {
        p_status: query.get("status"),
        p_request_type: query.get("requestType"),
        p_from: optionalTimestamp(query.get("from")),
        p_to: optionalTimestamp(query.get("to")),
        p_cursor_created_at: optionalTimestamp(query.get("cursorCreatedAt")),
        p_cursor_id: optionalUuid(query.get("cursorId")),
        p_limit: optionalInteger(query.get("limit"), 20),
      },
      dependencies,
    );
    return jsonResponse({ data: payload }, 200, request, allowedOrigins);
  } catch (error) {
    return handleError(error, request, allowedOrigins);
  }
}

if (import.meta.main) Deno.serve((request) => handleRequest(request));
