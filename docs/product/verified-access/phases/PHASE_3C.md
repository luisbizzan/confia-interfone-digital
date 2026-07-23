# Fase 3C — hardening operacional

## 1. Status

Stage: `Implementada / validada / aguardando revisão`.

A Fase 3C adiciona convergência operacional, retenção de registros não
sensíveis, reconciliação conservadora e processamento local da outbox para a
fundação entregue pelas Fases 3A e 3B.

Esta fase não autoriza rollout, scheduler remoto, migration remota, feature
flag, provider real, tratamento adicional de PII ou integração externa.

## 2. Base e invariantes preservadas

Base incorporada:

- Fases 1A a 1D: domínio local, Rede Confia inerte, state machines, audit,
  outbox e contratos fake;
- Fase 2: requests autenticadas do morador e slots;
- Fase 3A: invitations hash-only e operações autenticadas;
- Fase 3B: sessões públicas hash-only, comandos idempotentes, rate limits,
  submissão protegida e aplicação pública isolada;
- squash da Fase 3B:
  `ec17587d4ba1d7173b97730aa9284a1d94581392`.

Invariantes:

- expiração inline continua sendo a barreira transacional de autorização;
- jobs apenas convergem e limpam estado;
- nenhum token bruto, IP bruto ou PII entra em jobs, findings, logs, audit ou
  outbox;
- RLS permanece default-deny;
- não há grants diretos de tabela para runtime roles;
- não há criação automática de participant ou identity profile;
- falha técnica não gera negativa, network signal ou decisão adversa;
- `persons` e Expo permanecem inalterados;
- features permanecem desligadas.

## 3. Artefatos de banco

Migrations:

```text
supabase/migrations/20260723100000_verified_access_maintenance_foundation.sql
supabase/migrations/20260723101000_verified_access_maintenance_jobs.sql
```

Rollback:

```text
supabase/rollback/verified_access_phase_3c_rollback.sql
```

A fundação cria:

- `verified_access_maintenance_findings`, sem payload livre e sem PII;
- índices parciais para retenção de invitations, public sessions, public
  commands e outbox;
- índice de lease para outbox em `PROCESSING`.

`verified_access_maintenance_findings`:

- possui tenant obrigatório;
- aceita somente aggregate types, finding codes e estados em allowlist;
- usa identidade única `(condominium_id, finding_code, aggregate_id)`;
- é idempotente por upsert;
- possui RLS habilitado e nenhuma policy;
- não concede acesso a `PUBLIC`, `anon`, `authenticated` ou `service_role`.

## 4. Contrato comum dos jobs

Assinatura:

```text
(p_batch_size integer, p_dry_run boolean, p_correlation_id text) returns jsonb
```

Regras:

- `batch_size` obrigatório entre 1 e 500;
- `dry_run` obrigatório;
- correlation ID opcional, sanitizado e limitado;
- `security definer` com `search_path = public, pg_temp`;
- `statement_timeout` local de 20 segundos;
- ordenação determinística;
- `FOR UPDATE SKIP LOCKED` nas seleções mutáveis;
- savepoint implícito por item por bloco PL/pgSQL;
- resposta somente com `job`, `dryRun`, `processed`, `skipped`, `failed` e
  `remaining`;
- `remaining` é contagem limitada, não full scan;
- dry-run não adquire lock de mutação nem grava;
- audit/outbox ocorrem na mesma transação da mudança de domínio quando
  aplicável.

## 5. Jobs autorizados

### 5.1 `verified_access_expire_invitations`

- seleciona somente invitations `PENDING` ou `SENT`;
- exige `expires_at <= now()`;
- muda para `EXPIRED`;
- não expira `OPENED` por inferência;
- o trigger 3B existente revoga sessões dependentes;
- grava audit e outbox deduplicada.

### 5.2 `verified_access_expire_public_sessions`

- seleciona somente public sessions `ACTIVE`;
- muda para `EXPIRED` quando o TTL próprio vence;
- muda para `REVOKED` quando invitation/request pai é inválido;
- nunca reativa estado terminal;
- grava audit e outbox deduplicada.

### 5.3 `verified_access_purge_public_commands`

- remove `COMPLETED` após 30 dias;
- classifica `PROCESSING` com mais de 7 dias como finding;
- exige finding aberto e envelhecido antes de remover comando preso;
- registra audit sanitizada antes do descarte;
- não altera schema nem enfraquece idempotência.

### 5.4 `verified_access_purge_rate_limit_buckets`

- remove buckets somente após `expires_at + 1 hora`;
- nunca usa fingerprint como dimensão de resposta ou log;
- mantém o rate limit transacional da Fase 3B.

### 5.5 `verified_access_reconcile_public_registration_state`

Detecta, de forma limitada:

- invitation completada sem participant;
- slot claimed sem participant;
- session completada sem invitation completada;
- invitation ativa de request cancelada;
- session ativa com pais inválidos;
- command preso;
- outbox pendente ou lease vencido.

O job grava findings idempotentes. A única correção automática adicional é
liberar lease de outbox `PROCESSING` vencido para `FAILED`, com
`LEASE_EXPIRED`. Não cria ou move PII, participant, profile ou identidade.

### 5.6 `verified_access_process_outbox`

- processa somente uma allowlist local de eventos operacionais da Fase 3C;
- não chama rede, provider ou webhook;
- usa claim `PENDING/FAILED -> PROCESSING -> PROCESSED`;
- incrementa tentativa e registra lease;
- em falha, libera lease e agenda retry com código estável;
- eventos sem handler local permanecem intocados.

### 5.7 `verified_access_apply_retention_policy`

Política aprovada para registros não sensíveis:

