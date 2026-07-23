# Verified Access Phase 3C validation

## Status

Implementation validated on draft PR #9.

## Scope

- two local migrations;
- seven bounded maintenance jobs;
- one default-deny findings table;
- one internal Edge runner;
- one manual-only maintenance workflow;
- one dedicated CI workflow;
- cumulative rollback compatibility for legacy workflows;
- rollback, tests and operator runbook.

## Safety

- no remote migration;
- no feature enabled;
- no remote scheduler enabled;
- no real provider or external integration;
- no PII added to maintenance storage, logs, audit or outbox;
- no changes to `persons`, Expo, admin-web or public application runtime;
- no widened table grants;
- no merge or mark ready.

## Local validation

| Validation | Result |
|---|---|
| Edge format | passed |
| Edge lint | passed |
| Edge type-check | passed |
| Edge unit tests | 5 passed |
| Supabase db reset | unavailable: Docker daemon absent |
| pgTAP/integration/runtime roles | passed in CI |
| database lint | passed in CI |
| rollback and 1A-3B preservation | passed in CI |
| reapplication and post-reapplication smoke | passed in CI |
| admin-web lint/build | passed locally and in CI |
| public web lint/type-check/tests/build | passed locally and in CI; 10 tests |
| YAML lint | passed locally |
| `git diff --check` | passed before commits |

## CI

First full green cycle at technical SHA
`45b6c90f9c60db8f4897f2a86cacacb742fbd319`:

| Workflow | Run | Result |
|---|---:|---|
| Phase 1A | [30048599555](https://github.com/luisbizzan/confia-interfone-digital/actions/runs/30048599555) | success |
| Phase 1B | [30048599564](https://github.com/luisbizzan/confia-interfone-digital/actions/runs/30048599564) | success |
| Phase 1C | [30048599596](https://github.com/luisbizzan/confia-interfone-digital/actions/runs/30048599596) | success |
| Phase 2 | [30048599512](https://github.com/luisbizzan/confia-interfone-digital/actions/runs/30048599512) | success |
| Phase 3A | [30048599591](https://github.com/luisbizzan/confia-interfone-digital/actions/runs/30048599591) | success |
| Phase 3B | [30048599612](https://github.com/luisbizzan/confia-interfone-digital/actions/runs/30048599612) | success |
| Phase 3C | [30048599602](https://github.com/luisbizzan/confia-interfone-digital/actions/runs/30048599602) | success |
| Phase 3C pull request event | [30048595727](https://github.com/luisbizzan/confia-interfone-digital/actions/runs/30048595727) | success |

Phase 3C run `30048599602` passed:

- migrations from scratch;
- pgTAP for all phases;
- integrations 1A through 3C;
- runtime role checks;
- database lint;
- Phase 3C rollback;
- Phase 1A-3B preservation;
- migration reapplication and pgTAP;
- post-reapplication integrations and runtime checks;
- Edge format, lint, type-check and 5 tests;
- manual scheduler policy;
- admin-web lint/build;
- public web lint/type-check/10 tests/build.

Vercel Preview status for PR #9: `SUCCESS`.

Final documentation SHA and its resulting checks are recorded in the PR report
after the final push.

## Rollback order

```text
3C -> 3B -> 3A -> 2 -> 1C -> 1B -> 1A
```

The Phase 3C rollback uses explicit drops, no `CASCADE`, and preserves all
objects from prior phases.

## Remote state

- no Supabase remote migration was executed;
- no remote scheduler or cron was enabled;
- no feature was enabled;
- no deployment was performed manually.
