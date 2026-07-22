import { handleRequest } from "./index.ts";

Deno.test("submits only ciphertext and tenant HMAC through the server RPC", async () => {
  keys();
  const calls: Array<Record<string, unknown>> = [];
  const response = await handleRequest(post(validBody()), {
    supabaseUrl: "http://supabase",
    serviceRoleKey: "server-only",
    fetch: ((_input, init) => {
      const body = JSON.parse(String(init?.body));
      calls.push(body);
      return Promise.resolve(
        Response.json(
          calls.length === 1
            ? { tenantScope: "11111111-1111-4111-8111-111111111111" }
            : {
              sessionId: "internal",
              sessionStatus: "COMPLETED",
              registrationStatus: "SUBMITTED",
            },
        ),
      );
    }) as typeof fetch,
  });
  equal(response.status, 201);
  const submit = JSON.stringify(calls[1]);
  excludes(submit, "Maria Teste");
  excludes(submit, "52998224725");
  includes(submit, "p_full_name_ciphertext");
  includes(submit, "p_cpf_tenant_hmac");
  excludes(await response.text(), "internal");
});

Deno.test("rejects nonaccepted privacy terms before any RPC", async () => {
  keys();
  const body = validBody();
  body.termsAccepted = false;
  equal((await handleRequest(post(body))).status, 400);
});

function validBody(): Record<string, unknown> {
  return {
    idempotencyKey: "submit-key-000001",
    nationality: "BR",
    fullName: "Maria Teste",
    dateOfBirth: "1990-01-01",
    documentType: "CPF",
    documentValue: "52998224725",
    issuerCountry: null,
    phone: null,
    guardianName: null,
    guardianRelationship: null,
    privacyNoticeVersion: "dev-v1",
    termsVersion: "dev-v1",
    privacyAcknowledged: true,
    termsAccepted: true,
  };
}
function post(body: unknown) {
  return new Request("http://local", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${"S".repeat(43)}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
}
function keys() {
  const key = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  Deno.env.set("VERIFIED_ACCESS_PUBLIC_FINGERPRINT_KEY_B64", key);
  Deno.env.set("VERIFIED_ACCESS_RATE_LIMIT_KEY_B64", key);
  Deno.env.set("VERIFIED_ACCESS_TENANT_HMAC_KEY_B64", key);
  Deno.env.set("VERIFIED_ACCESS_LOCAL_ENCRYPTION_KEY_B64", key);
}
function equal(a: unknown, b: unknown) {
  if (a !== b) throw new Error(`${a} !== ${b}`);
}
function includes(a: string, b: string) {
  if (!a.includes(b)) throw new Error(`missing ${b}`);
}
function excludes(a: string, b: string) {
  if (a.includes(b)) throw new Error(`leaked ${b}`);
}
