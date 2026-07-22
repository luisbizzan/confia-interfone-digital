import { handleRequest } from "./index.ts";
Deno.test("status list rejects unknown query fields before authentication", async () => {
  const response = await handleRequest(
    new Request(
      "http://local?requestId=11111111-1111-4111-8111-111111111111&condominiumId=forbidden",
      { headers: { Authorization: "Bearer user" } },
    ),
  );
  if (response.status !== 400) throw new Error(`status ${response.status}`);
});
