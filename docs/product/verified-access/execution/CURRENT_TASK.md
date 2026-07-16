# CURRENT TASK — VA-1B-FOUNDATION

## 1. Autorização

Executar somente a fundação inerte da Rede Confia descrita em:

```text
docs/product/verified-access/phases/PHASE_1B.md
```

Branch:

```text
agent/verified-access-phase-1b
```

Worktree:

```text
C:\Projetos\Confia\repo-github-phase-1b
```

Base mínima:

```text
origin/main
84077aa18731f83d6e8cfa505b7d10dec2b89026
```

A branch pode conter o commit de bootstrap documental. Ela não pode conter implementação anterior da Fase 1B.

## 2. Preflight

Antes de editar:

```powershell
cd C:\Projetos\Confia\repo-github-phase-1b

git fetch origin --prune
git branch --show-current
git status --short
git log --oneline --decorate -10
git rev-parse HEAD
git rev-parse origin/main
git diff --check
```

Leia:

1. `AGENTS.md`
2. `docs/product/verified-access/README.md`
3. `docs/product/verified-access/DECISIONS.md`
4. `docs/product/verified-access/ROADMAP.md`
5. `docs/product/verified-access/phases/PHASE_1B.md`
6. este arquivo
7. `docs/product/verified-access/SECURITY_AND_PRIVACY.md`

Antes da edição, apresente:

- estado Git;
- migrations planejadas;
- tabelas;
- constraints;
- RLS/grants;
- testes;
- workflow;
- rollback;
- riscos.

Depois prossiga sem nova confirmação, salvo risco de perda de dados ou migration já aplicada.

## 3. Entregas

### 3.1 ADR

Criar:

```text
docs/adr/20260716-verified-access-network-foundation.md
```

### 3.2 Features

Adicionar desligadas:

```text
VERIFIED_ACCESS_NETWORK_IDENTITY
VERIFIED_ACCESS_NETWORK_SIGNALS
VERIFIED_ACCESS_NETWORK_HOLD
```

### 3.3 Schema

Criar somente:

```text
verified_access_network_subjects
verified_access_network_subject_identifiers
verified_access_network_subject_links
verified_access_network_security_cases
verified_access_network_signals
verified_access_network_signal_reviews
verified_access_network_appeals
```

### 3.4 Segurança

- RLS em todas.
- Revogar `PUBLIC`, `anon`, `authenticated` e `service_role`.
- Nenhuma policy.
- Nenhuma view.
- Nenhuma RPC.
- Nenhuma função de HMAC.
- Nenhum trigger nas tabelas locais que crie case/signal.
- Nenhuma coluna PII.

### 3.5 Testes

Criar:

```text
supabase/tests/verified_access_phase_1b.sql
supabase/tests/verified_access_phase_1b_integration.psql
```

Cobrir integralmente o plano da fase.

### 3.6 Rollback

Criar rollback da Fase 1B que preserve toda a Fase 1A e estruturas legadas.

### 3.7 CI

Criar:

```text
.github/workflows/verified-access-phase-1b.yml
```

Validar migrations, pgTAP, integração, papéis, lint, rollback, reaplicação e smoke.

Não enfraquecer a validação da Fase 1A.

## 4. Proibições

Não implementar:

- HMAC real;
- Edge Function;
- API;
- busca;
- criação operacional de caso/sinal;
- ativação;
- avaliação de participante;
- credencial hold;
- UI;
- providers;
- Fase 1C;
- Fase 1D.

Não executar migration remota.

Não habilitar feature.

Não alterar `persons` ou o app Expo.

## 5. Git e PR

- usar paths explícitos no stage;
- commits compreensíveis;
- push para `agent/verified-access-phase-1b`;
- atualizar/abrir draft PR;
- não marcar pronto;
- não fazer merge.

## 6. Condições de parada

Parar se:

- base divergir sem análise;
- migration da 1A precisar ser alterada;
- houver PII central;
- houver grant central;
- houver propagação automática;
- CI não executar rollback;
- migration remota tiver sido aplicada;
- arquivo não relacionado entrar.

## 7. Relatório final

Informar:

- branch e SHAs;
- commits;
- arquivos;
- migrations;
- tabelas/constraints/índices;
- RLS/grants;
- testes;
- CI;
- rollback/reaplicação;
- diferenças do plano;
- blockers;
- PR;
- confirmações de nenhuma migration remota, nenhuma feature habilitada e nenhuma operação de rede.
