import { handleRequest } from "./index.ts";

Deno.test("gets sanitized registration context with an opaque bearer", async () => {
  Deno.env.set(
    "VERIFIED_ACCESS_RATE_LIMIT_KEY_B64",
    "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
  );
  const response = await handleRequest(
    new Request("http://local", {
      headers: { Authorization: `Bearer ${"S".repeat(43)}` },
    }),
    deps({
      sessionId: "internal",
      tenantScope: "tenant",
      condominiumName: "Condominio",
    }),
  );
  equal(response.status, 200);
  const text = await response.text();
  if (text.includes("internal") || text.includes("tenant")) {
    throw new Error("internal scope leaked");
  }
});

Deno.test("maps missing, unavailable and rate-limited sessions to generic responses", async () => {
  Deno.env.set(
    "VERIFIED_ACCESS_RATE_LIMIT_KEY_B64",
    "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
  );
  equal((await handleRequest(new Request("http://local"))).status, 404);
  equal(
    (await handleRequest(
      bearer(),
      deps({ resultCode: "PUBLIC_ACCESS_UNAVAILABLE" }),
    )).status,
    404,
  );
  const limited = await handleRequest(
    bearer(),
    deps({ rateLimited: true, retryAfterSeconds: 300 }),
  );
  equal(limited.status, 429);
  equal(limited.headers.get("retry-after"), "300");
});

function deps(payload: unknown) {
  return {
    supabaseUrl: "http://supabase",
    serviceRoleKey: "server-only",
    fetch: (() => Promise.resolve(Response.json(payload))) as typeof fetch,
  };
}
function bearer() {
  return new Request("http://local", {
    headers: { Authorization: `Bearer ${"S".repeat(43)}` },
  });
}
function equal(a: unknown, b: unknown) {
  if (a !== b) throw new Error(`${a} !== ${b}`);
}
