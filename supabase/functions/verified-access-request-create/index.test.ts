import { handleRequest } from "./index.ts";
import type { AuthDependencies } from "../_shared/verified-access/resident-requests/auth.ts";

const valid = {
  unitId: "22222222-2222-4222-8222-222222222222",
  requestType: "VISITOR",
  accessStartsAt: "2030-01-01T12:00:00-03:00",
  accessEndsAt: "2030-01-01T13:00:00-03:00",
  participantSlots: 2,
  clientRequestId: "resident-request-0001",
};

Deno.test("create rejects unknown fields", async () => {
  const response = await handleRequest(
    post({ ...valid, condominiumId: "forbidden" }),
    deps(),
  );
  equal(response.status, 400);
});

Deno.test("create sends normalized allowlist and correlation ID", async () => {
  let rpcBody = "";
  const response = await handleRequest(
    post(valid),
    deps((body) => rpcBody = body),
  );
  equal(response.status, 201);
  const parsed = JSON.parse(rpcBody);
  equal(parsed.p_participant_slots, 2);
  if (typeof parsed.p_correlation_id !== "string") {
    throw new Error("missing correlation ID");
  }
  if ("p_condominium_id" in parsed || "p_actor_user_id" in parsed) {
    throw new Error("server fields leaked");
  }
});

Deno.test("create rejects payloads larger than 16 KiB", async () => {
  const response = await handleRequest(
    post({ ...valid, purpose: "x".repeat(16 * 1024) }),
    deps(),
  );
  equal(response.status, 413);
});

Deno.test("create rejects malformed JSON", async () => {
  const response = await handleRequest(
    new Request("http://local", {
      method: "POST",
      headers: {
        Authorization: "Bearer user-token",
        "Content-Type": "application/json",
      },
      body: "{",
    }),
    deps(),
  );
  equal(response.status, 400);
});

Deno.test("create rejects invalid correlation IDs", async () => {
  const request = post(valid);
  request.headers.set("x-correlation-id", "bad value");
  const response = await handleRequest(request, deps());
  equal(response.status, 400);
});

function post(body: unknown) {
  return new Request("http://local", {
    method: "POST",
    headers: {
      Authorization: "Bearer user-token",
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
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
      return new Response(
        '{"requestId":"55555555-5555-4555-8555-555555555555"}',
        { status: 200 },
      );
    }) as typeof fetch,
  };
}
function equal(actual: unknown, expected: unknown) {
  if (actual !== expected) throw new Error(`${actual} !== ${expected}`);
}
