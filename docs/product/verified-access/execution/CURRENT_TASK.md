# CURRENT TASK — VA-P3C-MAINTENANCE-HARDENING

## Authorization

Phase 3C is authorized only for operational hardening of the Verified Access
invitation and public-registration foundation already delivered by Phases 3A
and 3B.

The implementation must remain local and review-only. No remote Supabase
migration, feature enablement, rollout, merge, ready-for-review transition, or
force-push is authorized.

## Authorized deliverables

1. Add bounded, idempotent and concurrency-safe maintenance jobs for:
   - expiring eligible invitations;
   - expiring or revoking invalid public sessions;
   - purging retained public commands;
   - purging expired rate-limit buckets;
   - conservatively reconciling public-registration state;
   - processing only explicitly supported local outbox events;
   - applying the documented retention policy.
2. Add a hardened internal Edge Function that invokes only those jobs through
   exact internal RPC signatures.
3. Add a manually triggered scheduler workflow. A remote schedule is
   documented but must not be enabled in this task.
4. Add sanitized aggregate observability, operational findings, tests,
   rollback, reapplication, CI and an operator runbook.
5. Preserve all Phase 1A, 1B, 1C, 2, 3A and 3B invariants.

## Required job contract

The only authorized maintenance RPCs are:

- `verified_access_expire_invitations`
- `verified_access_expire_public_sessions`
- `verified_access_purge_public_commands`
- `verified_access_purge_rate_limit_buckets`
- `verified_access_reconcile_public_registration_state`
- `verified_access_process_outbox`
- `verified_access_apply_retention_policy`

Every job must:

- accept a bounded batch size, a dry-run flag and a sanitized correlation ID;
- use deterministic ordering and `FOR UPDATE SKIP LOCKED` where rows are
  claimed;
- be idempotent and safe under concurrent execution;
- return only aggregate counters and sanitized operational metadata;
- run with a fixed `search_path` and a finite statement timeout;
- preserve tenant scope and default-deny table access;
- avoid external integrations, PII, participant creation, identity-profile
  creation and automatic identity decisions;
- record domain audit/outbox changes in the same transaction when applicable;
- isolate per-item failures without masking the aggregate job result.

## Security boundaries

- The internal Edge Function is authenticated only by a dedicated maintenance
  secret and exposes no browser-facing CORS surface.
- Runtime roles receive no direct table access and no new broad grants.
- `service_role` may reach only the exact maintenance RPC signatures through a
  dedicated NOLOGIN executor role.
- Helper functions remain private and are not executable by `PUBLIC`, `anon`,
  `authenticated` or `service_role`.
- No real provider, webhook, queue consumer, distributed rate-limit service or
  remote scheduler is authorized.
- Logs, responses, audit metadata and outbox payloads must not contain tokens,
  secrets, raw documents, phone numbers, email addresses, names or other PII.

## Exact allowlist

Only the following paths may be created or changed:

- `docs/product/verified-access/execution/CURRENT_TASK.md`
- `docs/product/verified-access/phases/PHASE_3C.md`
- `docs/product/verified-access/phases/PHASE_3.md`
- `docs/verified-access-phase-3c-validation.md`
- `docs/product/verified-access/operations/PHASE_3C_RUNBOOK.md`
- `supabase/migrations/20260723100000_verified_access_maintenance_foundation.sql`
- `supabase/migrations/20260723101000_verified_access_maintenance_jobs.sql`
- `supabase/rollback/verified_access_phase_3c_rollback.sql`
- `supabase/functions/verified-access-maintenance-run/index.ts`
- `supabase/functions/verified-access-maintenance-run/index.test.ts`
- `supabase/tests/verified_access_phase_3c.sql`
- `supabase/tests/verified_access_phase_3c_integration.psql`
- `supabase/tests/verified_access_phase_3c_runtime_roles.psql`
- `.github/workflows/verified-access-phase-3c.yml`
- `.github/workflows/verified-access-maintenance.yml`
- `.github/workflows/verified-access-phase-1a.yml`
- `.github/workflows/verified-access-phase-3a.yml`
- `.github/workflows/verified-access-phase-3b.yml`
- `supabase/config.toml`

If another path is required, execution must stop as blocked before editing it.

## Required validation

- local database reset;
- pgTAP for Phases 1A through 3C;
- SQL integration tests for Phases 1A through 3C;
- runtime-role checks;
- tenant isolation, idempotency and concurrency checks;
- dry-run, audit, outbox, reconciliation and retention checks;
- database lint;
- Edge Function unit tests;
- admin-web lint and build;
- public application lint, tests and build where configured;
- Phase 3C rollback, preservation of prior phases, reapplication and
  post-reapplication smoke tests;
- legacy rollback workflow verification;
- `git diff --check` and exact-path audit.

## Commit sequence

1. `docs: authorize verified access phase 3c hardening`
2. `feat(db): add verified access phase 3c maintenance jobs`
3. `feat(edge): add verified access maintenance runner`
4. `test(ci): validate verified access phase 3c maintenance`
5. `docs: close verified access phase 3c hardening`

The final documentation commit must restore this file exactly to:

`# CURRENT TASK — NO ACTIVE IMPLEMENTATION`

## Explicitly out of scope

- remote migrations or remote scheduler activation;
- enabling any Verified Access feature flag;
- Phase 4 or unrelated product work;
- changes to `persons`, Expo, resident/admin runtime UI or public-registration
  application behavior;
- real provider, webhook, queue, email, SMS or background-check integration;
- new PII storage, identity matching, automatic denials or negative-signal
  propagation;
- destructive schema changes, `CASCADE`, weakened constraints or widened
  grants;
- merge or ready-for-review transition.
