# Acesso Verificado - Validacao da Fase 1A-H

Data: 2026-07-15

## Estado Git

- Base: `origin/main` em `8a4ff78`.
- SHA inicial da sprint: `d8609ee7d50e7c431ff433afdd54bbe4d8c44ecf`.
- SHA final de codigo/CI observado: `e5d7f3277cff15dc4dffac859c1839d388df9616`.
- Branch: `agent/verified-access-phase-1a-r`.

## Migrations da Fase 1A

- `supabase/migrations/20260714100000_verified_access_local_foundation.sql`
- `supabase/migrations/20260714101000_verified_access_local_security.sql`

As duas migrations aparecem como pendentes no historico remoto sanitizado. Por isso foram corrigidas diretamente nesta branch.

## Gaps corrigidos

- Removida funcao cross-table em `CHECK` para `OTHER`.
- Adicionados triggers `security invoker` com `search_path` fixo.
- Adicionadas FKs compostas para request/policy/version, participant/slot/request e evaluation/participant/request.
- Adicionada validacao de detalhe somente para `SERVICE_PROVIDER`.
- Adicionada validacao de capacidade de slot por `participant_limit`.
- Revisada semantica de `claimed_at`.
- Corrigido rollback para remover indices auxiliares da Fase 1A.
- Outbox tornou-se parcialmente imutavel.
- Auditoria bloqueia update, delete e truncate.
- Grants de `service_role` foram minimizados.
- JSON de audit/outbox/evaluation/policy limitado a objeto quando aplicavel.
- Policy V2 reconciliada com campos separados para visitante e prestador.
- Identity profile minimizado para HMAC local de CPF, documento e telefone.
- Request/evaluation reconciliados com campos de expiracao, ator e snapshot sanitizado.
- Campos livres receberam limites e comentarios de finalidade.

## Gaps adiados

- State machines completas, RPCs de policy, providers, convites, QR, credenciais e UI pertencem a fases posteriores.
- Sanitizacao JSON por blacklist permanece defesa em profundidade, nao detector universal de PII.
- Criptografia/HMAC reais permanecem fora do banco e serao implementados em camada aprovada posterior.

## Migration drift

Ver `docs/verified-access-phase-1a-repository-drift.md`.

Quatro migrations antigas estao aplicadas no remoto e presentes como untracked na checkout original, mas ausentes de `origin/main`. Elas nao pertencem a Fase 1A e nao foram incluidas nesta branch.

## Testes locais

| Comando | Resultado | Evidencia |
|---|---|---|
| `npm ci` | Passou | Instalou 425 pacotes; `npm audit` reportou 6 vulnerabilidades existentes |
| `npm run admin:lint` | Passou | ESLint sem erros |
| `npm run admin:build` | Passou | Next build concluido |
| `npx supabase db push --dry-run` na worktree | Bloqueado | Worktree isolada nao possui link Supabase local nao versionado |
| `npx supabase start` | Bloqueado | Docker Desktop/daemon indisponivel na sessao Windows |
| `npx supabase db reset` | Bloqueado | Docker indisponivel |
| `npx supabase test db` | Bloqueado localmente | Postgres local `127.0.0.1:54322` indisponivel |
| `npx supabase db lint` | Bloqueado localmente | Postgres local `127.0.0.1:54322` indisponivel |

Na checkout original, somente leitura, `npx supabase db push --dry-run` passou e listou apenas as duas migrations da Fase 1A como pendentes. Nenhuma migration remota foi executada.

## CI

- Workflow: `.github/workflows/verified-access-phase-1a.yml`.
- Run 1: `29384878087`, falhou em `Run integration SQL scenarios`.
- Run 2: `29385091735`, falhou em `Run integration SQL scenarios`.
- Run 3: `29385340268`, falhou em `Run integration SQL scenarios`.
- Run 4: `29385544909`, falhou em `Start Supabase local stack`.

Nos runs 1, 2 e 3:

- `Start Supabase local stack`: passou;
- `Apply migrations from scratch`: passou;
- `Run pgTAP database tests`: passou;
- `Run integration SQL scenarios`: falhou.

Sem autenticacao para logs completos, a API publica retornou apenas annotations genericas de exit code. O workflow foi ajustado para tentar expor o tail do `psql`, mas o limite de tres ciclos de correcao de CI foi atingido antes de um run verde.

Conclusao: CI vermelho. A branch nao esta aprovada para merge.

## Rollback

Rollback definido em `supabase/rollback/20260714100000_verified_access_phase_1a_rollback.sql`.

Validacao real em banco descartavel foi iniciada no GitHub Actions. Migrations e pgTAP passaram nos runs 1, 2 e 3; o teste de integracao psql e o rollback/reaplicacao ainda nao passaram.

O workflow verifica:

- remocao dos objetos `verified_access_%`;
- remocao de `ux_units_id_condominium_id`;
- remocao de `ux_user_profiles_id_condominium_id`;
- preservacao de `public.persons`;
- preservacao do papel `INTERCOM`;
- reaplicacao das migrations por `supabase db reset`;
- smoke tests apos reaplicacao.

## Features

`VERIFIED_ACCESS` e `VERIFIED_ACCESS_BACKGROUND_CHECK` permanecem desligadas por padrao.

## Blockers de merge

- CI vermelho.
- Teste de integracao psql ainda falha no GitHub Actions.
- Rollback e reaplicacao nao foram executados ate o fim no CI porque os runs pararam antes desses steps.
- Logs completos do GitHub Actions exigem autenticacao indisponivel nesta execucao; API publica retornou apenas annotations genericas.

A branch nao deve ser considerada aprovada para merge enquanto o GitHub Actions nao concluir verde em banco descartavel.
