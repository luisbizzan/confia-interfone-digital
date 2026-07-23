# Fase 3C — hardening e prontidão para rollout

## 1. Status e autoridade

Stage: `Planejada / em revisão / não autorizada`.

Este documento é um contrato técnico proposto para revisão humana. Ele não
autoriza migration, RPC, Edge Function, job, worker, cron, scheduler, UI,
provider, teste técnico, rollout ou alteração de infraestrutura.

`execution/CURRENT_TASK.md` permanece:

```text
# CURRENT TASK — NO ACTIVE IMPLEMENTATION
```

Uma implementação futura exige novo contrato versionado, allowlist fechada,
base SHA, migrations, rollback, testes e gates explicitamente autorizados.

## 2. Objetivo

Planejar o hardening do fluxo público entregue nas Fases 3A e 3B:

- materializar expirações sem depender de tráfego;
- revogar sessões dependentes;
- limpar estado operacional efêmero;
- reconciliar invariantes de invitation, session, slot e participant;
- processar a outbox com retry e idempotência;
- aplicar retenção aprovada sem apagar evidência obrigatória;
- evoluir rate limiting para operação distribuída;
- adicionar observabilidade, alertas e runbooks sem PII;
- definir rollout controlado;
- preparar um handoff seguro e explícito para a Fase 4.

Expiração continua sendo validada no caminho transacional. Jobs futuros são
mecanismo de convergência e limpeza, nunca a única barreira de autorização.

## 3. Dependências e inventário real

### 3.1 Dependências incorporadas

- Fase 1A: schema local, policy, participant, identity profile, audit e outbox.
- Fase 1B: fundação inerte da Rede Confia, ainda default-deny.
- Fase 1C: state machines, policy RPCs e helpers internos de audit/outbox.
- Fase 1D: contratos normalizados e providers fake determinísticos.
- Fase 2: requests do morador e slots.
- Fase 3A: invitations hash-only e mensageria fake.
- Fase 3B: sessões públicas hash-only, comandos, rate buckets, submissão
  protegida e aplicação pública isolada.

Fase 3B está incorporada à `main` pelo squash commit
`ec17587d4ba1d7173b97730aa9284a1d94581392`.

### 3.2 Objetos reutilizados

- `verified_access_invitations`, com índice parcial por expiração;
- `verified_access_public_sessions`, com índice parcial de `ACTIVE` por
  `expires_at`;
- `verified_access_public_registration_commands`;
- `verified_access_public_rate_limits`, com índice por `expires_at`;
- `verified_access_requests`, slots, participants e identity profiles;
- `verified_access_audit_events`, append-only;
- `verified_access_outbox_events`, com deduplication key, tentativas,
  `locked_at`, `locked_by`, `next_attempt_at` e índice de pendências;
- helpers sanitizados de audit/outbox;
- Edge Functions e shared modules das Fases 3A/3B;
- `apps/verified-access-public`;
- providers fake da Fase 1D.

### 3.3 Padrões reais aplicáveis

- PostgreSQL 17 local via Supabase CLI.
- RLS default-deny e grants em assinaturas exatas.
- Funções de domínio transacionais com `search_path` fixo.
- `FOR UPDATE SKIP LOCKED` já é usado pelo lifecycle de chamadas.
- O projeto não configura `pg_cron`.
- O scheduler existente é GitHub Actions chamando Edge Function protegida por
  segredo, que chama uma RPC.
- Não existe worker do outbox do Acesso Verificado.
- O workflow 1A já valida rollback cumulativo
  `3B -> 3A -> 2 -> 1C -> 1B -> 1A`.

O scheduler de chamadas é referência de topologia, não implementação a copiar
sem revisão. O futuro scheduler do Acesso Verificado deve ter origem
configurável, CORS não aplicável ou restrito, resposta sanitizada, segredo
rotacionável, proteção contra replay e executor de privilégio mínimo.

## 4. Escopo

Planejar:

1. expiração automática de invitations;
2. expiração automática de public sessions;
3. revogação de sessões dependentes;
4. limpeza de comandos idempotentes antigos;
5. limpeza de rate-limit buckets;
6. remoção de cadastros incompletos;
7. retenção, exclusão ou anonimização aprovada;
8. reconciliação conservadora de estados;
9. recuperação e processamento de outbox;
10. métricas e alertas sem PII;
11. proteção adicional contra abuso;
12. runbooks;
13. rollout controlado futuro;
14. handoff técnico para a Fase 4.

