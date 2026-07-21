import { handleRequest } from "./index.ts";
Deno.test("revoke rejects unsupported reason codes", async () => {
  const response = await handleRequest(
    new Request("http://local", {
      method: "POST",
      headers: {
        Authorization: "Bearer user",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        invitationId: "11111111-1111-4111-8111-111111111111",
        idempotencyKey: "revoke-key-0001",
        reasonCode: "OTHER",
      }),
    }),
  );
  if (response.status !== 400) throw new Error(`status ${response.status}`);
});
