import {
  createProviderInputFingerprint,
  type ProviderContext,
} from "../contracts.ts";
import type { BackgroundCheckProvider } from "../background-check-provider.ts";
import { FakeBackgroundCheckProvider } from "../fake/fake-background-check-provider.ts";
import { FakeIdentityProvider } from "../fake/fake-identity-provider.ts";
import { FakeMessagingProvider } from "../fake/fake-messaging-provider.ts";
import type { IdentityProvider } from "../identity-provider.ts";
import type { MessagingProvider } from "../messaging-provider.ts";

Deno.test("the three fake providers satisfy their ports", () => {
  const identity: IdentityProvider = new FakeIdentityProvider({
    scenario: "IDENTITY_SUCCESS",
  });
  const background: BackgroundCheckProvider = new FakeBackgroundCheckProvider({
    scenario: "BACKGROUND_SUCCESS",
  });
  const messaging: MessagingProvider = new FakeMessagingProvider({
    scenario: "MESSAGE_SUCCESS",
  });

  assert(identity.capabilities().faceMatchOneToOne);
  assert(background.capabilities().polling);
  assertEquals(typeof messaging.sendInvitation, "function");
});

Deno.test("fingerprints are canonical, stable, and exclude correlation context", async () => {
  const left = await createProviderInputFingerprint("createSession", {
    requestedChecks: ["LIVENESS", "DOCUMENT_VERIFICATION"],
    documentType: "CPF",
    sensitiveInputReferenceFingerprint: "opaque-input-fingerprint",
    issuerCountry: "BR",
  });
  const right = await createProviderInputFingerprint("createSession", {
    issuerCountry: "BR",
    sensitiveInputReferenceFingerprint: "opaque-input-fingerprint",
    documentType: "CPF",
    requestedChecks: ["DOCUMENT_VERIFICATION", "LIVENESS"],
  });

  assertEquals(left.value, right.value);
  assertEquals(left.version, 1);

  const firstContext: ProviderContext = {
    condominiumId: "condominium-contract",
    requestId: "request-contract",
    participantId: "participant-contract",
    correlationId: "correlation-first",
    idempotencyKey: "idempotency-contract",
    inputFingerprint: left,
    requestedAt: "2026-07-19T00:00:00.000Z",
  };
  const secondContext: ProviderContext = {
    ...firstContext,
    correlationId: "correlation-second",
    requestedAt: "2026-07-20T00:00:00.000Z",
  };
  assertEquals(
    firstContext.inputFingerprint.value,
    secondContext.inputFingerprint.value,
  );
});

Deno.test("fingerprint timestamps normalize to UTC", async () => {
  const utc = await createProviderInputFingerprint("requestCheck", {
    verifiedIdentityReferenceFingerprint: "opaque-identity-fingerprint",
    scopeCodes: ["SCOPE_B", "SCOPE_A"],
    approvalReference: "approval-reference",
    cutoffAt: "2026-07-19T12:00:00.000Z",
  });
  const offset = await createProviderInputFingerprint("requestCheck", {
    approvalReference: "approval-reference",
    cutoffAt: "2026-07-19T09:00:00-03:00",
    scopeCodes: ["SCOPE_A", "SCOPE_B"],
    verifiedIdentityReferenceFingerprint: "opaque-identity-fingerprint",
  });
  assertEquals(utc.value, offset.value);
});

Deno.test("fingerprint allowlists reject unknown fields", async () => {
  let thrown = false;
  try {
    await createProviderInputFingerprint("cancelSession", {
      providerSessionId: "synthetic-session",
      unexpected: "not-allowed",
    } as never);
  } catch (error) {
    thrown = error instanceof TypeError &&
      error.message === "Unknown fingerprint field: unexpected";
  }
  assert(thrown, "Expected an unknown fingerprint field to be rejected");
});

function assert(
  condition: unknown,
  message = "Assertion failed",
): asserts condition {
  if (!condition) throw new Error(message);
}

function assertEquals<T>(actual: T, expected: T): void {
  if (!Object.is(actual, expected)) {
    throw new Error(`Expected ${String(expected)}, received ${String(actual)}`);
  }
}
