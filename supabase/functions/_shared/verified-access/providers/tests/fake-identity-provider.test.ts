import { VirtualClock } from "../clock.ts";
import {
  createProviderInputFingerprint,
  type IdentityResult,
  type IdentitySessionInput,
  type ProviderContext,
  type ProviderInputFingerprint,
} from "../contracts.ts";
import { FakeIdentityProvider } from "../fake/fake-identity-provider.ts";
import { InMemoryFakeProviderStore } from "../fake/fake-provider-store.ts";
import { IDENTITY_SCENARIOS } from "../fake/scenarios.ts";
import type { ProviderResult } from "../result.ts";

Deno.test("identity fake covers every deterministic scenario without throwing", async () => {
  for (const scenario of IDENTITY_SCENARIOS) {
    const provider = new FakeIdentityProvider({ scenario });
    let thrown = false;
    let session: Awaited<ReturnType<typeof provider.createSession>> | undefined;
    try {
      session = await provider.createSession(
        await identityInput(`key-${scenario}`),
      );
    } catch {
      thrown = true;
    }
    assert(!thrown, `${scenario} threw an expected provider failure`);
    assert(session !== undefined);
    if (scenario === "IDENTITY_TIMEOUT") {
      assertFailureCode(session, "TIMEOUT");
      continue;
    }
    if (scenario === "IDENTITY_PROVIDER_ERROR") {
      assertFailureCode(session, "UNAVAILABLE");
      continue;
    }
    const created = mustSuccess(session);
    const result = await provider.getResult(created.providerSessionId, {
      condominiumId: "condominium-identity",
      requestId: "request-identity",
      participantId: "participant-identity",
      correlationId: `result-${scenario}`,
    });
    const identity = mustSuccess(result);
    assertEquals(identity.metadataSanitized?.scenario, scenario);
    assert(!JSON.stringify(identity).includes("MANUAL_VERIFIED"));
  }
});

Deno.test("liveness evidence alone never verifies identity", async () => {
  for (
    const scenario of [
      "LIVENESS_INCONCLUSIVE",
      "LIVENESS_FAILED_REVIEW",
      "FACE_NO_MATCH_REVIEW",
    ] as const
  ) {
    const provider = new FakeIdentityProvider({ scenario });
    const session = mustSuccess(
      await provider.createSession(await identityInput(`liveness-${scenario}`)),
    );
    const result = mustSuccess(
      await provider.getResult(session.providerSessionId, {
        condominiumId: "condominium-identity",
        requestId: "request-identity",
        participantId: "participant-identity",
        correlationId: `correlation-${scenario}`,
      }),
    );
    assert(result.level !== "IDENTITY_VERIFIED");
  }
});

Deno.test("identity idempotency detects fingerprint conflicts", async () => {
  const provider = new FakeIdentityProvider({ scenario: "IDENTITY_SUCCESS" });
  const first = await identityInput("shared-key");
  const repeated = await provider.createSession(first);
  const same = await provider.createSession({
    ...first,
    context: { ...first.context, correlationId: "correlation-repeated" },
  });
  assertEquals(
    mustSuccess(repeated).providerSessionId,
    mustSuccess(same).providerSessionId,
  );

  const conflict = await provider.createSession({
    ...first,
    context: {
      ...first.context,
      correlationId: "correlation-conflict",
      inputFingerprint: { version: 1, value: "different-fingerprint" },
    },
  });
  assertFailureCode(conflict, "CONFLICT");
});

Deno.test("identity fake isolates condominiums, instances, cleanup, and parallel calls", async () => {
  const sharedStore = new InMemoryFakeProviderStore();
  const firstProvider = new FakeIdentityProvider({
    scenario: "IDENTITY_SUCCESS",
    store: sharedStore,
  });
  const secondProvider = new FakeIdentityProvider({
    scenario: "IDENTITY_SUCCESS",
  });
  const firstInput = await identityInput("isolation-key", "condominium-a");
  const otherTenantInput = {
    ...firstInput,
    context: { ...firstInput.context, condominiumId: "condominium-b" },
  };
  const [tenantA, tenantB] = await Promise.all([
    firstProvider.createSession(firstInput),
    firstProvider.createSession(otherTenantInput),
  ]);
  assert(
    mustSuccess(tenantA).providerSessionId !==
      mustSuccess(tenantB).providerSessionId,
  );
  assertFailureCode(
    await firstProvider.getResult(mustSuccess(tenantA).providerSessionId, {
      condominiumId: "condominium-b",
      requestId: "request-identity",
      participantId: "participant-identity",
      correlationId: "cross-tenant-result",
    }),
    "NOT_FOUND",
  );

  const conflictingFingerprint: ProviderInputFingerprint = {
    version: 1,
    value: "instance-specific-fingerprint",
  };
  assertFailureCode(
    await firstProvider.createSession({
      ...firstInput,
      context: {
        ...firstInput.context,
        inputFingerprint: conflictingFingerprint,
      },
    }),
    "CONFLICT",
  );
  assert(
    (await secondProvider.createSession({
      ...firstInput,
      context: {
        ...firstInput.context,
        inputFingerprint: conflictingFingerprint,
      },
    })).ok,
  );

  sharedStore.clear();
  assert(
    (await firstProvider.createSession({
      ...firstInput,
      context: {
        ...firstInput.context,
        inputFingerprint: conflictingFingerprint,
      },
    })).ok,
  );
});

