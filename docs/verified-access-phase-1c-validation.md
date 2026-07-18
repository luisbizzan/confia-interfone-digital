# Verified Access Phase 1C Validation

Branch: `agent/verified-access-phase-1c`

This document records the Phase 1C execution evidence for state-machine hardening, policy lifecycle RPCs, and transactional audit/outbox helpers.

## Scope

- Migrations:
  - `20260718100000_verified_access_state_machines.sql`
  - `20260718101000_verified_access_policy_rpcs.sql`
  - `20260718102000_verified_access_audit_outbox_helpers.sql`
- Rollback:
  - `20260718100000_verified_access_phase_1c_rollback.sql`
- Tests:
  - `verified_access_phase_1c.sql`
  - `verified_access_phase_1c_integration.psql`
  - `verified_access_phase_1c_runtime_roles.psql`
- CI:
  - `verified-access-phase-1c.yml`

## Safety Notes

- No remote Supabase migrations are executed by this branch.
- No feature flags are enabled by Phase 1C migrations.
- No `persons` table changes are introduced.
- No Expo app files are changed.
- State-machine triggers are pure `security invoker` validators and do not write audit or outbox rows.
- Audit and outbox writes are limited to the three policy RPCs.

## Local Results

- `git diff --check`: passed.
- `npm run admin:lint`: passed.
- `npm run admin:build`: passed.
- `npx supabase db reset`: blocked locally because Docker Desktop is not available on this Windows host.
- `npx supabase db lint`: blocked locally because no Supabase local Postgres is listening on `127.0.0.1:54322`.
- `1C-RUNTIME-PERMISSIONS` local reproduction: blocked locally because the Supabase CLI cannot connect to a Docker engine on this Windows host and `docker` is not available in the shell PATH.

## Runtime Permissions Diagnostic

The `verified-access-phase-1c.yml` runtime role check was hardened to diagnose the previous connection loss without changing grants:

- introspects `has_function_privilege` for `anon`, `authenticated`, and `service_role`;
- inspects `pg_proc` signatures, owners, `prosecdef`, ACLs, and fixed `search_path`;
- verifies simple `SET ROLE` for each runtime role before calling RPCs;
- calls Phase 1C RPCs/helpers with explicit five/nine-argument signatures;
- accepts only SQLSTATE `42501` for negative execution checks;
- records `pg_isready` and `docker ps -a` after each diagnostic step;
- captures and sanitizes PostgreSQL container logs on connection loss or unexpected SQLSTATE.

## Supabase Postgres #2112 Workaround

The connection loss was confirmed as the upstream
[`supabase/postgres#2112`](https://github.com/supabase/postgres/issues/2112)
regression. On `public.ecr.aws/supabase/postgres:17.6.1.106`, a revoked
function call made after `SET ROLE anon` terminated the backend with signal 11,
started PostgreSQL crash recovery, and returned no SQLSTATE to the client.
Catalog inspection before the crash confirmed that the Phase 1C ACLs were
correct: `anon`, `authenticated`, and `service_role` had no `EXECUTE` privilege.

The runtime harness now detects the real database container image without
depending on a container name. For affected `17.6.1.100+` images it records
`SKIPPED_UPSTREAM_SUPABASE_POSTGRES_2112` and does not deliberately invoke a
revoked function as a Supabase reserved role. The skip applies only to that
known crash path. The following compensating checks remain mandatory:

- all five exact function signatures exist without overloads;
- owner, `prosecdef`, ACL, and fixed `search_path` match the contract;
- `has_function_privilege(..., 'EXECUTE')` is false for all three runtime roles;
- simple role switching succeeds for `anon`, `authenticated`, and `service_role`;
- a non-reserved synthetic role makes real negative calls to the create-policy
  RPC, activate-policy RPC, and audit helper, each requiring SQLSTATE `42501`;
- the synthetic role is removed on success and by a workflow trap on failure;
- PostgreSQL remains ready after the harness.

When the detected image is outside the affected range, the harness also makes
real negative calls as `anon` and `authenticated` and requires SQLSTATE `42501`.
The workaround can be removed after an upstream-fixed image is adopted and
those reserved-role calls pass without a backend restart. No grant was added or
expanded by this workaround.

## GitHub Actions Results

Latest pre-diagnostic run:

- Phase 1A preservation: success, run `29650084749`.
- Phase 1B preservation: success, run `29650084762`.
- Phase 1C: run `29650084731`.
  - `admin-web`: success.
  - migrations: success.
  - pgTAP: success.
  - integration SQL: success.
  - runtime role permission checks: failed due connection loss while checking the first `anon` RPC call.

Diagnostic run `29651031221` confirmed:

- image: `public.ecr.aws/supabase/postgres:17.6.1.106`;
- ACL matrix: false for `anon`, `authenticated`, and `service_role`;
- exact Phase 1C RPC/helper signatures, owner `postgres`, `prosecdef = true`,
  owner-only ACL, and `search_path = public, pg_temp`;
- simple role switching: success for all three runtime roles;
- first explicit call as `anon`: backend SIGSEGV and recovery, matching #2112.

## Post-workaround CI

Workaround commit: `735d4c93bfb2f07ca2da4db1b95cd8be39ae3fa4`.

- Phase 1C pull-request run `29653749644`: success.
  - `database`: success, including migrations, pgTAP, integrations 1A/1B/1C,
    runtime harness, db lint, rollback, rollback verification, reapplication,
    post-reapplication pgTAP/integration, and post-reapplication runtime harness.
  - `admin-web`: lint and build success.
- Phase 1C push run `29653748217`: success with the same database and
  `admin-web` sequence.
- Phase 1A preservation run `29653749597`: database and `admin-web` success,
  including rollback and reapplication.
- Phase 1B preservation run `29653749594`: database and `admin-web` success,
  including rollback and reapplication.
- Vercel Preview deployment for the workaround commit: success.

Environment recorded by the Phase 1C run:

- Supabase CLI: `2.98.2`;
- database image: `public.ecr.aws/supabase/postgres:17.6.1.106`;
- PostgreSQL: `17.6` on `x86_64-pc-linux-gnu`;
- `supautils` extension version: not exposed through `pg_extension` in this
  image;
- `supautils.hint_roles`: `anon, authenticated, service_role`;
- `supautils.reserved_roles`: includes `service_role*`, `authenticated*`, and
  `anon*`.

The effective ACL matrix was false for every combination of the five protected
functions and the three runtime roles. Every function had owner `postgres`,
`prosecdef = true`, ACL `{postgres=X/postgres}`, and fixed
`search_path = public, pg_temp`. Simple role switching passed for all three
runtime roles. The synthetic role received SQLSTATE `42501` from create-policy,
activate-policy, and audit-helper calls, was dropped, and the affected-image
path recorded `SKIPPED_UPSTREAM_SUPABASE_POSTGRES_2112`. `pg_isready` reported
the database accepting connections after the post-reapplication harness.
