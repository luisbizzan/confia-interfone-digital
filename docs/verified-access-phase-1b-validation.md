# Acesso Verificado - Validacao da Fase 1B

Data: 2026-07-16

## Estado Git

- Branch: `agent/verified-access-phase-1b`.
- Base esperada: `origin/main` em `84077aa18731f83d6e8cfa505b7d10dec2b89026`.
- Commit documental inicial: `0eba533d8e41007ca0e6f300edc316248d0c1c95`.
- Draft PR: `https://github.com/luisbizzan/confia-interfone-digital/pull/3`.
- SHA final validado: `257ec84b23b95a995aaffb335fedd85401599bab`.

## Escopo Implementado

- ADR da fundacao de rede.
- Migrations locais da Fase 1B.
- Sete tabelas centrais de rede.
- Feature flags de rede criadas sempre desligadas.
- RLS default-deny nas tabelas centrais.
- Revogacao explicita de privilegios de `PUBLIC`, `anon`, `authenticated` e `service_role`.
- pgTAP da Fase 1B.
- Integracao SQL da Fase 1B.
- Rollback da Fase 1B.
- Workflow GitHub Actions da Fase 1B.
- Compatibilidade do pgTAP/workflow da Fase 1A para executar em branches que
  tambem contenham a Fase 1B.

## Migrations da Fase 1B

- `supabase/migrations/20260716100000_verified_access_network_foundation.sql`
- `supabase/migrations/20260716101000_verified_access_network_security.sql`

As migrations sao para banco local/descartavel. Nenhuma migration Supabase
remota deve ser executada nesta fase.

## Tabelas Centrais

- `verified_access_network_subjects`
- `verified_access_network_subject_identifiers`
- `verified_access_network_subject_links`
- `verified_access_network_security_cases`
- `verified_access_network_signals`
- `verified_access_network_signal_reviews`
- `verified_access_network_appeals`

## Garantias de Seguranca

- Nenhuma coluna central de CPF, telefone, e-mail, nome, face, biometria,
  plaintext ou ciphertext foi criada.
- Telefone nao e identificador de rede.
- Sinais nao permitem `AUTO_DENY_NETWORK`, `GLOBAL_DENIED` ou
  `PERMANENT_BLACKLIST`.
- Nenhuma funcao SQL HMAC foi criada.
- Nenhum trigger operacional, view, RPC ou policy RLS foi criado.
- `service_role` nao recebeu privilegio direto nas tabelas centrais.

## Validacoes

Esta secao deve ser atualizada somente com resultados efetivamente executados.

| Validacao | Resultado | Evidencia |
|---|---|---|
| Preflight Git | Passou | Branch limpa em `0eba533`; `origin/main` ancestral em `84077aa` |
| Historico remoto Supabase | Passou | Phase 1A sem Remote em `npx supabase migration list` |
| Migrations descartaveis | Passou no CI | `npx supabase db reset`, run `29510636615` |
| pgTAP Phase 1A/1B | Passou no CI | `Run pgTAP database tests`, run `29510636615` |
| Integracao Phase 1A/1B | Passou no CI | `Run integration SQL scenarios`, run `29510636615` |
| Role checks | Passou no CI | `Run runtime role permission checks`, run `29510636615` |
| DB lint | Passou no CI | `Run Supabase database lint`, run `29510636615` |
| Rollback 1B | Passou no CI | `Roll back Phase 1B objects`, run `29510636615` |
| Preservacao 1A apos rollback | Passou no CI | `Verify rollback scope`, run `29510636615` |
| Reaplicacao | Passou no CI | `Reapply migrations`, run `29510636615` |
| Smoke pos-reaplicacao | Passou no CI | pgTAP e integracao pos-reaplicacao, run `29510636615` |
| `npm run admin:lint` | Passou | ESLint sem erros apos `npm ci` |
| `npm run admin:build` | Passou | Next build concluido apos `npm ci` |
| CI Phase 1B | Passou | `database = success`, `admin-web = success`, run `29510636615` |
| CI Phase 1A legado | Passou | `database = success`, `admin-web = success`, run `29510636495` |
| Vercel | Passou | Status GitHub `Vercel = success`, target `https://vercel.com/confia-interfone-s-projects/confia-interfone-digital-admin-web/3tsL7tszYrtg9NQT8EbRT81sKzkN` |

## CI Verde

- Workflow principal: `Verified Access Phase 1B`.
- Run: `29510636615`.
- URL: `https://github.com/luisbizzan/confia-interfone-digital/actions/runs/29510636615`.
- SHA: `257ec84b23b95a995aaffb335fedd85401599bab`.

### Job `database`

| Step | Resultado |
|---|---|
| Start Supabase local stack | success |
| Apply migrations from scratch | success |
| Run pgTAP database tests | success |
| Run integration SQL scenarios | success |
| Run runtime role permission checks | success |
| Run Supabase database lint | success |
| Create rollback sentinel | success |
| Roll back Phase 1B objects | success |
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

## Ciclos de CI

- Ciclo 1: run `29509931404` falhou no pgTAP porque o teste 1A ainda exigia
  ausencia das tabelas centrais depois da aplicacao da Fase 1B.
- Ciclo 2: run `29510259086` da Fase 1B passou; o workflow legado 1A
  `29510259602` falhou porque tentava rollback 1A antes de remover FKs da 1B.
- Ciclo 3: runs `29510636615` e `29510636495` passaram.

## Vercel

- Status GitHub: `success`.
- Target: `https://vercel.com/confia-interfone-s-projects/confia-interfone-digital-admin-web/3tsL7tszYrtg9NQT8EbRT81sKzkN`.
- Ambiente identificado: Preview, associado ao check Vercel do PR/head branch
  `agent/verified-access-phase-1b`. A API publica de deployments do GitHub nao
  retornou um deployment separado com campo `environment`, e a API Vercel exige
  token para detalhes internos do deployment.

## Rollback

Rollback dedicado:

- `supabase/rollback/20260716100000_verified_access_phase_1b_rollback.sql`

O rollback remove apenas as sete tabelas centrais e as tres flags de rede
criadas desligadas. Ele nao remove objetos da Fase 1A, `persons`, `INTERCOM`,
`VERIFIED_ACCESS` ou `VERIFIED_ACCESS_BACKGROUND_CHECK`.

## Fora de Escopo Confirmado

- Nenhuma implementacao da Fase 1C ou 1D.
- Nenhuma alteracao no app Expo.
- Nenhuma alteracao na tabela `persons`.
- Nenhuma feature flag habilitada.
- Nenhum deploy manual.
- Nenhuma migration remota.