## 5. Fora de escopo

- prova de vida, selfie, vídeo, biometria ou face match;
- OCR, upload ou imagem de documento;
- `IdentityProvider` real ou qualquer provider externo;
- background check;
- credencial, QR Code, check-in, check-out ou portaria;
- app mobile ou Expo;
- Rede Confia operacional;
- mensageria real;
- alteração de `persons`;
- habilitação de feature;
- migration remota;
- deploy ou rollout de produção;
- decisão automática adversa;
- implementação dos jobs descritos neste documento.

## 6. Decisões propostas

### 6.1 Expiração

- Invitation `PENDING` ou `SENT` passa para `EXPIRED` quando
  `expires_at <= clock_timestamp()`.
- Invitation `OPENED` também deve expirar quando vencer sem submissão, pois
  continua sendo um convite ativo no contrato 3B.
- Public session `ACTIVE` passa para `EXPIRED` quando
  `expires_at <= clock_timestamp()`.
- Invitation expirada ou revogada muda sessões `ACTIVE` relacionadas para
  `REVOKED` na mesma transação, com reason code que distingue a causa. O estado
  `EXPIRED` da session fica reservado ao vencimento do próprio `expires_at`.
- Session `COMPLETED`, `REVOKED` ou `EXPIRED` nunca volta a `ACTIVE`.
- Invitation `COMPLETED`, `REVOKED` ou `EXPIRED` nunca é reaberta por job.
- Cada execução usa batch limitado, lock de linha e cursor estável.
- Execuções concorrentes devem produzir o mesmo estado e os mesmos eventos
  lógicos, sem duplicação.
- Índices parciais por estado e expiração são obrigatórios; full scan de
  tabelas operacionais não é aceitável.

### 6.2 Cadastros incompletos

- A Fase 3B não persiste PII de rascunho.
- Session iniciada sem submit pode ser removida após expiração e retenção.
- Command `START` antigo pode ser removido conforme a política operacional.
- Não deve existir participant ou identity profile parcial: ambos nascem no
  submit atômico.
- Qualquer participant/profile parcial encontrado é inconsistência, não
  rascunho válido.
- Correção que toque PII, identity profile ou vínculo civil exige revisão
  manual; o job não inventa, move ou recria identidade.

### 6.3 Falha técnica

- Erro, timeout, atraso de scheduler ou falha de outbox não nega acesso.
- Job interrompido deixa linhas elegíveis para nova tentativa.
- Falha parcial não confirma o cursor além da última unidade concluída.
- Limite de retries esgotado gera alerta e estado técnico explícito; não gera
  case, signal ou negativa automática.

## 7. Modelo operacional dos jobs

Regras comuns:

- entrada estruturada: `batch_size`, `cursor`, `dry_run`, `run_id` e
  `time_budget_ms`;
- `batch_size` validado entre 1 e limite específico;
- cursor opaco composto pelo campo indexado e PK, nunca offset;
- seleção com `FOR UPDATE SKIP LOCKED` quando houver mutação;
- lock advisory por nome do job apenas para tarefas globais incompatíveis;
- nenhuma transação deve abranger chamada de rede;
- idempotência por estado atual e deduplication key;
- timeout por execução e por batch;
- retry externo com backoff e jitter; uma chamada executa uma tentativa;
- retorno apenas com contadores, reason codes, cursor e duração;
- `dry_run` não adquire lock de mutação, não escreve audit/outbox e não
  promete estabilidade diante de concorrência;
- logs, métricas, audit e outbox usam allowlist;
- limites por execução impedem resource exhaustion;
- rollback operacional significa parar o scheduler e reaplicar a versão
  anterior; alterações de domínio já confirmadas não são reabertas.

### 7.1 Matriz dos jobs