Deno.test("identity fake uses virtual time once per call and enforces store limits", async () => {
  const clock = new VirtualClock("2026-07-19T00:00:00.000Z");
  const provider = new FakeIdentityProvider({
    scenario: "IDENTITY_SUCCESS",
    clock,
    latencyMs: 750,
    maxRecords: 1,
  });
  const before = clock.now().getTime();
  const first = await provider.createSession(
    await identityInput("limit-first"),
  );
  assert(first.ok);
  assertEquals(clock.now().getTime() - before, 750);

  const second = await provider.createSession(
    await identityInput("limit-second"),
  );
  assertFailureCode(second, "UNAVAILABLE");
  assertEquals(clock.now().getTime() - before, 1_500);
});

Deno.test("identity fake identifiers do not expose input references", async () => {
  const provider = new FakeIdentityProvider({ scenario: "IDENTITY_SUCCESS" });
  const input = await identityInput("pii-safety-key");
  const marker = "SYNTHETIC_SENSITIVE_REFERENCE";
  const result = mustSuccess(
    await provider.createSession({
      ...input,
      sensitiveInputReference: marker,
    }),
  );
  assert(!result.providerSessionId.includes(marker));
});

Deno.test("identity cancellation is idempotent and tenant isolated", async () => {
  const provider = new FakeIdentityProvider({ scenario: "IDENTITY_SUCCESS" });
  const session = mustSuccess(
    await provider.createSession(await identityInput("cancel-session")),
  );
  const inputFingerprint = await createProviderInputFingerprint(
    "cancelSession",
    { providerSessionId: session.providerSessionId },
  );
  const cancellationContext = {
    ...context(
      "cancel-idempotency",
      inputFingerprint,
      "condominium-identity",
    ),
  };
  const first = await provider.cancelSession(
    session.providerSessionId,
    cancellationContext,
  );
  const repeated = await provider.cancelSession(session.providerSessionId, {
    ...cancellationContext,
    correlationId: "cancel-repeat",
  });
  assertEquals(mustSuccess(first).status, "CANCELLED");
  assertEquals(
    mustSuccess(first).occurredAt,
    mustSuccess(repeated).occurredAt,
  );
  assertFailureCode(
    await provider.cancelSession(session.providerSessionId, {
      ...cancellationContext,
      condominiumId: "other-condominium",
    }),
    "NOT_FOUND",
  );
});

async function identityInput(
  idempotencyKey: string,
  condominiumId = "condominium-identity",
): Promise<IdentitySessionInput> {
  const inputFingerprint = await createProviderInputFingerprint(
    "createSession",
    {
      documentType: "CPF",
      requestedChecks: [
        "DOCUMENT_VERIFICATION",
        "LIVENESS",
        "FACE_MATCH_ONE_TO_ONE",
      ],
      sensitiveInputReferenceFingerprint: `opaque-${idempotencyKey}`,
    },
  );
  return {
    context: context(idempotencyKey, inputFingerprint, condominiumId),
    documentType: "CPF",
    requestedChecks: [
      "DOCUMENT_VERIFICATION",
      "LIVENESS",
      "FACE_MATCH_ONE_TO_ONE",
    ],
    sensitiveInputReference: "synthetic-sensitive-reference",
  };
}

function context(
  idempotencyKey: string,
  inputFingerprint: ProviderInputFingerprint,
  condominiumId: string,
): ProviderContext {
  return {
    condominiumId,
    requestId: "request-identity",
    participantId: "participant-identity",
    correlationId: `correlation-${idempotencyKey}`,
    idempotencyKey,
    inputFingerprint,
    requestedAt: "2026-07-19T00:00:00.000Z",
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

const _identityResultTypeGuard: IdentityResult["level"] = "IDENTITY_VERIFIED";
void _identityResultTypeGuard;
