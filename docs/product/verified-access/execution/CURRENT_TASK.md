# CURRENT TASK — VA-P2-RESIDENT-REQUESTS

## Objetivo

Implementar a Fase 2 — solicitações autenticadas do morador — conforme o contrato
final em:

docs/product/verified-access/phases/PHASE_2.md

A execução deve permitir:

- listar tipos de serviço habilitados;
- criar solicitação VISITOR ou SERVICE_PROVIDER;
- criar N participant slots;
- listar solicitações próprias;
- consultar solicitação própria;
- cancelar solicitação DRAFT;
- garantir idempotência persistente;
- garantir tenant isolation;
- registrar audit e outbox sanitizados;
- expor cinco Edge Functions autenticadas.

## Base autorizada

Base obrigatória:

4284085959e185892f00c77dd89138838ba1dcdb

Branch:

agent/verified-access-phase-2

PR:

https://github.com/luisbizzan/confia-interfone-digital/pull/6

## Decisões vinculantes

### Vínculo do morador

A existência da linha em unit_members representa vínculo MVP quando:

- user_id = auth.uid();
- member_type = RESIDENT;
- unit_id corresponde à unidade solicitada;
- condominium_id = current_user_condominium_id();
- unidade pertence ao mesmo condomínio.

active_for_calls não participa da autorização.

Não criar lifecycle de unit_members, units ou condominiums.

### Catálogo

Default-deny:

- verified_access_service_types.is_active = true;
- linha explícita em verified_access_condominium_service_types;
- is_enabled = true;
- mesmo condomínio.

Ausência de configuração significa serviço indisponível.

### Feature

Todas as cinco operações exigem:

VERIFIED_ACCESS = true

A feature permanece desligada por padrão.

Não habilitar feature nesta execução.

### Policy

- catálogo, create e cancel exigem policy ACTIVE;
- list/get de requests próprias podem funcionar sem policy ACTIVE atual;
- nunca aplicar defaults silenciosos;
- policy e tenant são derivados pelo servidor.

### PII

Não coletar:

- nome;
- telefone;
- CPF;
- documento;
- nascimento;
- biometria;
- background;
- provider IDs;
- credencial;
- dados da Rede Confia.

participantSlots é inteiro.

Não criar participants nesta fase.

## Migrations autorizadas

Criar exatamente:

supabase/migrations/20260720100000_verified_access_request_commands.sql
supabase/migrations/20260720101000_verified_access_resident_request_rpcs.sql

Não criar terceira migration sem parar e reportar BLOCKED.

## Tabela autorizada

Criar:

verified_access_request_commands

Campos mínimos:

- id uuid primary key;
- condominium_id uuid not null;
- actor_user_id uuid not null;
- command_type text not null;
- idempotency_key text not null;
- input_fingerprint text not null;
- request_id uuid null;
- status text not null;
- result_code text null;
- result_payload jsonb null;
- created_at timestamptz not null;
- completed_at timestamptz null.

Taxonomias:

command_type:
- CREATE_REQUEST
- CANCEL_REQUEST

status:
- PROCESSING
- COMPLETED

Constraints obrigatórias:

- unique:
  condominium_id,
  actor_user_id,
  command_type,
  idempotency_key;

- input_fingerprint obrigatório e não vazio;
- idempotency_key entre 16 e 128 caracteres;
- result_payload somente objeto JSON sanitizado;
- COMPLETED exige completed_at;
- PROCESSING exige completed_at null;
- request_id coerente com tenant;
- sem PII;
- sem purpose;
- sem operationalNote;
- sem nome, telefone, documento ou biometria.

RLS:

- habilitada;
- default-deny;
- nenhuma policy permissiva;
- nenhum grant para PUBLIC;
- nenhum grant para anon;
- nenhum acesso direto de authenticated;
- service_role não é autorização de negócio.

## RPCs autorizadas

Criar exatamente:

- verified_access_list_resident_service_types;
- verified_access_create_resident_request;
- verified_access_list_resident_requests;
- verified_access_get_resident_request;
- verified_access_cancel_resident_request.

Todas devem:

- ser security definer;
- usar SET search_path = public, pg_temp;
- derivar auth.uid();
- derivar current_user_condominium_id();
- rejeitar usuário sem tenant;
- nunca aceitar condominium_id do cliente;
- nunca aceitar actor_user_id do cliente;
- nunca aceitar policy_id do cliente;
- nunca aceitar status do cliente;
- não conceder autorização ao service_role;
- não expor request de outro autor ou tenant;
- retornar erros estáveis;
- respeitar feature flag;
- usar grants mínimos e explícitos.

Revogar EXECUTE de:

- PUBLIC;
- anon;
- authenticated;
- service_role;

por padrão.

Qualquer grant técnico necessário para authenticated deve ocorrer apenas em
wrapper/caminho explicitamente testado e documentado. Não ampliar helpers
existentes.

## RPC — catálogo

verified_access_list_resident_service_types

Deve:

- exigir usuário autenticado;
- derivar tenant;
- exigir VERIFIED_ACCESS habilitada;
- exigir policy ACTIVE;
- retornar somente tipos globais ativos e explicitamente habilitados;
- aplicar default-deny;
- não retornar configurações de outro tenant;
- retornar apenas IDs, codes, display names e requires_description;
- não retornar metadata interna.

## RPC — criação

verified_access_create_resident_request

Input conceitual estrito:

- unit_id;
- request_type;
- service_type_code nullable;
- service_description nullable;
- access_starts_at;
- access_ends_at;
- purpose nullable;
- operational_note nullable;
- participant_slots;
- client_request_id;
- correlation_id.

Proibir chaves/campos fora da allowlist na Edge Function.

Regras:

- usuário autenticado;
- tenant derivado;
- vínculo RESIDENT válido;
- unit no mesmo tenant;
- feature habilitada;
- policy ACTIVE;
- request_type:
  VISITOR | SERVICE_PROVIDER;
- VISITOR não aceita service_type_code;
- SERVICE_PROVIDER exige service_type_code;
- service type deve estar ativo e habilitado;
- service_description somente quando requires_description;
- datas válidas em UTC;
- starts_at < ends_at;
- janela conforme policy;
- participant_slots conforme policy;
- request nasce DRAFT;
- slots nascem OPEN;
- criar slots numerados 1..N;
- não criar participant;
- não criar identity profile;
- não chamar provider;
- não criar convite;
- não alterar Rede Confia.

Transação única:

- command PROCESSING;
- request;
- service detail quando aplicável;
- N slots;
- audit;
- outbox;
- command COMPLETED.

Idempotência:

- fingerprint calculado no servidor;
- mesma key + mesmo fingerprint + COMPLETED:
  retornar resultado lógico anterior;
- mesma key + fingerprint divergente:
  IDEMPOTENCY_CONFLICT;
- mesma key + PROCESSING:
  COMMAND_IN_PROGRESS;
- nenhuma duplicação de request, slots, audit ou outbox.

Fingerprint CREATE_REQUEST:

- unitId;
- requestType;
- serviceTypeCode normalizado;
- serviceDescription normalizada;
- accessStartsAt UTC;
- accessEndsAt UTC;
- purpose normalizado;
- operationalNote normalizada;
- participantSlots.

Excluir:

- correlationId;
- timestamp da tentativa;
- auth.uid();
- condominiumId;
- policyId;
- status;
- clientRequestId.

## RPC — listagem

verified_access_list_resident_requests

Deve:

- exigir autenticação;
- exigir feature habilitada;
- não exigir policy ACTIVE atual;
- retornar somente requests:
  condominium_id = tenant derivado;
  requested_by_user_id = auth.uid();
- usar paginação por cursor;
- ordenar por created_at desc, id desc;
- limit padrão 20;
- máximo 50;
- filtros estritos:
  status,
  request_type,
  from,
  to;
- sem texto livre;
- sem offset irrestrito;
- sem dados de identity/network/background;
- sem audit/outbox;
- sem dados de outro morador.

## RPC — detalhe

verified_access_get_resident_request

Deve:

- exigir autenticação;
- exigir feature habilitada;
- não exigir policy ACTIVE atual;
- retornar somente request própria;
- request alheia/tenant divergente:
  REQUEST_NOT_FOUND;
- retornar:
  request;
  service detail sanitizado;
  slots com id, slot_number e status;
- não retornar participant;
- não retornar identity profile;
- não retornar network subject/case/signal;
- não retornar audit/outbox.

## RPC — cancelamento

verified_access_cancel_resident_request

Input:

- request_id;
- idempotency_key;
- reason_code;
- correlation_id.

reason_code permitido:

RESIDENT_CANCELLED

Regras:

- usuário autenticado;
- tenant derivado;
- feature habilitada;
- policy ACTIVE;
- request própria;
- somente request DRAFT;
- todos os slots devem estar OPEN;
- cancelar request;
- cancelar slots OPEN;
- não aceitar CLAIMED ou RESERVED;
- não criar participant;
- não alterar identity/background/network;
- não operar credencial;
- não operar Rede Confia.

Transação única:

- command PROCESSING;
- update request;
- update slots;
- audit;
- outbox;
- command COMPLETED.

Fingerprint CANCEL_REQUEST:

- requestId;
- reasonCode.

Idempotência igual à criação.

## Audit

Eventos:

- VERIFIED_ACCESS_REQUEST_CREATED;
- VERIFIED_ACCESS_REQUEST_CANCELLED.

Audit deve conter somente:

- actor_user_id;
- condominium_id;
- request_id;
- action code;
- correlation_id;
- IDs e códigos sanitizados.

Não registrar:

- purpose;
- operational_note;
- service_description;
- nome;
- telefone;
- body;
- Authorization;
- documento;
- biometria;
- payload bruto.

## Outbox

Eventos:

- VERIFIED_ACCESS_REQUEST_CREATED;
- VERIFIED_ACCESS_REQUEST_CANCELLED.

Payload permitido:

- request_id;
- condominium_id;
- unit_id;
- request_type;
- participant_limit;
- access_starts_at;
- access_ends_at;
- event_code.

Não incluir texto livre ou PII.

