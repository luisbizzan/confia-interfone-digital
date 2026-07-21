import {
  type AuthDependencies,
  callAuthenticatedRpc,
} from "../_shared/verified-access/resident-requests/auth.ts";
import {
  CREATE_KEYS,
  createArgs,
} from "../_shared/verified-access/resident-requests/contracts.ts";
import {
  correlationId,
  handleError,
  jsonResponse,
  preflightResponse,
  strictJsonObject,
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
    if (request.method !== "POST") {
      return jsonResponse(
        { error: { code: "METHOD_NOT_ALLOWED" } },
        405,
        request,
        allowedOrigins,
      );
    }
    const body = await strictJsonObject(request, CREATE_KEYS);
    const payload = await callAuthenticatedRpc(
      request,
      "verified_access_create_resident_request",
      createArgs(body, correlationId(request)),
      dependencies,
    );
    return jsonResponse({ data: payload }, 201, request, allowedOrigins);
  } catch (error) {
    return handleError(error, request, allowedOrigins);
  }
}

if (import.meta.main) Deno.serve((request) => handleRequest(request));
