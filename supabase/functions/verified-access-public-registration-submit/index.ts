import {
  callPublicRpc,
  type RpcDependencies,
} from "../_shared/verified-access/public-registration/auth.ts";
import {
  SUBMIT_KEYS,
  validateRegistrationInput,
} from "../_shared/verified-access/public-registration/contracts.ts";
import {
  encryptValue,
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

    const input = validateRegistrationInput(
      await strictJsonObject(request, SUBMIT_KEYS),
    );
    const rateKey = requiredKey("VERIFIED_ACCESS_RATE_LIMIT_KEY_B64");
    const fingerprintKey = requiredKey(
      "VERIFIED_ACCESS_PUBLIC_FINGERPRINT_KEY_B64",
    );
    const hmacKey = requiredKey("VERIFIED_ACCESS_TENANT_HMAC_KEY_B64");
    const encryptionKey = requiredKey(
      "VERIFIED_ACCESS_LOCAL_ENCRYPTION_KEY_B64",
    );
    const credentials = await sessionCredentials(request, rateKey);
    const correlation = correlationId(request);
    const context = await callPublicRpc(
      "verified_access_public_get_registration",
      {
        p_session_token_hash: credentials.sessionHash,
        p_rate_fingerprint: credentials.rateFingerprint,
        p_correlation_id: correlation,
      },
      dependencies,
    );
    if (typeof context.tenantScope !== "string") {
      throw new Error("missing tenant scope");
    }
    const tenantScope = context.tenantScope;
    const protect = (field: string, value: string | null) =>
      value === null
        ? Promise.resolve(null)
        : encryptValue(encryptionKey, tenantScope, field, value);
    const documentHmac = input.documentValue === null
      ? null
      : await keyedFingerprint(
        hmacKey,
        `${tenantScope}:${input.documentType}`,
        input.documentValue,
      );
    const phoneHmac = input.phone === null
      ? null
      : await keyedFingerprint(hmacKey, `${tenantScope}:PHONE`, input.phone);
    const canonical = JSON.stringify(input);
    const payload = await callPublicRpc(
      "verified_access_public_submit_registration",
      {
        p_session_token_hash: credentials.sessionHash,
        p_idempotency_key: input.idempotencyKey,
        p_input_fingerprint: await keyedFingerprint(
          fingerprintKey,
          "submit-input",
          canonical,
        ),
        p_rate_fingerprint: credentials.rateFingerprint,
        p_document_rate_fingerprint: await keyedFingerprint(
          rateKey,
          "submit-document",
          `${tenantScope}\0${documentHmac ?? credentials.sessionHash}`,
        ),
        p_full_name_ciphertext: await protect("full_name", input.fullName),
        p_birth_date_ciphertext: await protect("birth_date", input.dateOfBirth),
        p_document_type: input.documentType,
        p_cpf_ciphertext: input.documentType === "CPF"
          ? await protect("cpf", input.documentValue)
          : null,
        p_cpf_tenant_hmac: input.documentType === "CPF" ? documentHmac : null,
        p_document_number_ciphertext:
          input.documentType === "RNM" || input.documentType === "PASSPORT"
            ? await protect("document_number", input.documentValue)
            : null,
        p_document_number_tenant_hmac:
          input.documentType === "RNM" || input.documentType === "PASSPORT"
            ? documentHmac
            : null,
        p_document_issuer_country_ciphertext: await protect(
          "document_issuer_country",
          input.issuerCountry,
        ),
        p_phone_ciphertext: await protect("phone", input.phone),
        p_phone_tenant_hmac: phoneHmac,
        p_is_minor: input.isMinor,
        p_guardian_name_ciphertext: await protect(
          "guardian_name",
          input.guardianName,
        ),
        p_guardian_relationship_ciphertext: await protect(
          "guardian_relationship",
          input.guardianRelationship,
        ),
        p_privacy_notice_version: input.privacyNoticeVersion,
        p_terms_version: input.termsVersion,
        p_encryption_key_version: 1,
        p_hmac_key_version: 1,
        p_correlation_id: correlation,
      },
      dependencies,
    );
    const { sessionId: _sessionId, participantId: _participantId, ...data } =
      payload;
    return jsonResponse(request, { data }, 201);
  } catch (error) {
    return handleError(error, request);
  }
}

if (import.meta.main) Deno.serve((request) => handleRequest(request));
