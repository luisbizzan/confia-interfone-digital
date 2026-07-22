import { handleRequest } from "./index.ts";

Deno.test("returns only the final public registration status", async () => {
  Deno.env.set(
    "VERIFIED_ACCESS_RATE_LIMIT_KEY_B64",
    "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
  );
  const response = await handleRequest(
    new Request("http://local", {
      headers: { Authorization: `Bearer ${"S".repeat(43)}` },
    }),
    {
      supabaseUrl: "http://supabase",
      serviceRoleKey: "server-only",
      fetch: (() =>
        Promise.resolve(
          Response.json({
            sessionStatus: "COMPLETED",
            registrationStatus: "SUBMITTED",
          }),
        )) as typeof fetch,
    },
  );
  equal(response.status, 200);
  equal((await response.json()).data.registrationStatus, "SUBMITTED");
});

function equal(a: unknown, b: unknown) {
  if (a !== b) throw new Error(`${a} !== ${b}`);
}
