import { handleRequest, type IssueDependencies } from "./index.ts";

Deno.test("issue uses only the allowlist and never persists or returns the raw token", async () => {
  let rpcBody = "";
  let dispatched = "";
  const response = await handleRequest(
    post({
      participantSlotId: "11111111-1111-4111-8111-111111111111",
      idempotencyKey: "issue-key-000001",
    }),
    deps((body) => rpcBody = body, (raw) => dispatched = raw),
  );
  equal(response.status, 201);
  equal(JSON.parse(rpcBody).p_token_hash, `v1:${"a".repeat(64)}`);
  equal(dispatched, "raw-secret");
  const text = await response.text();
  if (text.includes("raw-secret") || text.includes(`v1:${"a".repeat(64)}`)) {
    throw new Error("token leaked");
  }
});

Deno.test("issue rejects unknown fields", async () =>
  equal(
    (await handleRequest(
      post({
        participantSlotId: "11111111-1111-4111-8111-111111111111",
        idempotencyKey: "issue-key-000001",
        condominiumId: "forbidden",
      }),
      deps(),
    )).status,
    400,
  ));

function post(body: unknown) {
  return new Request("http://local", {
    method: "POST",
    headers: {
      Authorization: "Bearer user",
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
}
function deps(
  capture: (body: string) => void = () => {},
  dispatchCapture: (raw: string) => void = () => {},
): IssueDependencies {
  let calls = 0;
  return {
    supabaseUrl: "http://supabase",
    anonKey: "anon",
    createToken: () =>
      Promise.resolve({
        raw: "raw-secret",
        hash: `v1:${"a".repeat(64)}`,
      }),
    dispatch: (_record, raw) => {
      dispatchCapture(raw);
      return Promise.resolve({
        providerCode: "FAKE_MESSAGING",
        status: "DELIVERED",
        providerMessageId: "fake-id",
      });
    },
    fetch: ((_input, init) => {
      calls++;
      if (calls === 1) {
        return Promise.resolve(new Response("{}", { status: 200 }));
      }
      capture(String(init?.body));
      return Promise.resolve(Response.json({
        invitationId: "inv",
        requestId: "req",
        participantSlotId: "slot",
        tokenVersion: 1,
        dispatchRequired: true,
        commandId: "cmd",
        condominiumId: "cond",
      }));
    }) as typeof fetch,
  };
}
function equal(actual: unknown, expected: unknown) {
  if (actual !== expected) throw new Error(`${actual} !== ${expected}`);
}