Deduplication key deve derivar do comando idempotente.

## Edge Functions autorizadas

Criar exatamente:

supabase/functions/verified-access-service-types-list/index.ts
supabase/functions/verified-access-request-create/index.ts
supabase/functions/verified-access-request-list/index.ts
supabase/functions/verified-access-request-get/index.ts
supabase/functions/verified-access-request-cancel/index.ts

Cada função deve:

- validar bearer token;
- rejeitar token ausente/inválido;
- usar o JWT do usuário na chamada à RPC;
- não usar service_role para regra de negócio;
- validar Content-Type quando houver body;
- validar JSON estrito;
- rejeitar unknown fields;
- limitar body a 16 KiB;
- gerar ou validar correlation ID;
- não registrar Authorization;
- não registrar body;
- não registrar purpose;
- não registrar operational_note;
- não registrar service_description;
- não habilitar CORS amplo;
- não aceitar anon;
- mapear erros SQL para códigos HTTP estáveis.

## Shared modules autorizados

Utilizar/criar somente os módulos shared definidos na allowlist final de
PHASE_2.md.

Eles podem cobrir:

- autenticação;
- parsing JSON estrito;
- correlation ID;
- respostas de erro;
- validação de input.

Não criar framework genérico além do necessário para as cinco funções.

## Configuração

Atualizar supabase/config.toml somente para registrar as cinco Edge Functions,
mantendo o padrão real do repositório.

Não alterar configuração de outras funções.

## Rollback autorizado

Criar:

supabase/rollback/verified_access_phase_2_rollback.sql

O rollback deve:

- remover grants da Fase 2;
- remover as cinco RPCs;
- remover funções/helpers exclusivos da Fase 2;
- remover verified_access_request_commands;
- preservar integralmente Fases 1A–1D;
- preservar requests, participants, slots, policies, audit e outbox existentes;
- preservar persons;
- preservar Rede Confia;
- preservar providers da Fase 1D;
- ser reaplicável após rollback.

## Testes obrigatórios

Adicionar testes conforme a allowlist de PHASE_2.md para:

### Banco

- tabela, constraints, FKs, índices, RLS e grants;
- search_path das RPCs;
- feature desligada;
- policy ausente;
- catálogo default-deny;
- vínculo RESIDENT;
- active_for_calls ignorado;
- vínculo de outro tenant negado;
- unidade de outro tenant negada;
- create VISITOR;
- create SERVICE_PROVIDER;
- descrição obrigatória;
- slots 1..N;
- nenhum participant criado;
- mesma key + mesmo fingerprint;
- fingerprint divergente;
- PROCESSING;
- concorrência;
- cancelamento;
- cancelamento idempotente;
- estado inválido;
- slots não OPEN;
- tenant isolation;
- request alheia indistinguível;
- list/get histórico sem policy atual;
- audit actor_user_id;
- outbox sanitizado;
- sem purpose/note em audit/outbox;
- grants default-deny;
- service_role sem autorização de negócio.

### Edge Functions

- 401 sem token;
- JSON inválido;
- unknown fields;
- payload acima do limite;
- correlation ID;
- mapeamento de erros;
- bearer token preservado para RPC;
- nenhuma utilização de service_role como ator;
- nenhuma PII em logs;
- nenhuma exposição de body ou Authorization.

### Rollback

- rollback completo;
- preservação 1A–1D;
- reaplicação;
- smoke tests pós-reaplicação.

## Workflow autorizado

Criar ou alterar somente o workflow definido na allowlist final de PHASE_2.md.

O CI deve executar:

- Supabase local;
- migrations do zero;
- pgTAP;
- integration SQL;
- runtime roles;
- db lint;
- Edge Function fmt/lint/check/test;
- rollback;
- verificação de preservação;
- reaplicação;
- smoke pós-reaplicação;
- admin-web lint/build existente sem alteração funcional.

## Arquivos autorizados

Autorizar exatamente os paths finais listados em PHASE_2.md, incluindo:

- as duas migrations;
- rollback;
- cinco Edge Functions;
- quatro módulos shared definidos;
- testes SQL/pgTAP/integration/runtime roles;
- testes Deno;
- workflow da Fase 2;
- supabase/config.toml;
- CURRENT_TASK;
- documento de validação da Fase 2.

Nenhum arquivo fora da allowlist pode ser alterado.

Caso seja necessário um path não listado:

- parar;
- não alterar;
- reportar BLOCKED.

## Fora de escopo

- UI;
- admin-web funcional;
- Expo;
- convite;
- WhatsApp;
- cadastro público;
- nome;
- telefone;
- documento;
- biometria;
- liveness;
- face match;
- background;
- provider real;
- provider fake;
- credencial;
- QR Code;
- portaria;
- Rede Confia operacional;
- migration remota;
- feature habilitada;
- Fase 3;
- lifecycle de morador/unidade/condomínio.

## Validações obrigatórias

Antes de commit:

- verificar somente paths autorizados;
- UTF-8;
- caracteres de controle;
- git diff --check;
- migrations locais do zero;
- testes completos;
- rollback;
- reaplicação;
- worktree limpa após commit/push.