| Job | Input e batch | Lock e cursor | Retry/timeout/falha parcial | Audit/outbox e observabilidade | Dry-run, rollback e limite |
|---|---|---|---|---|---|
| `expire_invitations` | cutoff server-side; padrão 200, máximo 1000 | linhas `PENDING`, `SENT` ou `OPENED` por `(expires_at,id)` com `SKIP LOCKED` | retry do batch; 20 s; commit por batch | um evento deduplicado por invitation; contagem por estado, lag e duração | lista somente contadores; parar scheduler; máximo 5 batches/run |
| `expire_public_sessions` | cutoff server-side; padrão 500, máximo 2000 | `ACTIVE` por `(expires_at,id)` com `SKIP LOCKED` | retry seguro; 15 s; commit por batch | evento somente quando a transição é materializada; expiradas e lag | dry-run agregado; rollback não reativa terminal; máximo 5 batches/run |
| `purge_public_commands` | cutoff derivado da policy; padrão 500, máximo 2000 | por `(completed_at,id)` e `(created_at,id)`; `SKIP LOCKED` | retry de delete; 20 s; falha não avança cursor | somente contagem por tipo/status/idade; sem result payload | dry-run conta elegíveis; desabilitar purge; máximo 2500/run |
| `purge_rate_limit_buckets` | `expires_at + margin <= now`; padrão 2000, máximo 10000 | por `(expires_at,id)`; `SKIP LOCKED` | retry; 15 s; batches independentes | buckets removidos, idade máxima e duração; sem fingerprint como dimensão | dry-run agregado; máximo 10000/run |
| `reconcile_public_registration_state` | janela temporal e escopo opcional de tenant técnico; padrão 100, máximo 500 | advisory lock por shard + locks de domínio em ordem session, invitation, request, slot, participant | sem retry interno; 30 s; cada aggregate em savepoint/transação própria | finding/correction code, IDs e contadores; achados sensíveis vão a revisão | dry-run obrigatório antes de modo write; modo write allowlisted; máximo 500/run |
| `process_verified_access_outbox` | `next_attempt_at <= now`; padrão 100, máximo 500 | claim `PENDING/FAILED` com `SKIP LOCKED`, lease em `locked_at/locked_by`, cursor `(next_attempt_at,created_at,id)` | uma tentativa por evento; timeout por handler; backoff+jitter; lease recuperável | tentativa, latência, event type, status e error code; nunca payload em log | dry-run só backlog; kill switch; máximo 500/run e concorrência configurável |
| `apply_retention_policy` | policy version aprovada, entity type, cutoff, dry-run obrigatório; padrão 100, máximo 500 | advisory lock por tenant/entity + cursor `(retention_until,id)` | sem retry interno; 30 s; falha preserva dado | prova de descarte sanitizada e imutável, contagem e policy version | duas etapas preview/execute; kill switch; máximo 500/run |

### 7.2 Ordem e frequência propostas

| Job | Frequência inicial proposta | Dependência |
|---|---|---|
| `expire_public_sessions` | a cada 5 minutos | nenhuma; autorização continua validando TTL inline |
| `expire_invitations` | a cada 5 minutos | expira/revoga sessões na mesma transação |
| `purge_rate_limit_buckets` | a cada hora | margem de retenção aprovada |
| `process_verified_access_outbox` | a cada minuto | handlers fake/internos autorizados |
| `reconcile_public_registration_state` | a cada hora, inicialmente dry-run | alertas e runbook aprovados |
| `purge_public_commands` | diário | política de retenção aprovada |
| `apply_retention_policy` | diário, inicialmente dry-run | jurídico/DPO e policy versionada |

Frequências são propostas. Nenhum scheduler é habilitado por este documento.

## 8. Scheduler

### 8.1 Opções avaliadas

| Opção | Aderência atual | Pontos fortes | Limitações |
|---|---|---|---|
| GitHub Actions -> Edge -> RPC | padrão já existente | baixo custo inicial, auditável no repositório, execução manual | atraso de cron, dependência externa, segredo e URL, não ideal para alta frequência |
| Scheduled Edge Function | compatível com Supabase, não existente no repo | borda próxima, controle de timeout | backend de agenda ainda precisa ser escolhido; secrets e retries |
| `pg_cron` | não configurado | atomicidade e baixa latência próximas ao banco | extensão/produção não validadas, risco de privilégio e operação |
| scheduler gerenciado externo | inexistente | SLA, retry e alertas maduros | custo, integração, segredo e nova dependência |
| execução manual controlada | sempre disponível como contingência | simples, adequada a dry-run/runbook | não garante prazo nem escala |

