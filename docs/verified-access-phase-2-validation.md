# Verified Access Phase 2 Validation

Branch: `agent/verified-access-phase-2`

PR: <https://github.com/luisbizzan/confia-interfone-digital/pull/6>

Base: `4284085959e185892f00c77dd89138838ba1dcdb`

## Scope

Phase 2 adds authenticated resident request commands, five narrowly scoped
RPCs, five authenticated Edge Functions, persistent idempotency, sanitized
audit/outbox writes, database and Deno tests, rollback, and a dedicated CI
workflow. The implementation is limited to the paths authorized by
`CURRENT_TASK`.

## Database

The two authorized local migrations are:

- `20260720100000_verified_access_request_commands.sql`;
- `20260720101000_verified_access_resident_request_rpcs.sql`.

`verified_access_request_commands` is default-deny with RLS, no permissive
policies, no direct runtime grants, tenant-qualified foreign keys, bounded
idempotency keys, versioned server fingerprints, and coherent PROCESSING or
COMPLETED result state.

The exact authenticated RPC surface is:

- `verified_access_list_resident_service_types`;
- `verified_access_create_resident_request`;
- `verified_access_list_resident_requests`;
- `verified_access_get_resident_request`;
- `verified_access_cancel_resident_request`.

Each RPC derives actor and tenant server-side, has a fixed
`search_path = public, pg_temp`, and is `security definer`. Only the exact five
RPC signatures have the technical `authenticated` EXECUTE grant. Helpers,
tables, `PUBLIC`, `anon`, and `service_role` remain default-deny.

## Edge Functions

The five functions validate the bearer token against Supabase Auth and invoke
the exact RPC with the same user JWT and anon API key. They do not use the
service-role key. JSON bodies have strict allowlists and a 16 KiB limit;
queries are allowlisted; correlation IDs are generated or validated; CORS is
restricted to configured origins; errors expose stable codes only. No request
body, Authorization header, free text, or PII is logged.

## Idempotency and Events

CREATE fingerprints exclude actor, tenant, policy, correlation ID, attempt
time, status, and client request ID. CANCEL fingerprints contain only request
ID and reason code. Same-key retries return the completed logical result;
different fingerprints fail with `IDEMPOTENCY_CONFLICT`; in-progress commands
fail with `COMMAND_IN_PROGRESS`.

Request/detail/slots, audit, outbox, and command completion are written in the
same transaction. Audit stores the derived actor and sanitized codes/IDs.
Outbox payloads contain only the authorized structural fields and use a
command-derived deduplication key. Neither stream contains purpose,
operational note, service description, participant identity, or PII.

## Local Validation

Executed on the Windows worktree with Deno `2.9.3`:

| Check | Result |
|---|---|
| Deno format check | success |
| Deno type check | success |
| Deno lint | success |
| Deno unit tests | 12 passed, 0 failed |
| `npm run admin:lint` | success |
| `npm run admin:build` | success |
| Phase 2 workflow format | success |
| `git diff --check` | success |

The local host has no Docker engine, PostgreSQL client, or Supabase local
database runtime. Database reset, migrations, pgTAP, SQL integration, runtime
roles, database lint, rollback, preservation, reapplication, and
post-reapplication smoke tests therefore remain pending until the dedicated
GitHub Actions jobs execute. They are not reported as locally passed.

## CI

Pending the first Phase 2 branch run. `CURRENT_TASK` remains active until the
database, edge-functions, admin-web, rollback, preservation, reapplication,
and post-reapplication gates are all green.

## Safety

- No remote Supabase migration was executed.
- `VERIFIED_ACCESS` remains disabled outside rollback-scoped test fixtures.
- No participant, identity profile, invitation, credential, provider call, or
  operational Rede Confia behavior is created.
- No name, phone, CPF, document, birth data, biometrics, background data, or
  provider identifier is collected.
- `persons`, Expo, UI, and admin-web runtime code remain unchanged.
- The Supabase Postgres #2112 workaround skips only crashing reserved-role
  calls on affected images and still requires real SQLSTATE `42501` checks
  through a synthetic non-reserved role. No grant is widened.
