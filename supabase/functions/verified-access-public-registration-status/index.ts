import {
  callPublicRpc,
  type RpcDependencies,
} from "../_shared/verified-access/public-registration/auth.ts";
import { requiredKey } from "../_shared/verified-access/public-registration/crypto.ts";
import {
  correlationId,
  handleError,
  jsonResponse,
  preflightResponse,
} from "../_shared/verified-access/public-registration/http.ts";
import { sessionCredentials } from "../_shared/verified-access/public-registration/session.ts";

export async function handleRequest(
  request: Request,
  dependencies?: RpcDependencies,
) {
  try {
    if (request.method === "OPTIONS") return preflightResponse(request);
    if (request.method !== "GET") {
      return jsonResponse(
        request,
        { error: { code: "METHOD_NOT_ALLOWED" } },
        405,
      );
    }
    const credentials = await sessionCredentials(
      request,
      requiredKey("VERIFIED_ACCESS_RATE_LIMIT_KEY_B64"),
    );
    const payload = await callPublicRpc(
      "verified_access_public_registration_status",
      {
        p_session_token_hash: credentials.sessionHash,
        p_rate_fingerprint: credentials.rateFingerprint,
        p_correlation_id: correlationId(request),
      },
      dependencies,
    );
    return jsonResponse(request, { data: payload });
  } catch (error) {
    return handleError(error, request);
  }
}

if (import.meta.main) Deno.serve((request) => handleRequest(request));