### 8.2 Recomendação

Recomendação primária para o primeiro gate local/staging: reutilizar a topologia
existente `GitHub Actions -> Edge Function de scheduler -> RPC interna`, com:

- URL por secret/configuração, nunca hard-coded no novo workflow;
- segredo dedicado e rotacionável;
- método `POST`, sem CORS público;
- timestamp/nonce ou assinatura para reduzir replay;
- Edge sem regra de domínio e sem payload livre;
- role executor NOLOGIN com `EXECUTE` somente nas assinaturas autorizadas;
- nenhuma tabela exposta ao scheduler;
- timeout, concurrency group e resposta sanitizada;
- workflow sem imprimir secret, URL sensível ou corpo bruto;
- `workflow_dispatch` para dry-run controlado;
- alertas quando cron atrasar ou falhar repetidamente.

Alternativa preferida para escala futura: scheduler gerenciado ou mecanismo
Supabase oficialmente suportado, mantendo as mesmas RPCs idempotentes. A
escolha depende de SLA, custo, disponibilidade regional e aprovação de
infraestrutura. `pg_cron` não deve ser assumido disponível.

Modo manual controlado é o fallback obrigatório. Expiração inline permanece
fail-closed mesmo se todo scheduler estiver indisponível.

## 9. Retenção proposta

| Entidade | Prazo/evento proposto | Ação | Estado |
|---|---|---|---|
| public session terminal | 7 dias após terminal/expiração | delete físico após comandos dependentes elegíveis | proposta |
| rate-limit bucket | janela + margem operacional | delete físico | proposta; margem a aprovar |
| command concluído | 30 dias após `completed_at` | delete físico depois de preservar evidência necessária | proposta |
| command preso/incompleto | 7 dias após `created_at` | classificar/reconciliar antes de delete | proposta |
| invitation expirada/revogada | 90 dias após terminal | delete/anonimização de metadata operacional | sujeito a jurídico |
| invitation completada | ligada à retenção da request/participant | não apagar isoladamente se quebrar evidência | blocker |
| audit | longa, por compliance e finalidade | append-only; eventual archive controlado | blocker jurídico/compliance |
| outbox processada | 30 a 90 dias após processamento | archive/delete preservando dedupe exigida | proposta sujeita a operação |
| outbox falha/descartada | até resolução e prazo aprovado | preservar para incidente/runbook | blocker operacional |
| identity profile submetido | evento e prazo ainda não definidos | anonimizar/excluir conforme decisão aprovada | blocker jurídico/DPO |
| participant submetido | alinhado a profile/request | anonimizar ou excluir preservando integridade | blocker |
| request concluída/cancelada/expirada | policy do tenant + obrigação legal | minimizar textos e relações conforme policy | blocker |
| PII de request cancelada | não inferido | nenhuma exclusão automática sem regra aprovada | blocker jurídico/DPO |
| PII de rascunho | não existe na 3B | nenhuma ação | invariante |
| biometria futura | fora da Fase 3C | nenhuma decisão | fora de escopo |

Regras:

- prazo é derivado de policy versionada, não hard-coded no worker;
- retenção por tenant não pode reduzir obrigação legal mínima;
- legal hold bloqueia exclusão;
- anonimização deve ser irreversível e definida campo a campo;
- ciphertext e HMAC exigem decisões separadas; apagar ciphertext e manter HMAC
  ainda é tratamento de dado pseudonimizado;
- FKs e evidência de audit/outbox devem ser verificadas antes de delete;
- backups e réplicas precisam de ciclo documentado;
- toda execução de retenção exige preview, policy version e prova de descarte;
- nenhuma regra definitiva para PII é aprovada por este plano.

## 10. Rate limiting distribuído

O Postgres atual continua como defesa local transacional até substituição
aprovada. O desenho futuro deve avaliar:

