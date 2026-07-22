import { handleRequest } from "./index.ts";

Deno.test("starts one session with a typed bearer and idempotency key", async () => {
  keys();
  let captured: Record<string, unknown> = {};
  const response = await handleRequest(
    new Request("http://local", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${"S".repeat(43)}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ idempotencyKey: "start-key-0000001" }),
    }),
    {
      supabaseUrl: "http://supabase",
      serviceRoleKey: "server-only",
      fetch: ((_input, init) => {
        captured = JSON.parse(String(init?.body));
        return Promise.resolve(
          Response.json({ sessionId: "internal", sessionStatus: "ACTIVE" }),
        );
      }) as typeof fetch,
    },
  );
  equal(response.status, 200);
  equal(captured.p_idempotency_key, "start-key-0000001");
  if ((await response.text()).includes("internal")) {
    throw new Error("internal id leaked");
  }
});

function keys() {
  Deno.env.set(
    "VERIFIED_ACCESS_PUBLIC_FINGERPRINT_KEY_B64",
    "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
  );
  Deno.env.set(
    "VERIFIED_ACCESS_RATE_LIMIT_KEY_B64",
    "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
  );
}
function equal(a: unknown, b: unknown) {
  if (a !== b) throw new Error(`${a} !== ${b}`);
}
