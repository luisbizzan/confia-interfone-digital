# Verified Access Phase 3B validation

Validation date: 2026-07-22.

## Scope

Phase 3B implements the local public-registration foundation: invitation
exchange, hash-only public sessions, protected identity-profile submission,
participant and slot completion, sanitized audit/outbox events, five Edge
endpoints, and the isolated `apps/verified-access-public` Next.js application.

The technical validation head was
`2696fed293a1255076bfd60aed35ec98108e54c7`. Pull request #8 remains a draft.

## Legacy rollback correction

The initial Phase 1A and Phase 3A regression runs failed because their legacy
workflows attempted to remove `verified_access_invitations` while Phase 3B
tables still referenced it through these composite foreign keys:

- `verified_access_public_sessions_invitation_tenant_fk`;
- `verified_access_public_commands_invitation_tenant_fk`.

No schema, foreign key, constraint, or rollback SQL was changed. The workflows
now call the existing dedicated rollback scripts in dependency order:

```text
3B -> 3A -> 2 -> 1C -> 1B -> 1A
```

The Phase 3A workflow uses the applicable prefix `3B -> 3A`. The Phase 1A
workflow exercises the complete cumulative order. Both continue to fail
strictly on SQL errors; there is no `CASCADE`, `continue-on-error`, ignored
failure, or reduced verification.

Workflows changed:

- `.github/workflows/verified-access-phase-1a.yml`;
- `.github/workflows/verified-access-phase-3a.yml`.

## Final CI evidence

All runs below executed against technical head
`2696fed293a1255076bfd60aed35ec98108e54c7` and completed successfully:

| Scope | Run | Result |
|---|---|---|
| Phase 1A | [29962641406](https://github.com/luisbizzan/confia-interfone-digital/actions/runs/29962641406) | success |
| Phase 1B | [29962641301](https://github.com/luisbizzan/confia-interfone-digital/actions/runs/29962641301) | success |
| Phase 1C | [29962641382](https://github.com/luisbizzan/confia-interfone-digital/actions/runs/29962641382) | success |
| Phase 2 | [29962641362](https://github.com/luisbizzan/confia-interfone-digital/actions/runs/29962641362) | success |
| Phase 3A | [29962641348](https://github.com/luisbizzan/confia-interfone-digital/actions/runs/29962641348) | success |
| Phase 3B | [29962641314](https://github.com/luisbizzan/confia-interfone-digital/actions/runs/29962641314) | success |

Phase 3B passed migrations, pgTAP, integration tests for Phases 1A through 3B,
runtime-role checks, database lint, Phase 3B rollback, preservation of Phases
1A through 3A, reapplication, and post-reapplication integration/runtime
checks. Its Edge, public-web, and admin-web jobs also passed.

Phase 1A passed the complete cumulative rollback, rollback-scope sentinels,
reapplication, post-reapplication pgTAP, and integration smoke. Phase 3A
passed `3B -> 3A` rollback, preservation of Phases 1A through 2, reapplication,
pgTAP, and post-reapplication integration. The Phase 1B, 1C, and 2 regression
workflows also passed their rollback, preservation, reapplication, and smoke
checks.

## Applications and deployment checks

- admin-web lint and build: success in the Phase 1A, 1B, 1C, 2, 3A, and 3B
  workflows;
- public application lint, typecheck, 10 Vitest tests, and build: success in
  Phase 3B;
- Edge format, lint, typecheck, 17 unit tests, and log/secret guard: success;
- Vercel: success for the existing `apps/admin-web` Preview deployment,
  [inspection](https://vercel.com/confia-interfone-s-projects/confia-interfone-digital-admin-web/FfMdxEG65YPdMNoDaW8rx7LMbMrW) and
  [preview](https://confia-interfone-digital-git-efe817-confia-interfone-s-projects.vercel.app).

Vercel did not deploy the isolated public application in this gate; the
reported Preview belongs to the configured admin-web project.

## Security and safety confirmation

- No grants, RLS policies, foreign keys, or constraints were weakened.
- No `CASCADE`, masked failure, or reduced test coverage was introduced.
- `PUBLIC`, `anon`, and `authenticated` received no new database access.
- The public session remains opaque, hash-only, and limited to 30 minutes.
- Audit and outbox payloads remain sanitized and contain no PII.
- `VERIFIED_ACCESS` remains disabled.
- No Verified Access migration was executed against remote Supabase.
- `persons`, Expo, providers, and external integrations were not changed.
- Phase 3C and Phase 4 remain unauthorized.

Legal text, production domain/proxy, submitted-data retention, key custody,
and the production rate-limit design remain human gates. The implementation is
not authorized for production rollout while those gates remain open.