| Opção | Atomicidade | Latência/escala | Tenant e pseudonimização | Disponibilidade/falha | Custo/consistência |
|---|---|---|---|---|---|
| PostgreSQL | forte por instância | adiciona carga ao banco | HMAC efêmero já modelado | indisponibilidade do DB bloqueia fluxo | baixo custo incremental; região única |
| Redis | comandos atômicos/Lua | baixa latência e alto throughput | prefixos por ambiente/tenant; chave HMAC | exige política fail-closed/fail-open por endpoint | custo novo; replicação pode ser eventual |
| serviço gerenciado | depende do contrato | escala e operação terceirizada | precisa garantir residência e retenção | SLA e fallback contratuais | custo e vendor lock-in |
| Edge-native | forte no escopo do produto escolhido | próximo do cliente | cuidado com IP/proxy e isolamento | partitions e limites do fornecedor | consistência cross-region variável |
| proxy/CDN | bom para IP e volumetria | bloqueio antes da aplicação | não substitui limite por session/invitation | protege origem, mas pode falsear IP | custo e regras por PoP |

Proposta em camadas:

1. proxy/CDN para volumetria por IP/rede, depois de domínio aprovado;
2. backend distribuído para chaves pseudonimizadas por endpoint;
3. Postgres transacional para limites ligados a invitation, session,
   idempotency e documento por tenant.

Requisitos:

- IP vem somente de cadeia de proxy confiável; headers do cliente são ignorados;
- fingerprint usa chave exclusiva, versionada e fora do banco;
- IP bruto nunca é persistido;
- IPv4/IPv6 e NAT têm política explícita;
- cardinalidade máxima e TTL são obrigatórios;
- falha do backend: exchange e submit falham tecnicamente fechados; leitura de
  status pode usar orçamento degradado curto, sem revelar existência;
- fallback nunca elimina o limite transacional do Postgres;
- resposta é genérica com `429` e `Retry-After`;
- métricas não incluem fingerprint;
- consistência cross-region e propagação de bloqueios devem ser testadas;
- não há integração externa autorizada nesta fase.

## 11. Observabilidade e alertas

### 11.1 Allowlist de métricas

- invitations emitidas, abertas, concluídas, revogadas e expiradas;
- sessions criadas, concluídas, revogadas e expiradas;
- registrations iniciadas e submetidas;
- taxa de abandono por janela agregada;
- rate limits acionados por scope e endpoint;
- erros por código estável;
- commands `PROCESSING`, concluídos e conflitos;
- idade do command preso mais antigo;
- outbox pendente/falha, idade e tentativas;
- tempo de submissão em buckets;
- falhas de transação por código;
- inconsistências detectadas, corrigidas e enviadas a revisão;
- duração, batch, retries, lag e resultado de cada job;
- atraso e falha do scheduler.

Dimensões permitidas: ambiente, job, endpoint, event/status/reason code,
provider fake code, faixa de latência e tenant pseudonimizado somente se
aprovado. Cardinalidade deve ser limitada.

Proibidos: nome, documento, nascimento, telefone, token, hash de token,
ciphertext, HMAC/fingerprint, IP bruto, body, cookie, Authorization, URL com
segredo e texto livre.

### 11.2 Alertas mínimos

- scheduler sem execução dentro de duas janelas;
- job falhando repetidamente;
- invitation/session expiration lag acima do SLO;
- command `PROCESSING` além do timeout;
- outbox acima de idade ou volume;
- taxa anormal de `429`, token inválido ou conflito;
- aumento de erro transacional;
- reconciliação encontra invariante crítica;
- falha de revogação;
- tentativa de cross-tenant;
- suspeita de secret ou PII em log;
- retenção atrasada ou legal hold ignorado.

Alertas apontam para runbook e IDs técnicos, nunca para PII.

## 12. Reconciliação

### 12.1 Matriz de findings

| Finding | Detecção | Correção automática permitida |
|---|---|---|
| invitation `COMPLETED` sem participant | ausência de participant no slot/request | nenhuma; revisão manual e incidente |
| participant sem slot válido | FK ausente ou vínculo incompatível | nenhuma; revisão manual |
| slot `CLAIMED` sem participant | ausência de participant único | nenhuma; revisão manual |
| session `COMPLETED` sem invitation `COMPLETED` | mesmos invitation/request/tenant | promover invitation somente se participant + slot + profile e timestamps provarem submit atômico; caso contrário, manual |
| invitation ativa com request `CANCELLED` | `PENDING/SENT/OPENED` ligada a cancelada | revogar invitation e sessions ativas, com evento deduplicado |
| session `ACTIVE` com invitation `REVOKED/EXPIRED` | vínculo direto | mudar session para `REVOKED`, preservando reason code da invitation |
| command `PROCESSING` preso | idade maior que timeout, sem transação ativa | marcar finding; repetir lógica somente pela idempotency key; delete após 7 dias exige aprovação |
| outbox pendente por tempo excessivo | `next_attempt_at`, status, attempts e lease | liberar lease vencido e reprogramar com backoff; nunca duplicar evento |

