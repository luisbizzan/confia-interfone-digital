import { handleRequest } from "./index.ts";

Deno.test("exchanges an invitation without returning internal ids or hashes", async () => {
  keys();
  let captured: Record<string, unknown> = {};
  const response = await handleRequest(
    post({
      invitationToken: "A".repeat(43),
      idempotencyKey: "exchange-key-0001",
    }),
    {
      supabaseUrl: "http://supabase",
      serviceRoleKey: "server-only",
      createSessionToken: () => "B".repeat(43),
      fetch: ((_input, init) => {
        captured = JSON.parse(String(init?.body));
        return Promise.resolve(
          Response.json({
            sessionId: "internal",
            tenantScope: "tenant",
            sessionStatus: "ACTIVE",
          }),
        );
      }) as typeof fetch,
    },
  );
  equal(response.status, 201);
  if (!/^v1:[0-9a-f]{64}$/.test(String(captured.p_invitation_token_hash))) {
    throw new Error("invitation hash was not versioned");
  }
  const text = await response.text();
  includes(text, `"sessionToken":"${"B".repeat(43)}"`);
  excludes(text, "internal");
  excludes(text, "tenant");
  excludes(text, "server-only");
});

Deno.test("exchange rejects fields outside the public allowlist", async () => {
  keys();
  const response = await handleRequest(
    post({
      invitationToken: "A".repeat(43),
      idempotencyKey: "exchange-key-0001",
      condominiumId: "forbidden",
    }),
  );
  equal(response.status, 400);
});

Deno.test("exchange rejects missing, malformed and excessive invitation bodies", async () => {
  keys();
  equal(
    (await handleRequest(post({ idempotencyKey: "exchange-key-0001" }))).status,
    400,
  );
  equal(
    (await handleRequest(
      post({ invitationToken: "short", idempotencyKey: "exchange-key-0001" }),
    )).status,
    400,
  );
  equal(
    (await handleRequest(
      post({
        invitationToken: "A".repeat(43),
        idempotencyKey: "exchange-key-0001",
        padding: "x".repeat(17_000),
      }),
    )).status,
    413,
  );
});

Deno.test("exchange returns no-store and framing protections", async () => {
  keys();
  const response = await handleRequest(
    post({
      invitationToken: "A".repeat(43),
      idempotencyKey: "exchange-key-0001",
    }),
    {
      supabaseUrl: "http://supabase",
      serviceRoleKey: "server-only",
      createSessionToken: () => "B".repeat(43),
      fetch: (() =>
        Promise.resolve(
          Response.json({ sessionStatus: "ACTIVE" }),
        )) as typeof fetch,
    },
  );
  equal(response.headers.get("cache-control"), "no-store, max-age=0");
  equal(response.headers.get("referrer-policy"), "no-referrer");
  equal(response.headers.get("x-frame-options"), "DENY");
});

function post(body: unknown) {
  return new Request("http://local", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Forwarded-For": "203.0.113.10",
    },
    body: JSON.stringify(body),
  });
}
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
function includes(a: string, b: string) {
  if (!a.includes(b)) throw new Error(`missing ${b}`);
}
function excludes(a: string, b: string) {
  if (a.includes(b)) throw new Error(`leaked ${b}`);
}
