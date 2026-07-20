import {
  type BackgroundCheckInput,
  createProviderInputFingerprint,
  type ProviderContext,
} from "../contracts.ts";
import { FakeBackgroundCheckProvider } from "../fake/fake-background-check-provider.ts";
import { BACKGROUND_SCENARIOS } from "../fake/scenarios.ts";
import type { ProviderResult } from "../result.ts";

Deno.test("background fake covers all scenarios without expected exceptions", async () => {
  for (const scenario of BACKGROUND_SCENARIOS) {
    const provider = new FakeBackgroundCheckProvider({ scenario });
    let thrown = false;
    let request: Awaited<ReturnType<typeof provider.requestCheck>> | undefined;
    try {
      request = await provider.requestCheck(
        await backgroundInput(`key-${scenario}`),
      );
    } catch {
      thrown = true;
    }
    assert(!thrown, `${scenario} threw an expected provider failure`);
    assert(request !== undefined);
    if (scenario === "BACKGROUND_TIMEOUT") {
      assertFailureCode(request, "TIMEOUT");
      continue;
    }
    if (scenario === "BACKGROUND_PROVIDER_ERROR") {
      assertFailureCode(request, "UNAVAILABLE");
      continue;
    }
    const created = mustSuccess(request);
    const result = mustSuccess(
      await provider.getResult(created.providerRequestId, {
        condominiumId: "condominium-background",
        requestId: "request-background",
        participantId: "participant-background",
        correlationId: `result-${scenario}`,
      }),
    );
    assertEquals(result.metadataSanitized?.scenario, scenario);
  }
});

Deno.test("adverse background information requires review and never denies", async () => {
  const provider = new FakeBackgroundCheckProvider({
    scenario: "BACKGROUND_ADVERSE_REVIEW",
  });
  const request = mustSuccess(
    await provider.requestCheck(await backgroundInput("adverse-review")),
  );
  const result = mustSuccess(
    await provider.getResult(request.providerRequestId, {
      condominiumId: "condominium-background",
      requestId: "request-background",
      participantId: "participant-background",
      correlationId: "correlation-adverse-result",
    }),
  );
  assertEquals(result.status, "ADVERSE_INFORMATION_REVIEW");
  const serialized = JSON.stringify(result);
  assert(!serialized.includes("DENIED"));
  assert(!serialized.includes("AUTO_DENY_NETWORK"));
});

Deno.test("background idempotency returns conflict for a changed fingerprint", async () => {
  const provider = new FakeBackgroundCheckProvider({
    scenario: "BACKGROUND_SUCCESS",
  });
  const input = await backgroundInput("background-idempotency");
  const first = await provider.requestCheck(input);
  const repeated = await provider.requestCheck({
    ...input,
    context: { ...input.context, correlationId: "correlation-repeat" },
  });
  assertEquals(
    mustSuccess(first).providerRequestId,
    mustSuccess(repeated).providerRequestId,
  );
  const conflict = await provider.requestCheck({
    ...input,
    context: {
      ...input.context,
      inputFingerprint: { version: 1, value: "changed-background-fingerprint" },
    },
  });
  assertFailureCode(conflict, "CONFLICT");
});

Deno.test("background result lookup is tenant isolated", async () => {
  const provider = new FakeBackgroundCheckProvider({
    scenario: "BACKGROUND_SUCCESS",
  });
  const request = mustSuccess(
    await provider.requestCheck(await backgroundInput("tenant-isolation")),
  );
  assertFailureCode(
    await provider.getResult(request.providerRequestId, {
      condominiumId: "other-condominium",
      requestId: "request-background",
      participantId: "participant-background",
      correlationId: "cross-tenant-result",
    }),
    "NOT_FOUND",
  );
});

async function backgroundInput(
  idempotencyKey: string,
): Promise<BackgroundCheckInput> {
  const inputFingerprint = await createProviderInputFingerprint(
    "requestCheck",
    {
      verifiedIdentityReferenceFingerprint: "opaque-verified-identity",
      scopeCodes: ["SYNTHETIC_SCOPE"],
      approvalReference: "synthetic-approval-reference",
      cutoffAt: "2026-07-19T00:00:00.000Z",
    },
  );
  const context: ProviderContext = {
    condominiumId: "condominium-background",
    requestId: "request-background",
    participantId: "participant-background",
    correlationId: `correlation-${idempotencyKey}`,
    idempotencyKey,
    inputFingerprint,
    requestedAt: "2026-07-19T00:00:00.000Z",
  };
  return {
    context,
    verifiedIdentityReference: "synthetic-verified-identity-reference",
    scopeCodes: ["SYNTHETIC_SCOPE"],
    approvalReference: "synthetic-approval-reference",
    cutoffAt: "2026-07-19T00:00:00.000Z",
  };
}

function mustSuccess<T>(result: ProviderResult<T>): T {
  if (!result.ok) {
    throw new Error(`Expected success, received ${result.error.code}`);
  }
  return result.value;
}

function assertFailureCode<T>(result: ProviderResult<T>, code: string): void {
  assert(!result.ok, `Expected ${code}, received success`);
  assertEquals(result.error.code, code);
}

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