### 12.2 Regras de segurança

- reconciliação roda primeiro em `dry_run`;
- locks seguem ordem estável para não competir com submit/cancel;
- correção não pode reabrir estado terminal;
- correção não cria participant, profile ou identificador;
- correção não descriptografa nem move PII;
- dúvida sobre identidade, PII ou evidência gera revisão manual;
- cada correção automática possui código allowlisted e deduplication key;
- finding repetido sem correção gera alerta, não loop de escrita;
- concorrência com submit/cancel deve resultar em skip/retry, não overwrite.

## 13. Processamento da outbox

O worker futuro deve:

1. selecionar `PENDING`/`FAILED` elegível com `FOR UPDATE SKIP LOCKED`;
2. registrar lease em `locked_at`, `locked_by`, status e attempts;
3. confirmar o claim antes de qualquer I/O;
4. despachar por handler allowlisted de `event_type`;
5. usar a deduplication key como idempotência downstream;
6. marcar `PROCESSED` em sucesso;
7. marcar `FAILED`, `last_error_code` e `next_attempt_at` em falha retryable;
8. usar `DISCARDED` somente por decisão operacional documentada;
9. recuperar lease vencido com comparação de owner e tempo;
10. nunca logar `payload`.

No primeiro rollout, somente handlers fake/internos podem ser autorizados.
Mensageria, identidade e background reais continuam fora de escopo.

## 14. Segurança

| Ameaça | Controle planejado |
|---|---|
| abuso distribuído | camadas CDN/backend/DB, budgets e alertas |
| replay/token stuffing | token hash-only, rotação, uso único, TTL e rate limit |
| session fixation | rotação no exchange, cookie `__Host-`, same-origin e revogação |
| brute force/enumeration | resposta uniforme, timing testado, `429` e jitter |
| concorrência | locks ordenados, `SKIP LOCKED`, state machines e idempotência |
| command flooding | quota por session/invitation/tenant, TTL e cardinalidade |
| resource exhaustion | 16 KiB, batches, timeouts, limites de conexão e custo |
| payload amplification | DTO allowlisted e resposta com tamanho máximo |
| header spoofing | trusted proxy e rejeição de forwarded headers não confiáveis |
| correlation ID abuse | 8–128 caracteres, allowlist e valor gerado quando inválido |
| cache poisoning | `no-store`, chave de cache inexistente para respostas privadas |
| CORS bypass | origem exata, credentials controladas, sem wildcard |
| CSP regression | teste automatizado de headers e ausência de terceiros |
| secret leakage | secret store, rotação, redaction e scanning |
| log injection | structured logging, controle de caracteres e sem texto livre |
| timing attacks | comparação constante e testes estatísticos razoáveis |

Runbooks obrigatórios: secret leak, token abuse, rate backend outage, scheduler
outage, outbox backlog, retention failure, cross-tenant attempt, PII in logs e
rollback. Cada runbook define detecção, contenção, comunicação, recuperação,
evidências sanitizadas e critério de encerramento.

## 15. Rollout futuro

| Etapa | Escopo | Gates de entrada | Critério de saída/rollback |
|---|---|---|---|
| DEV local | Supabase descartável, fakes | testes e fixtures sintéticas | suite completa e rollback/reaplicação |
| staging com fakes | domínio/proxy não produtivos | migrations reconciliadas, keys de teste, observabilidade | SLOs e abuso/retenção em dry-run |
| piloto interno | usuários autorizados e dados sintéticos/controlados | jurídico/DPO para o piloto, suporte e incident response | zero finding crítico e rollback ensaiado |
| condomínio piloto | tenant explicitamente aprovado | notice/termos, keys, rate limit distribuído, monitoramento | métricas estáveis, suporte e decisão formal |
| expansão controlada | lotes de tenants | aprovação de rollout e pós-piloto | canary, kill switch e rollback por lote |

