import { handleRequest } from "./index.ts";
import type { AuthDependencies } from "../_shared/verified-access/resident-requests/auth.ts";

Deno.test("list rejects unknown query fields", async () => {
  const response = await handleRequest(request("?search=free-text"), deps());
  equal(response.status, 400);
});

Deno.test("list passes bounded pagination to RPC", async () => {
  let body = "";
  const response = await handleRequest(
    request("?limit=50&requestType=VISITOR"),
    deps((value) => body = value),
  );
  equal(response.status, 200);
  const parsed = JSON.parse(body);
  equal(parsed.p_limit, 50);
  equal(parsed.p_request_type, "VISITOR");
});

function request(query: string) {
  return new Request(`http://local${query}`, {
    headers: { Authorization: "Bearer user-token" },
  });
}
function deps(capture: (body: string) => void = () => {}): AuthDependencies {
  let calls = 0;
  return {
    supabaseUrl: "http://supabase",
    anonKey: "anon-test",
    fetch: (async (_input, init) => {
      await Promise.resolve();
      calls++;
      if (calls === 1) return new Response('{"id":"user"}', { status: 200 });
      capture(String(init?.body ?? ""));
      return new Response("[]", { status: 200 });
    }) as typeof fetch,
  };
}
function equal(actual: unknown, expected: unknown) {
  if (actual !== expected) throw new Error(`${actual} !== ${expected}`);
}
