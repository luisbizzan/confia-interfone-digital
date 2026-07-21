import { handleRequest } from "./index.ts";
import type { AuthDependencies } from "../_shared/verified-access/resident-requests/auth.ts";

Deno.test("service types requires bearer token", async () => {
  const response = await handleRequest(
    new Request("http://local?unitId=22222222-2222-4222-8222-222222222222"),
    deps(),
  );
  equal(response.status, 401);
});

Deno.test("service types preserves user JWT for RPC", async () => {
  const seen: string[] = [];
  const response = await handleRequest(
    new Request("http://local?unitId=22222222-2222-4222-8222-222222222222", {
      headers: { Authorization: "Bearer user-token" },
    }),
    deps(seen),
  );
  equal(response.status, 200);
  equal(seen.join(","), "Bearer user-token,Bearer user-token");
});

function deps(seen: string[] = []): AuthDependencies {
  return {
    supabaseUrl: "http://supabase",
    anonKey: "anon-test",
    fetch: (async (_input, init) => {
      await Promise.resolve();
      seen.push(new Headers(init?.headers).get("Authorization") ?? "");
      return seen.length === 1
        ? new Response('{"id":"user"}', { status: 200 })
        : new Response("[]", { status: 200 });
    }) as typeof fetch,
  };
}
function equal(actual: unknown, expected: unknown) {
  if (actual !== expected) throw new Error(`${actual} !== ${expected}`);
}
