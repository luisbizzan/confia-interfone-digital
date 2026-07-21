import {
  type AuthDependencies,
  callAuthenticatedRpc,
} from "../_shared/verified-access/invitations/auth.ts";
import {
  RESEND_KEYS,
  resendArgs,
} from "../_shared/verified-access/invitations/contracts.ts";
import {
  correlationId,
  handleError,
  jsonResponse,
  preflightResponse,
  strictJsonObject,
} from "../_shared/verified-access/invitations/http.ts";
import {
  dispatchFakeInvitation,
  type DispatchResult,
} from "../_shared/verified-access/invitations/messaging.ts";
import {
  createOpaqueInvitationToken,
  type OpaqueInvitationToken,
} from "../_shared/verified-access/invitations/token.ts";

export type ResendDependencies = AuthDependencies & {
  createToken?: () => Promise<OpaqueInvitationToken>;
  dispatch?: (
    record: Record<string, unknown>,
    raw: string,
    correlationId: string,
  ) => Promise<DispatchResult>;
};
export async function handleRequest(
  request: Request,
  dependencies?: ResendDependencies,
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
    const body = await strictJsonObject(request, RESEND_KEYS);
    const correlation = correlationId(request);
    const token =
      await (dependencies?.createToken ?? createOpaqueInvitationToken)();
    const payload = await callAuthenticatedRpc(
      request,
      "verified_access_resend_resident_invitation",
      resendArgs(body, token.hash, correlation),
      dependencies,
    );
    const record = payload as Record<string, unknown>;
    const delivery = record.dispatchRequired === true
      ? await (dependencies?.dispatch ?? dispatchFakeInvitation)(
        record,
        token.raw,
        correlation,
      )
      : undefined;
    const { dispatchRequired: _a, commandId: _b, condominiumId: _c, ...data } =
      record;
    return jsonResponse(
      { data: { ...data, ...(delivery ? { delivery } : {}) } },
      200,
      request,
      origins,
    );
  } catch (error) {
    return handleError(error, request, origins);
  }
}
if (import.meta.main) Deno.serve((request) => handleRequest(request));
