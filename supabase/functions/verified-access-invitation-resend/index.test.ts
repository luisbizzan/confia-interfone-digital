import { handleRequest, type ResendDependencies } from "./index.ts";
Deno.test("resend does not dispatch an idempotent replay", async () => {
  let dispatched = false;
  let calls = 0;
  const dependencies: ResendDependencies = {
    supabaseUrl: "http://supabase",
    anonKey: "anon",
    createToken: () =>
      Promise.resolve({ raw: "raw", hash: `v1:${"b".repeat(64)}` }),
    dispatch: () => {
      dispatched = true;
      return Promise.reject(new Error("unexpected"));
    },
    fetch: (() => {
      calls++;
      return Promise.resolve(
        calls === 1
          ? new Response("{}", { status: 200 })
          : Response.json({ invitationId: "inv", dispatchRequired: false }),
      );
    }) as typeof fetch,
  };
  const response = await handleRequest(
    new Request("http://local", {
      method: "POST",
      headers: {
        Authorization: "Bearer user",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        invitationId: "11111111-1111-4111-8111-111111111111",
        idempotencyKey: "resend-key-00001",
      }),
    }),
    dependencies,
  );
  if (response.status !== 200 || dispatched) {
    throw new Error("replay dispatched");
  }
});
