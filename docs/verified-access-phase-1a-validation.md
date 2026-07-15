# Acesso Verificado - Validacao da Fase 1A

Data: 2026-07-15

## Estado Git

- Base: `origin/main` em `8a4ff78`.
- SHA inicial da Fase 1A: `d8609ee7d50e7c431ff433afdd54bbe4d8c44ecf`.
- SHA inicial do Gate 1A-FINAL: `0f1dabf257ed006769e9a412e8a0bfbdff54d00f`.
- SHA validado: `4802dce9af17eb152f51724b34fdbf33a0142598`.
- Branch: `agent/verified-access-phase-1a-r`.
- Draft PR: `https://github.com/luisbizzan/confia-interfone-digital/pull/2`.

## Migrations da Fase 1A

- `supabase/migrations/20260714100000_verified_access_local_foundation.sql`
- `supabase/migrations/20260714101000_verified_access_local_security.sql`

As migrations aplicaram do zero no banco descartavel do GitHub Actions.
Nenhuma migration remota foi executada.

## Gaps corrigidos

- Removida funcao cross-table em `CHECK` para `OTHER`.
- Adicionados triggers `security invoker` com `search_path` fixo.
- Adicionadas FKs compostas para request/policy/version, participant/slot/request e evaluation/participant/request.
- Adicionada validacao de detalhe somente para `SERVICE_PROVIDER`.
- Adicionada validacao de capacidade de slot por `participant_limit`.
- Revisada semantica de `claimed_at`.
- Corrigidas fixtures para que testes negativos violem uma invariante por vez.
- Corrigido rollback para validar `INTERCOM` em `condominium_features`.
- Corrigido rollback para remover indices auxiliares da Fase 1A.
- Outbox tornou-se parcialmente imutavel.
- Auditoria bloqueia update, delete e truncate.
- Grants de `service_role` foram revogados antes dos grants minimos.
- JSON de audit/outbox/evaluation/policy limitado a objeto quando aplicavel.
- Policy V2 reconciliada com campos separados para visitante e prestador.
- Identity profile minimizado para HMAC local de CPF, documento e telefone.
- Request/evaluation reconciliados com campos de expiracao, ator e snapshot sanitizado.
- Diagnostics do workflow nao fazem upload do log bruto de `supabase start`.

## Migration drift

Ver `docs/verified-access-phase-1a-repository-drift.md`.

Quatro migrations antigas estao aplicadas no remoto e presentes como untracked na checkout original, mas ausentes de `origin/main`. Elas nao pertencem a Fase 1A e nao foram incluidas nesta branch.

## Testes locais

| Comando | Resultado | Evidencia |
|---|---|---|
| `npm run admin:lint` | Passou | ESLint sem erros |
| `npm run admin:build` | Passou | Next build concluido |
| `npx supabase start` | Bloqueado localmente | Docker nao esta instalado/disponivel nesta sessao Windows |
| `npx supabase db reset` | Bloqueado localmente | Docker indisponivel |
| `npx supabase test db` | Bloqueado localmente | Postgres local `127.0.0.1:54322` indisponivel |
| `npx supabase db lint` | Bloqueado localmente | Postgres local `127.0.0.1:54322` indisponivel |

## CI verde

- Workflow: `.github/workflows/verified-access-phase-1a.yml`.
- Run PR verde: `29417139604`.
- URL: `https://github.com/luisbizzan/confia-interfone-digital/actions/runs/29417139604`.
- SHA: `4802dce9af17eb152f51724b34fdbf33a0142598`.

### Job `database`

| Step | Resultado |
|---|---|
| Start Supabase local stack | success |
| Apply migrations from scratch | success |
| Run pgTAP database tests | success, 233 testes |
| Run integration SQL scenarios | success |
| Run runtime role permission checks | success |
| Run Supabase database lint | success |
| Create rollback sentinel | success |
| Roll back Phase 1A objects | success |
| Verify rollback scope | success |
| Reapply migrations | success |
| Re-run pgTAP smoke tests after reapply | success |
| Re-run integration smoke after reapply | success |
| Stop Supabase local stack | success |
| Upload diagnostics | skipped, pois o run verde nao falhou |

### Job `admin-web`

| Step | Resultado |
|---|---|
| Install dependencies | success |
| Lint admin web | success |
| Build admin web | success |

## Rollback e reaplicacao

O rollback foi executado no banco descartavel do GitHub Actions.

O workflow verificou:

- nenhum objeto `verified_access_%` permaneceu depois do rollback;
- `public.persons` permaneceu;
- `public.condominium_features` permaneceu;
- `public.condominium_feature_enabled(uuid,text)` permaneceu;
- sentinel `INTERCOM = true` permaneceu em `condominium_features`;
- features `VERIFIED_ACCESS` e `VERIFIED_ACCESS_BACKGROUND_CHECK` do sentinel foram removidas;
- indices auxiliares `ux_units_id_condominium_id` e `ux_user_profiles_id_condominium_id` foram removidos.

A reaplicacao via `npx supabase db reset` passou. O pgTAP e a integracao SQL passaram novamente apos a reaplicacao.

## Artifacts e diagnosticos

- O workflow cria `/tmp/verified-access-supabase-start-sanitized.log`.
- O log bruto `/tmp/verified-access-supabase-start.log` e removido antes de qualquer upload.
- O upload lista paths explicitos e nao usa wildcard que capture o log bruto.
- O artifact bruto anterior do run `29412883145` foi removido via API oficial.
- No run verde `29417139604`, o step `Upload diagnostics` ficou `skipped` porque nao houve falha.

## Features

`VERIFIED_ACCESS` e `VERIFIED_ACCESS_BACKGROUND_CHECK` permanecem desligadas por padrao.

## Status

Gate 1A-FINAL aprovado no CI em banco descartavel.
Branch permanece em draft PR para revisao humana; nao houve merge.
