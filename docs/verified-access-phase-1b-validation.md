# Acesso Verificado - Validacao da Fase 1B

Data: 2026-07-16

## Estado Git

- Branch: `agent/verified-access-phase-1b`.
- Base esperada: `origin/main` em `84077aa18731f83d6e8cfa505b7d10dec2b89026`.
- Commit documental inicial: `0eba533d8e41007ca0e6f300edc316248d0c1c95`.
- Draft PR: a registrar depois do push da Fase 1B.

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
| Migrations descartaveis | Bloqueado localmente | Docker/Supabase local indisponivel nesta sessao Windows |
| pgTAP Phase 1A/1B | Bloqueado localmente | Docker/Supabase local indisponivel nesta sessao Windows |
| Integracao Phase 1A/1B | Bloqueado localmente | Docker/Supabase local indisponivel nesta sessao Windows |
| Role checks | Bloqueado localmente | Docker/Supabase local indisponivel nesta sessao Windows |
| DB lint | Bloqueado localmente | Docker/Supabase local indisponivel nesta sessao Windows |
| Rollback 1B | Bloqueado localmente | Docker/Supabase local indisponivel nesta sessao Windows |
| Preservacao 1A apos rollback | Bloqueado localmente | Docker/Supabase local indisponivel nesta sessao Windows |
| Reaplicacao | Bloqueado localmente | Docker/Supabase local indisponivel nesta sessao Windows |
| Smoke pos-reaplicacao | Bloqueado localmente | Docker/Supabase local indisponivel nesta sessao Windows |
| `npm run admin:lint` | Passou | ESLint sem erros apos `npm ci` |
| `npm run admin:build` | Passou | Next build concluido apos `npm ci` |
| CI | Pendente | A executar |

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
