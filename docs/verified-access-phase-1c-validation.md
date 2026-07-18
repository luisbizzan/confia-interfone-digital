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

Post-diagnostic CI: pending after the runtime permissions hardening commit.