Nenhuma etapa é autorizada por este documento. Feature permanece desligada.
Rollout exige migration remota em gate separado, reconciliação do migration
drift histórico, backup/restore validado e aprovação humana.

## 16. Preparação para a Fase 4

Handoff existente após submit 3B:

```text
participant criado
identity profile local protegido
registration_status = SUBMITTED
identity_status = SELF_DECLARED
invitation = COMPLETED
public session = COMPLETED
slot = CLAIMED
nenhum IdentityProvider executado
```

Antes da Fase 4, um contrato separado deve definir:

- dados mínimos e referência efêmera para abrir identity session;
- base legal e ciência/consentimento específico quando aplicável;
- policy e nível de identidade exigido;
- retenção de mídia/biometria no provider e proibição de template local;
- provider correlation ID, idempotency key e input fingerprint;
- estados de documento, liveness e face match 1:1 separados;
- timeout, retry, backoff, jitter e limite de tentativas;
- webhook autenticado, replay, eventos fora de ordem e polling;
- revisão manual, acessibilidade e alternativa sem câmera;
- audit/outbox sanitizados pelo orquestrador;
- cancelamento concorrente e callback tardio;
- nenhuma busca facial 1:N ou auto-deny.

A Fase 3C não cria identity case, sessão de provider, webhook ou biometria.

## 17. Plano futuro de testes

### 17.1 Jobs e scheduler

- idempotência, repetição e execução concorrente;
- batches, cursores, locks e ordem de locks;
- timeout, retry, jitter e lease vencido;
- falha parcial e retomada;
- dry-run sem escrita;
- limites e time budget;
- nenhuma PII em logs, métricas ou artifacts;
- scheduler atrasado, duplicado e indisponível;
- manual fallback.

### 17.2 Retenção

- elegibilidade por entidade, status, tenant e legal hold;
- dados ainda não elegíveis preservados;
- anonimização campo a campo;
- exclusão com integridade referencial;
- audit preservado e outbox conforme prazo aprovado;
- ciphertext/HMAC tratados separadamente;
- preview igual ao conjunto executado sob cutoff congelado;
- prova de descarte sanitizada;
- dados cancelados/expirados e blockers de PII.

### 17.3 Reconciliação

- cada finding da seção 12;
- estado válido não alterado;
- correções allowlisted;
- caso sensível enviado à revisão;
- concorrência com submit, cancel e expiração;
- evento e audit sem duplicação;
- terminal não reabre.

### 17.4 Segurança e carga

- replay, brute force, enumeration e token stuffing;
- command flooding e payload amplification;
- rate limit distribuído e consistência cross-region;
- backend de rate limit indisponível;
- trusted proxy, IPv6 e headers forjados;
- cache, CORS, CSP, cookie e headers;
- secret/log injection e timing;
- carga sustentada, burst e recuperação.

### 17.5 Regressão e rollback

- pgTAP, integrações e runtime roles 1A–3C;
- Edge/Deno 1D–3B;
- public web e admin-web;
- rollback `3C -> 3B -> 3A -> 2 -> 1C -> 1B -> 1A`;
- preservação após cada prefixo;
- reaplicação completa;
- pgTAP, integrações, runtime checks e smoke pós-reaplicação;
- feature desligada e `persons` preservada.

## 18. Migrations e artefatos futuros propostos

Nomes sugeridos, ainda não autorizados:

```text
supabase/migrations/YYYYMMDDHHMM00_verified_access_phase_3c_job_foundation.sql
supabase/migrations/YYYYMMDDHHMM10_verified_access_phase_3c_jobs.sql
supabase/migrations/YYYYMMDDHHMM20_verified_access_phase_3c_retention_security.sql
supabase/rollback/verified_access_phase_3c_rollback.sql
```

Responsabilidades:

1. fundação: executor role, run/lease metadata estritamente necessária,
   índices parciais e constraints sem PII;
2. jobs: funções internas e entrypoints de assinatura exata para expiração,
   purge, reconciliação e outbox;
3. retenção/segurança: policy versionada, grants/revokes, allowlists e guardas
   de descarte;
4. rollback: remoção integral da 3C, preservando 1A–3B.