| Entidade | Janela | Condição |
|---|---:|---|
| public session terminal | 7 dias | sem public command dependente |
| outbox processada | 30 dias | status `PROCESSED` |
| invitation terminal | 90 dias | sem session, public command ou invitation command |

Public commands e rate buckets são tratados por jobs dedicados. Identity
profiles, participants, audit e qualquer PII ficam fora da retenção automática.
O job não depende de efeito `CASCADE`: todas as dependências autorizadas são
verificadas antes do delete.

## 6. Privilégios

Role:

```text
verified_access_phase3c_maintenance_executor NOLOGIN
```

Matriz:

| Recurso | PUBLIC | anon | authenticated | service_role | executor 3C |
|---|---:|---:|---:|---:|---:|
| findings table | nenhum | nenhum | nenhum | nenhum | nenhum direto |
| helpers 3C | nenhum | nenhum | nenhum | nenhum | nenhum |
| sete jobs | nenhum | nenhum | nenhum | herdado pela role | EXECUTE exato |

`service_role` herda a role NOLOGIN. Não recebe grant direto nas tabelas ou
helpers. As assinaturas exatas dos sete jobs são o único caminho runtime.

## 7. Edge Function interna

Endpoint:

```text
verified-access-maintenance-run
```

Contrato:

- somente `POST`;
- autenticação por `x-maintenance-secret`;
- comparação constante do segredo;
- corpo máximo de 4 KiB;
- allowlist exata de `job`, `batchSize` e `dryRun`;
- sete nomes de job mapeados para sete RPCs exatas;
- correlation ID sanitizado;
- timeout de 25 segundos;
- limite interno de 10 chamadas por minuto por isolate;
- resposta RPC validada e reduzida a contadores;
- erros genéricos;
- sem CORS, logs, secrets no cliente ou payload bruto.

A Edge usa a service key apenas no servidor para alcançar a role executora.

## 8. Scheduler

Topologia escolhida:

```text
GitHub Actions manual -> Edge interna -> RPC interna
```

Workflow:

```text
.github/workflows/verified-access-maintenance.yml
```

O workflow contém somente `workflow_dispatch`. Não há `schedule` e nenhuma
agenda remota é habilitada nesta fase. Ele:

- serializa execuções com `cancel-in-progress: false`;
- exige environment protegido `verified-access-maintenance`;
- recebe URL e segredo exclusivamente por secrets;
- valida job e batch;
- usa timeout e retries limitados;
- não imprime URL, segredo ou resposta bruta;
- publica somente contadores sanitizados no step summary.

Frequências futuras sugeridas, ainda não habilitadas:

| Job | Frequência proposta |
|---|---|
| expirar invitations | 5 minutos |
| expirar sessions | 5 minutos |
| processar outbox | 1 minuto |
| reconciliar | 1 hora, inicialmente dry-run |
| limpar rate limits | 1 hora |
| limpar commands | diário |
| retenção | diário, inicialmente dry-run |

## 9. Observabilidade

Permitido:

- nome do job;
- dry-run;
- contadores processed/skipped/failed/remaining;
- correlation ID sanitizado;
- event, finding, status, reason e error codes;
- IDs opacos em audit/outbox.

Proibido:

- token, secret ou credencial;
- nome, telefone, email, documento, nascimento, endereço ou IP bruto;
- ciphertext, HMAC, fingerprint ou payload de usuário;
- body RPC, response upstream ou stack trace;
- aggregate ID como label de métrica.

Alertas futuros devem usar backlog, falhas, idade e duração agregados. Nenhum
serviço externo de métricas é integrado nesta fase.

## 10. Testes e CI

Arquivos:

```text
supabase/tests/verified_access_phase_3c.sql
supabase/tests/verified_access_phase_3c_integration.psql
supabase/tests/verified_access_phase_3c_runtime_roles.psql
.github/workflows/verified-access-phase-3c.yml
```

Cobertura:

- existência, RLS, ausência de policies e grants;
- signatures, `prosecdef`, `search_path` e ACLs;
- input inválido;
- dry-run sem escrita;
- expiração real e idempotência;
- audit/outbox sanitizados;
- processamento local de outbox;
- purge de rate limit;
- findings de reconciliação;
- negação real por role sintética;
- regressões 1A a 3B;
- Edge format, lint, type-check e testes;
- admin-web e aplicação pública;
- rollback, preservação, reaplicação e smoke pós-reaplicação.

Workflows legados 1A, 3A e 3B executam primeiro o rollback 3C. A ordem
cumulativa fica:

```text
3C -> 3B -> 3A -> 2 -> 1C -> 1B -> 1A
```

## 11. Rollback

Ordem explícita:

1. revogar a role 3C de `service_role`;
2. revogar EXECUTE das sete RPCs;
3. remover as sete RPCs;
4. remover helpers;
5. remover a role NOLOGIN;
6. remover índices adicionados;
7. remover `verified_access_maintenance_findings`.

Não usa `CASCADE`, não remove objetos 1A–3B e não reabre estados terminais.

## 12. Runbook

O runbook operacional está em:

[`PHASE_3C_RUNBOOK.md`](../operations/PHASE_3C_RUNBOOK.md).

Ele cobre dry-run, execução manual, interpretação de contadores, backlog,
rollback operacional, rotação de segredo e escalonamento.

## 13. Fora de escopo

- migration, scheduler ou cron remoto;
- feature enablement ou rollout;
- provider, webhook, fila ou mensageria real;
- serviço externo de rate limit;
- PII deletion, anonimização ou alteração de identity profile/participant;
- biometria, OCR, background check, Rede Confia operacional ou decisão
  adversa;
- alteração de `persons`, Expo, admin-web ou aplicação pública;
- Fase 4;
- merge ou mark ready.
