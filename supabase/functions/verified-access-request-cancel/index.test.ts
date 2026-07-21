import { handleRequest } from "./index.ts";
import type { AuthDependencies } from "../_shared/verified-access/resident-requests/auth.ts";

Deno.test("cancel rejects unsupported reason", async () => {
  const response = await handleRequest(post("OTHER_REASON"), deps());
  equal(response.status, 400);
});

Deno.test("cancel forwards only idempotent contract fields", async () => {
  let body = "";
  const response = await handleRequest(
    post("RESIDENT_CANCELLED"),
    deps((value) => body = value),
  );
  equal(response.status, 200);
  const parsed = JSON.parse(body);
  equal(parsed.p_reason_code, "RESIDENT_CANCELLED");
  if ("p_condominium_id" in parsed || "p_actor_user_id" in parsed) {
    throw new Error("server fields leaked");
  }
});

function post(reasonCode: string) {
  return new Request("http://local", {
    method: "POST",
    headers: {
      Authorization: "Bearer user-token",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      requestId: "55555555-5555-4555-8555-555555555555",
      idempotencyKey: "resident-cancel-0001",
      reasonCode,
    }),
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
      return new Response('{"requestStatus":"CANCELLED"}', { status: 200 });
    }) as typeof fetch,
  };
}
function equal(actual: unknown, expected: unknown) {
  if (actual !== expected) throw new Error(`${actual} !== ${expected}`);
}
