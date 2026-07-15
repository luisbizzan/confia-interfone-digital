# Acesso Verificado - Validacao da Fase 1A

Data: 2026-07-15

## Estado Git

- Base: `origin/main` em `8a4ff78`.
- SHA inicial da Fase 1A: `d8609ee7d50e7c431ff433afdd54bbe4d8c44ecf`.
- SHA inicial do Gate 1A-FINAL: `0f1dabf257ed006769e9a412e8a0bfbdff54d00f`.
- SHA inicial do Gate 1A-REVIEW: `9f758a7d768af87753923c65d881d15df4e5d0d5`.
- SHA validado no Gate 1A-REVIEW: `7aeed1cf1f0027a8b3aa99fd4657ce842a70cc3a`.
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
- Privacy approval passa a ser obrigatoria para identidade de visitante ou prestador em `OPTIONAL` ou `REQUIRED`.
- Telefone deixa de ser identificador unico; CPF e documento continuam unicos por condominio e versao de chave.
- Alteracao de catalogo `requires_description false -> true` fica bloqueada quando ha detalhes existentes sem `other_description`.

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
- Run PR verde: `29436074139`.
- URL: `https://github.com/luisbizzan/confia-interfone-digital/actions/runs/29436074139`.
- SHA: `7aeed1cf1f0027a8b3aa99fd4657ce842a70cc3a`.

### Job `database`

| Step | Resultado |
|---|---|
| Start Supabase local stack | success |
| Apply migrations from scratch | success |
| Run pgTAP database tests | success, 239 testes |
| Run integration SQL scenarios | success |
| Run runtime role permission checks | success |
| Run Supabase database lint | success |
| Create rollback sentinel | success |
| Roll back Phase 1A objects | success |
| Verify rollback scope | success |
| Reapply migrations | success |
| Re-run pgTAP smoke tests after reapply | success, 239 testes |
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

## Gate 1A-REVIEW

PM-01:

- `verified_access_policies_privacy_approval_check` criada.
- Integração cobre `visitor_identity_mode` `OPTIONAL` e `REQUIRED` sem referencia, e `service_identity_mode` `OPTIONAL` e `REQUIRED` sem referencia, todos com `23514`.
- Integração cobre ambos `DISABLED` sem referencia, visitor `REQUIRED` com referencia e service `REQUIRED` com referencia.
- pgTAP cobre existencia da constraint.

PM-02:

- `ux_verified_access_identity_profiles_phone_tenant_hmac` removido.
- `idx_verified_access_identity_profiles_phone_tenant_hmac` criado como indice nao unico.
- Integração cobre dois profiles no mesmo condominio com o mesmo telefone.
- Integração confirma que CPF e documento duplicados continuam falhando com `23505`.
- pgTAP cobre ausencia do indice antigo, existencia do novo e `indisunique = false`.

PM-03:

- `verified_access_validate_service_type_requirement_change()` criada como `security invoker` com `search_path` fixo.
- Trigger `verified_access_service_types_validate_requirement_change` criado em `verified_access_service_types`.
- Integração cobre falha ao mudar `false -> true` com detalhe existente sem descricao, sucesso apos preencher descricao, falha de novo detalhe sem descricao depois da exigencia e bloqueio de `OTHER true -> false`.
- Rollback remove o trigger e a funcao antes das tabelas.

## Artifacts e diagnosticos

- O workflow cria `/tmp/verified-access-supabase-start-sanitized.log`.
- O log bruto `/tmp/verified-access-supabase-start.log` e removido antes de qualquer upload.
- O upload lista paths explicitos e nao usa wildcard que capture o log bruto.
- O artifact bruto anterior do run `29412883145` foi removido via API oficial.
- No run verde `29436074139`, o step `Upload diagnostics` ficou `skipped` porque nao houve falha.

## Features

`VERIFIED_ACCESS` e `VERIFIED_ACCESS_BACKGROUND_CHECK` permanecem desligadas por padrao.

## Status

Gate 1A-REVIEW aprovado no CI em banco descartavel.
Branch permanece em draft PR para revisao humana; nao houve merge.
