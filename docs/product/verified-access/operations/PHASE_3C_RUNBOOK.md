# Runbook — Verified Access Phase 3C maintenance

## 1. Scope

This runbook covers the manual Phase 3C maintenance workflow. No remote
schedule is enabled by the repository.

Do not run maintenance against a remote environment without explicit human
authorization for that environment, its secrets and the intended job.

## 2. Preconditions

Confirm:

- the target environment is explicitly approved;
- migrations 3A, 3B and 3C are present;
- `VERIFIED_ACCESS` remains in the approved state;
- the `verified-access-maintenance` GitHub environment has required reviewers;
- `VERIFIED_ACCESS_MAINTENANCE_URL` and
  `VERIFIED_ACCESS_MAINTENANCE_SECRET` are configured as environment secrets;
- no previous maintenance run is active.

Never paste secrets, URLs containing credentials, tokens, payloads or raw
responses into logs, issues or pull requests.

## 3. Dry-run

1. Open the `Verified Access Maintenance` workflow.
2. Select one job.
3. Use `batch_size = 100`.
4. Keep `dry_run = true`.
5. Review only the aggregate step summary.

Expected counters:

- `processed`: candidates inspected in dry-run or mutations completed;
- `skipped`: dependencies or safety conditions prevented mutation;
- `failed`: isolated item failures;
- `remaining`: capped estimate of eligible work still present.

Dry-run must not create audit, outbox, findings or domain mutations.

## 4. Write execution

Write mode requires an approved dry-run and explicit human authorization.

1. Run the same job with the same batch size and `dry_run = false`.
2. Do not start a second run; workflow concurrency is serialized.
3. Require `failed = 0`.
4. Repeat only while `remaining > 0` and the operational time budget permits.
5. Run a final dry-run to confirm convergence.

Start with:

1. `expire_invitations`
2. `expire_public_sessions`
3. `reconcile_public_registration_state`
4. `process_outbox`
5. `purge_rate_limit_buckets`
6. `purge_public_commands`
7. `apply_retention_policy`

Retention should remain dry-run until the target environment receives separate
approval for destructive maintenance.

## 5. Findings

Findings are sanitized technical inconsistencies. They are not access
decisions.

- command stuck: investigate the idempotent command before a later purge;
- outbox overdue: inspect handler availability and lease age without reading
  payload into logs;
- invitation/session mismatch: validate domain history and existing audit;
- participant/slot inconsistency: escalate to application and privacy owners;
  do not auto-create identity data.

Never resolve a finding by manually editing PII or weakening a constraint.

## 6. Failure handling

Stop and escalate when:

- `failed > 0`;
- counters grow across repeated dry-runs;
- database or Edge availability is degraded;
- tenant isolation, ACL, RLS, audit or outbox checks fail;
- a job requires a path, grant or schema change not in the active contract;
- retention encounters an unexpected dependent record;
- secrets may have been exposed.

Do not use `continue-on-error`, `CASCADE`, direct table grants or manual state
rewrites as a workaround.

## 7. Operational rollback

For an invocation problem:

1. stop launching new runs;
2. rotate or disable the maintenance secret;
3. leave the feature state unchanged;
4. preserve aggregate run evidence;
5. open an incident with codes and counters only.

Database rollback is for disposable validation environments or an explicitly
approved deployment rollback. It removes 3C objects only and does not reverse
already committed domain terminal states.

## 8. Secret rotation

1. Generate a new high-entropy secret in the approved secret manager.
2. Update the Edge environment.
3. Update the protected GitHub environment secret.
4. Test with dry-run.
5. Revoke the previous secret.

Never log either value or store it in repository files.

## 9. Scheduler activation

The repository workflow is manual. Enabling a cron/schedule is a separate
change requiring:

- environment and rollout authorization;
- frequency and batch approval;
- alert ownership;
- secret lifecycle;
- cost and SLA review;
- rollback and incident plan.
