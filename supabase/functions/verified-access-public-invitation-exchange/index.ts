import {
  callPublicRpc,
  type RpcDependencies,
} from "../_shared/verified-access/public-registration/auth.ts";
import {
  EXCHANGE_KEYS,
  requiredIdempotencyKey,
  requiredInvitationToken,
} from "../_shared/verified-access/public-registration/contracts.ts";
import {
  keyedFingerprint,
  randomOpaqueToken,
  requiredKey,
  sha256Fingerprint,
} from "../_shared/verified-access/public-registration/crypto.ts";
import {
  correlationId,
  handleError,
  jsonResponse,
  preflightResponse,
  strictJsonObject,
} from "../_shared/verified-access/public-registration/http.ts";
import { clientAddress } from "../_shared/verified-access/public-registration/session.ts";

export type ExchangeDependencies = Partial<RpcDependencies> & {
  createSessionToken?: () => string;
};

export async function handleRequest(
  request: Request,
  dependencies?: ExchangeDependencies,
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

    const body = await strictJsonObject(request, EXCHANGE_KEYS);
    const invitationToken = requiredInvitationToken(body.invitationToken);
    const idempotencyKey = requiredIdempotencyKey(body.idempotencyKey);
    const sessionToken =
      (dependencies?.createSessionToken ?? randomOpaqueToken)();
    const fingerprintKey = requiredKey(
      "VERIFIED_ACCESS_PUBLIC_FINGERPRINT_KEY_B64",
    );
    const rateKey = requiredKey("VERIFIED_ACCESS_RATE_LIMIT_KEY_B64");
    const invitationFingerprint = await keyedFingerprint(
      rateKey,
      "exchange-invitation",
      invitationToken,
    );
    const payload = await callPublicRpc(
      "verified_access_public_exchange_invitation",
      {
        p_invitation_token_hash: await sha256Fingerprint(invitationToken),
        p_session_token_hash: await sha256Fingerprint(sessionToken),
        p_idempotency_key: idempotencyKey,
        p_input_fingerprint: await keyedFingerprint(
          fingerprintKey,
          "exchange-input",
          `${invitationFingerprint}\0${sessionToken}`,
        ),
        p_ip_fingerprint: await keyedFingerprint(
          rateKey,
          "exchange-ip",
          clientAddress(request),
        ),
        p_invitation_fingerprint: invitationFingerprint,
        p_correlation_id: correlationId(request),
      },
      dependencies as RpcDependencies | undefined,
    );

    const { sessionId: _sessionId, tenantScope: _tenantScope, ...context } =
      payload;
    return jsonResponse(request, { data: { sessionToken, context } }, 201);
  } catch (error) {
    return handleError(error, request);
  }
}

if (import.meta.main) Deno.serve((request) => handleRequest(request));
