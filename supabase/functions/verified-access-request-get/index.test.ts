import { handleRequest } from "./index.ts";
import type { AuthDependencies } from "../_shared/verified-access/resident-requests/auth.ts";

Deno.test("get maps hidden cross-tenant result to REQUEST_NOT_FOUND", async () => {
  const response = await handleRequest(
    new Request("http://local?requestId=55555555-5555-4555-8555-555555555555", {
      headers: { Authorization: "Bearer user-token" },
    }),
    deps(),
  );
  equal(response.status, 404);
  equal((await response.json()).error.code, "REQUEST_NOT_FOUND");
});

function deps(): AuthDependencies {
  let calls = 0;
  return {
    supabaseUrl: "http://supabase",
    anonKey: "anon-test",
    fetch: (async () => {
      await Promise.resolve();
      calls++;
      return calls === 1
        ? new Response('{"id":"user"}', { status: 200 })
        : new Response('{"message":"REQUEST_NOT_FOUND"}', { status: 400 });
    }) as typeof fetch,
  };
}
function equal(actual: unknown, expected: unknown) {
  if (actual !== expected) throw new Error(`${actual} !== ${expected}`);
}
