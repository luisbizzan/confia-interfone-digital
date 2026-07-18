# Acesso Verificado - Validacao da Fase 1B

Data: 2026-07-16

## Estado Git

- Branch de implementacao: `agent/verified-access-phase-1b`.
- PR: `https://github.com/luisbizzan/confia-interfone-digital/pull/3`.
- Squash merge em `origin/main`:
  `957b01351f412ad75e353e99643cbe99446f9bff`.
- Head validado antes do merge:
  `cfe4b227ec79c521d060c5dc7499e78e5cb5d45a`.

## Escopo Implementado

- Tres feature flags de rede criadas desligadas.
- Sete tabelas centrais de rede.
- Taxonomias canonicas de subjects, identifiers, links, cases, signals,
  reviews e appeals.
- RLS default-deny, sem policies.
- Revogacao explicita de privilegios de `PUBLIC`, `anon`, `authenticated` e
  `service_role`.
- Nenhuma view, RPC, API, provider, HMAC SQL real ou operacao de rede.
- Rollback dedicado e reaplicacao em banco descartavel.

## Findings Gate 1B-FINAL REVIEW

| Finding | Status | Evidencia |
|---|---|---|
| 1B-FINAL-01 links | Corrigido e validado | `link_status` aceita somente `ACTIVE`, `DISPUTED`, `UNLINKED`; `link_reason` aceita somente `IDENTITY_VERIFIED`, `MANUAL_VERIFIED`, `IDENTIFIER_ROTATION`, `SUBJECT_MERGE`, `CORRECTION`; regras de `unlinked_at` cobertas |
| 1B-FINAL-02 appeals | Corrigido e validado | FK composta `(signal_id, network_subject_id)` para signals; appeal sem signal permitido |
| 1B-FINAL-03 condominium report | Corrigido e validado | trigger `verified_access_network_cases_validate_source_subject` valida participant, identity profile e link `ACTIVE`/`DISPUTED` do mesmo subject |
| 1B-FINAL-04 docs/PR | Corrigido | PR body atualizado manualmente antes do merge; README, ROADMAP e CURRENT_TASK registrados no estado pós-merge |

## Migrations da Fase 1B

- `supabase/migrations/20260716100000_verified_access_network_foundation.sql`
- `supabase/migrations/20260716101000_verified_access_network_security.sql`

Nenhuma migration do Acesso Verificado foi aplicada remotamente.

## Tabelas Centrais

- `verified_access_network_subjects`
- `verified_access_network_subject_identifiers`
- `verified_access_network_subject_links`
- `verified_access_network_security_cases`
- `verified_access_network_signals`
- `verified_access_network_signal_reviews`
- `verified_access_network_appeals`

## Invariantes Estruturais

- Signal referencia case do mesmo subject por FK composta.
- Signal exige case `SUBSTANTIATED` por trigger `security invoker`.
- Appeal com signal referencia signal do mesmo subject por FK composta.
- `CONDOMINIUM_REPORT` exige participant local com identity profile e link
  central `ACTIVE` ou `DISPUTED` para o mesmo subject.
- Sources nao locais exigem condominium e participant nulos.
- `LOCAL_DENIED` nao cria case nem signal.
- Features de rede permanecem desligadas.

## CI Verde

### Phase 1B

- Run final pré-merge: `29531896729`.
- URL: `https://github.com/luisbizzan/confia-interfone-digital/actions/runs/29531896729`.
- SHA: `cfe4b227ec79c521d060c5dc7499e78e5cb5d45a`.
- `database`: success.
- `admin-web`: success.

Steps de banco validados:

- Start Supabase local stack: success.
- Apply migrations from scratch: success.
- Run pgTAP database tests: success.
- Run integration SQL scenarios: success.
- Run runtime role permission checks: success.
- Run Supabase database lint: success.
- Roll back Phase 1B objects: success.
- Verify rollback scope: success.
- Reapply migrations: success.
- Re-run pgTAP smoke tests after reapply: success.
- Re-run integration smoke after reapply: success.

### Phase 1A

- Run final pré-merge: `29531896626`.
- URL: `https://github.com/luisbizzan/confia-interfone-digital/actions/runs/29531896626`.
- SHA: `cfe4b227ec79c521d060c5dc7499e78e5cb5d45a`.
- `database`: success.
- `admin-web`: success.
- Rollback/reaplicacao/smokes da Fase 1A: success.

### Vercel

- Status GitHub: success.
- Ambiente identificado pelo deployment/status: Preview.
- Deployment pós-merge em `main`: `5488471803`.
- Ambiente Vercel identificado: `Production`.

## Validacoes Locais

- `git diff --check`: passou.
- `npm run admin:lint`: passou.
- `npm run admin:build`: passou.
- `npx supabase db reset`: nao executado localmente por Docker Desktop
  indisponivel no ambiente Windows; executado com sucesso no CI.

## Rollback

Rollback dedicado:

- `supabase/rollback/20260716100000_verified_access_phase_1b_rollback.sql`

Remove triggers, funcoes, tabelas e flags da Fase 1B. Preserva Fase 1A,
`persons`, `INTERCOM`, `VERIFIED_ACCESS` e
`VERIFIED_ACCESS_BACKGROUND_CHECK`.

## Fora de Escopo Confirmado

- Nenhuma Fase 1C ou 1D.
- Nenhuma migration remota.
- Nenhuma feature flag habilitada.
- Nenhuma alteracao em `persons`.
- Nenhuma alteracao no app Expo.
- Nenhum deploy manual.
- Merge por squash realizado no PR #3.
