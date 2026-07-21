# Verified Access Phase 2 Validation

Branch: `agent/verified-access-phase-2`

PR: <https://github.com/luisbizzan/confia-interfone-digital/pull/6>

Base: `4284085959e185892f00c77dd89138838ba1dcdb`

Corrective gate initial SHA: `b77978aaa88a94e8d797765e4941d23d562b367b`

Corrective technical SHA: `13951b0284f7aa1dbeed612d4c63a5dce4c14584`

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
`search_path = public, pg_temp`, and is `security definer`. A dedicated
`NOLOGIN`/`NOINHERIT` executor role has EXECUTE only on the exact five RPC
signatures and is granted only to `authenticated`; no function grant is made
directly to `authenticated`. Helpers, tables, `PUBLIC`, `anon`, and
`service_role` remain default-deny.

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

The initial Phase 2 implementation was fully validated by Phase 2 PR run
[`29795016624`](https://github.com/luisbizzan/confia-interfone-digital/actions/runs/29795016624)
and push run
[`29795015534`](https://github.com/luisbizzan/confia-interfone-digital/actions/runs/29795015534).
The Phase 1B and Phase 1C preservation runs were also green. The legacy Phase
1A run `29795016667` failed only when its rollback tried to drop
`verified_access_requests` before removing the Phase 2 command table and its
tenant-qualified foreign key.

The root cause was orchestration drift in
`.github/workflows/verified-access-phase-1a.yml`: it applies every repository
migration from zero, but its rollback sequence knew only about Phases 1B and
1A. The correction reuses the existing rollback scripts in reverse dependency
order: Phase 2, Phase 1C when present, Phase 1B when present, then Phase 1A. No
rollback SQL, migration, grant, RLS policy, domain behavior, or test
expectation was changed.

Corrective runs for technical SHA `13951b0284f7aa1dbeed612d4c63a5dce4c14584`:

| Workflow | Run | Result |
|---|---:|---|
| Phase 1A | [29823125780](https://github.com/luisbizzan/confia-interfone-digital/actions/runs/29823125780) | success |
| Phase 1B | [29823125690](https://github.com/luisbizzan/confia-interfone-digital/actions/runs/29823125690) | success |
| Phase 1C | [29823125675](https://github.com/luisbizzan/confia-interfone-digital/actions/runs/29823125675) | success |
| Phase 2 pull request | [29823125764](https://github.com/luisbizzan/confia-interfone-digital/actions/runs/29823125764) | success |
| Phase 2 push | [29823122516](https://github.com/luisbizzan/confia-interfone-digital/actions/runs/29823122516) | success |
| Vercel | Preview deployment | success |

The corrected Phase 1A database job passed migrations from zero, pgTAP,
integration SQL, runtime-role checks, database lint, rollback from Phase 2
through Phase 1A, rollback-scope verification, migration reapplication,
post-reapplication pgTAP, and post-reapplication integration smoke. Its
admin-web lint and build job also passed.

The Phase 2 pull-request run initially received HTTP 504 responses while
`denoland/setup-deno` downloaded Deno, before any project test executed. The
official failed-job rerun succeeded without source changes. Phase 2 database,
edge-functions, and admin-web jobs are green, including rollback, preservation
of Phases 1A through 1D, reapplication, and post-reapplication tests.

Residual risk is limited to transient external download availability in CI.
The rollback compatibility relies on the versioned rollback files remaining
dependency ordered; future phases that add references to earlier objects must
extend legacy full-stack rollback workflows in the same way.

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
- No remote Supabase migration was executed during the corrective gate.
- `VERIFIED_ACCESS` remains disabled; rollback sentinels were local CI fixtures.
- `CURRENT_TASK` is closed as `NO ACTIVE IMPLEMENTATION`; Phase 3 is not
  authorized.
