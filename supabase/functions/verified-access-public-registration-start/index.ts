import {
  callPublicRpc,
  type RpcDependencies,
} from "../_shared/verified-access/public-registration/auth.ts";
import {
  requiredIdempotencyKey,
  START_KEYS,
} from "../_shared/verified-access/public-registration/contracts.ts";
import {
  keyedFingerprint,
  requiredKey,
} from "../_shared/verified-access/public-registration/crypto.ts";
import {
  correlationId,
  handleError,
  jsonResponse,
  preflightResponse,
  strictJsonObject,
} from "../_shared/verified-access/public-registration/http.ts";
import { sessionCredentials } from "../_shared/verified-access/public-registration/session.ts";

export async function handleRequest(
  request: Request,
  dependencies?: RpcDependencies,
) {
  try {
    if (request.method === "OPTIONS") return preflightResponse(request);
    if (request.method !== "POST") {
      return jsonResponse(
        request,
        { error: { code: "METHOD_NOT_ALLOWED" } },
        405,
      );
    }
    const body = await strictJsonObject(request, START_KEYS);
    const idempotencyKey = requiredIdempotencyKey(body.idempotencyKey);
    const rateKey = requiredKey("VERIFIED_ACCESS_RATE_LIMIT_KEY_B64");
    const fingerprintKey = requiredKey(
      "VERIFIED_ACCESS_PUBLIC_FINGERPRINT_KEY_B64",
    );
    const credentials = await sessionCredentials(request, rateKey);
    const payload = await callPublicRpc(
      "verified_access_public_start_registration",
      {
        p_session_token_hash: credentials.sessionHash,
        p_idempotency_key: idempotencyKey,
        p_input_fingerprint: await keyedFingerprint(
          fingerprintKey,
          "start-input",
          `${credentials.sessionHash}\0${idempotencyKey}`,
        ),
        p_rate_fingerprint: credentials.rateFingerprint,
        p_correlation_id: correlationId(request),
      },
      dependencies,
    );
    const { sessionId: _sessionId, ...data } = payload;
    return jsonResponse(request, { data });
  } catch (error) {
    return handleError(error, request);
  }
}

if (import.meta.main) Deno.serve((request) => handleRequest(request));
