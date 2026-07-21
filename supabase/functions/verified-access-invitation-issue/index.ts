import {
  type AuthDependencies,
  callAuthenticatedRpc,
} from "../_shared/verified-access/invitations/auth.ts";
import {
  ISSUE_KEYS,
  issueArgs,
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

export type IssueDependencies = AuthDependencies & {
  createToken?: () => Promise<OpaqueInvitationToken>;
  dispatch?: (
    record: Record<string, unknown>,
    raw: string,
    correlationId: string,
  ) => Promise<DispatchResult>;
};

export async function handleRequest(
  request: Request,
  dependencies?: IssueDependencies,
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
    const body = await strictJsonObject(request, ISSUE_KEYS);
    const correlation = correlationId(request);
    const token =
      await (dependencies?.createToken ?? createOpaqueInvitationToken)();
    const payload = await callAuthenticatedRpc(
      request,
      "verified_access_issue_resident_invitation",
      issueArgs(body, token.hash, correlation),
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
    return jsonResponse(
      { data: sanitize(record, delivery) },
      201,
      request,
      origins,
    );
  } catch (error) {
    return handleError(error, request, origins);
  }
}

function sanitize(record: Record<string, unknown>, delivery?: DispatchResult) {
  const {
    dispatchRequired: _dispatchRequired,
    commandId: _commandId,
    condominiumId: _condominiumId,
    ...data
  } = record;
  return { ...data, ...(delivery ? { delivery } : {}) };
}
if (import.meta.main) Deno.serve((request) => handleRequest(request));
