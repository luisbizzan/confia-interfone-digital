# Acesso Verificado - Validacao da Fase 1B

Data: 2026-07-16

## Estado Git

- Branch: `agent/verified-access-phase-1b`.
- Base: `origin/main` em `84077aa18731f83d6e8cfa505b7d10dec2b89026`.
- Draft PR: `https://github.com/luisbizzan/confia-interfone-digital/pull/3`.
- SHA validado no Gate 1B-FINAL REVIEW antes desta atualizacao documental:
  `71d9929e46e12c95e328f2273a32259ed1ccb26b`.

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
| 1B-FINAL-04 docs/PR | Parcial | README, ROADMAP e CURRENT_TASK atualizados; PR body bloqueado por permissao da GitHub App, fallback manual requerido |

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

- Run: `29531335271`.
- URL: `https://github.com/luisbizzan/confia-interfone-digital/actions/runs/29531335271`.
- SHA: `71d9929e46e12c95e328f2273a32259ed1ccb26b`.
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

- Run: `29531335267`.
- URL: `https://github.com/luisbizzan/confia-interfone-digital/actions/runs/29531335267`.
- SHA: `71d9929e46e12c95e328f2273a32259ed1ccb26b`.
- `database`: success.
- `admin-web`: success.
- Rollback/reaplicacao/smokes da Fase 1A: success.

### Vercel

- Status GitHub: success.
- Ambiente identificado pelo deployment/status: Preview.

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
- Nenhum merge.