Uma revisão futura deve provar se tabela de runs é indispensável. Não criar
infraestrutura genérica de filas quando `verified_access_outbox_events` já
atende ao domínio.

## 19. Rollback futuro

Ordem proposta:

1. desabilitar scheduler externo e aguardar execuções em voo;
2. revogar `EXECUTE` dos entrypoints 3C e membership do executor;
3. remover configuração e Edge Function de scheduler;
4. dropar entrypoints de jobs;
5. dropar helpers de retenção, reconciliação, lease e métricas;
6. dropar triggers 3C, se indispensáveis e autorizados;
7. dropar índices/constraints exclusivos da 3C;
8. dropar tabelas auxiliares exclusivas da 3C;
9. dropar executor role;
10. verificar preservação integral de 1A–3B;
11. para rollback cumulativo, continuar
    `3B -> 3A -> 2 -> 1C -> 1B -> 1A`;
12. reaplicar e repetir todas as suites.

Rollback não reativa invitation/session terminal e não restaura PII já
descartada. Retenção só pode ser habilitada após backup/restore e runbook
aprovados.

## 20. Allowlist futura proposta

Uma futura autorização deve fechar paths exatos dentro destas superfícies:

```text
supabase/migrations/<phase-3c-foundation>.sql
supabase/migrations/<phase-3c-jobs>.sql
supabase/migrations/<phase-3c-retention-security>.sql
supabase/rollback/verified_access_phase_3c_rollback.sql
supabase/functions/verified-access-maintenance/index.ts
supabase/functions/verified-access-maintenance/index.test.ts
supabase/functions/_shared/verified-access/maintenance/contracts.ts
supabase/functions/_shared/verified-access/maintenance/http.ts
supabase/tests/verified_access_phase_3c.sql
supabase/tests/verified_access_phase_3c_integration.psql
supabase/tests/verified_access_phase_3c_runtime_roles.psql
.github/workflows/verified-access-phase-3c.yml
.github/workflows/verified-access-maintenance.yml
.github/workflows/verified-access-phase-1a.yml
.github/workflows/verified-access-phase-3a.yml
.github/workflows/verified-access-phase-3b.yml
supabase/config.toml
docs/product/verified-access/phases/PHASE_3C.md
docs/product/verified-access/execution/CURRENT_TASK.md
docs/verified-access-phase-3c-validation.md
docs/runbooks/verified-access-*.md
```

Os placeholders não autorizam arquivos. Qualquer Edge Function, workflow
cumulativo ou tabela auxiliar exige justificativa e allowlist literal no
`CURRENT_TASK` futuro. Aplicações web, Expo, providers e `persons` permanecem
fora da allowlist técnica proposta.

## 21. Blockers obrigatórios

- retenção definitiva de PII;
- base legal;
- aprovação de jurídico e DPO;
- política campo a campo de anonimização;
- backend de rate limiting distribuído;
- backend de scheduler;
- gestão, rotação e custódia de chaves;
- monitoramento, SLOs e alertas;
- domínio público e proxy same-origin;
- incident response;
- política e capacidade de suporte;
- aprovação formal de rollout;
- política futura de biometria;
- legal hold, backups e prova de descarte;
- SLA e custo de qualquer serviço externo;
- reconciliação do migration drift antes de migration remota.

Nenhum blocker pode ser resolvido por inferência técnica.

## 22. Gates de implementação

Uma implementação futura só pode começar quando:

1. Fase 3B estiver incorporada e validada na base escolhida;
2. houver `CURRENT_TASK` ativo e versionado;
3. migrations, assinaturas, roles, índices e rollback estiverem fechados;
4. scheduler e rate backend tiverem decisão humana;
5. jurídico/DPO aprovarem retenção e anonimização aplicáveis;
6. allowlist literal estiver aprovada;
7. threat model e runbooks estiverem revisados;
8. testes de jobs, carga, segurança e regressão estiverem autorizados;
9. CI incluir rollback, preservação, reaplicação e smoke;
10. feature permanecer desligada;
11. não houver migration remota no contrato técnico local;
12. rollout continuar em gate separado.

Até lá:

```text
PHASE_3C = PLANNED_UNDER_REVIEW_NOT_AUTHORIZED
CURRENT_TASK = NO_ACTIVE_IMPLEMENTATION
```
