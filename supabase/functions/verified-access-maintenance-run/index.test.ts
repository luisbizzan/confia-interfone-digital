import {
  createRateLimiter,
  handleRequest,
  type MaintenanceDependencies,
} from "./index.ts";

const secret = "maintenance-secret-at-least-32-characters";

Deno.test("calls only the mapped RPC with typed maintenance parameters", async () => {
  let rpcPath = "";
  let rpcBody: Record<string, unknown> = {};
  const response = await handleRequest(
    request({
      job: "expire_invitations",
      batchSize: 25,
      dryRun: true,
    }),
    dependencies((input, init) => {
      rpcPath = String(input);
      rpcBody = JSON.parse(String(init?.body));
      return Promise.resolve(
        Response.json(result("verified_access_expire_invitations", true)),
      );
    }),
  );

  equal(response.status, 200);
  includes(rpcPath, "/rpc/verified_access_expire_invitations");
  equal(rpcBody.p_batch_size, 25);
  equal(rpcBody.p_dry_run, true);
  equal(typeof rpcBody.p_correlation_id, "string");
});

Deno.test("rejects unknown keys and jobs before calling the RPC", async () => {
  let called = false;
  const response = await handleRequest(
    request({
      job: "unknown",
      batchSize: 25,
      dryRun: true,
      extra: "forbidden",
    }),
    dependencies(() => {
      called = true;
      return Promise.resolve(Response.json({}));
    }),
  );
  equal(response.status, 400);
  equal(called, false);
});

Deno.test("rejects missing or incorrect internal secrets", async () => {
  const missing = request(
    { job: "process_outbox", batchSize: 1, dryRun: true },
    "",
  );
  equal((await handleRequest(missing, dependencies())).status, 401);

  const incorrect = request(
    { job: "process_outbox", batchSize: 1, dryRun: true },
    "incorrect-secret-at-least-32-characters",
  );
  equal((await handleRequest(incorrect, dependencies())).status, 401);
});

Deno.test("enforces the internal per-isolate request limit", async () => {
  const limiter = createRateLimiter(1, 60_000);
  const deps = dependencies(undefined, limiter);
  equal(
    (await handleRequest(
      request({ job: "process_outbox", batchSize: 1, dryRun: true }),
      deps,
    )).status,
    200,
  );
  equal(
    (await handleRequest(
      request({ job: "process_outbox", batchSize: 1, dryRun: true }),
      deps,
    )).status,
    429,
  );
});

Deno.test("does not return upstream error bodies or credentials", async () => {
  const response = await handleRequest(
    request({ job: "process_outbox", batchSize: 1, dryRun: false }),
    dependencies(() =>
      Promise.resolve(
        new Response(
          JSON.stringify({
            secret,
            key: "service-role-value",
            detail: "database internals",
          }),
          { status: 500 },
        ),
      )
    ),
  );
  equal(response.status, 502);
  const body = await response.text();
  excludes(body, secret);
  excludes(body, "service-role-value");
  excludes(body, "database internals");
});

function request(body: unknown, suppliedSecret = secret): Request {
  return new Request(
    "http://local/functions/v1/verified-access-maintenance-run",
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-maintenance-secret": suppliedSecret,
        "x-correlation-id": "phase3c-test-correlation",
      },
      body: JSON.stringify(body),
    },
  );
}

function dependencies(
  requestFetch: typeof fetch = (() =>
    Promise.resolve(
      Response.json(result("verified_access_process_outbox", true)),
    )) as typeof fetch,
  rateLimiter = createRateLimiter(100, 60_000),
): MaintenanceDependencies {
  const values: Record<string, string> = {
    VERIFIED_ACCESS_MAINTENANCE_SECRET: secret,
    SUPABASE_URL: "http://supabase",
    SUPABASE_SERVICE_ROLE_KEY: "service-role-value",
  };
  return {
    env: { get: (name) => values[name] },
    fetch: requestFetch,
    now: () => 1_000,
    rateLimiter,
  };
}

function result(job: string, dryRun: boolean) {
  return {
    job,
    dryRun,
    processed: 0,
    skipped: 0,
    failed: 0,
    remaining: 0,
  };
}

function equal(left: unknown, right: unknown) {
  if (left !== right) throw new Error(`${left} !== ${right}`);
}
function includes(value: string, expected: string) {
  if (!value.includes(expected)) throw new Error(`missing ${expected}`);
}
function excludes(value: string, forbidden: string) {
  if (value.includes(forbidden)) throw new Error(`leaked ${forbidden}`);
}
