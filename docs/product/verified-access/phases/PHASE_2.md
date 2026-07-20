# Fase 2 — solicitações do morador

## 1. Status

Stage: `Planejada / em revisão / não autorizada`.

Este documento é somente um plano. Ele não autoriza migration, função SQL,
RPC, Edge Function, API, UI, teste técnico, feature flag ou deploy. Uma futura
execução exige novo contrato versionado em `execution/CURRENT_TASK.md`.

## 2. Objetivo e limite funcional

Planejar o fluxo autenticado em que um morador autorizado cria, lista,
consulta e cancela uma solicitação local de acesso para um ou vários visitantes
ou prestadores. A fase cria a solicitação e suas vagas individuais, sem iniciar
cadastro, convite, identidade, background, rede ou credencial.

Resultado funcional futuro:

```text
morador autenticado
  -> tenant e vínculos derivados no servidor
  -> policy ACTIVE e feature validadas
  -> request DRAFT + N slots OPEN
  -> audit + outbox na mesma transação
  -> consulta somente das próprias requests
  -> cancelamento transacional e idempotente
```

## 3. Inventário real reutilizado

### 3.1 Autenticação, tenant e vínculo

- Supabase Auth fornece o usuário autenticado.
- `user_profiles.id = auth.users.id` associa o usuário a um único
  `condominium_id`.
- `current_user_condominium_id()` deriva o tenant de `auth.uid()`.
- `unit_members` associa `user_id`, `unit_id` e `condominium_id` e distingue
  `RESIDENT`, `DEVICE` e `PORTARIA` por `member_type`.
- `units` possui FK para `condominiums`.
- As Edge Functions atuais usam `verify_jwt = false` em `supabase/config.toml`,
  validam o bearer token internamente em `/auth/v1/user` e só então acessam o
  backend.

O cliente nunca informa `condominium_id`. O endpoint futuro preserva o bearer
token do usuário ao chamar as RPCs autenticadas, para que `auth.uid()` seja a
identidade de negócio. `service_role` não substitui o usuário nem concede
autorização de morador.

### 3.2 Domínio local existente

- `verified_access_service_types`: catálogo global ativo, com código estável e
  `requires_description`.
- `verified_access_condominium_service_types`: habilitação e nome por tenant.
- `verified_access_policies`: policy versionada, uma `ACTIVE` por condomínio,
  imutável quando ativa.
- `verified_access_requests`: tenant, unidade, autor, tipo, janela, policy,
  limite, notas e estados.
- `verified_access_service_request_details`: detalhe exclusivo de prestador.
- `verified_access_participant_slots`: vagas numeradas e limitadas pela request.
- `verified_access_participants`: participantes individuais, ainda não
  necessários na criação sem convite ou identidade.
- `verified_access_audit_events`: append-only.
- `verified_access_outbox_events`: payload de negócio imutável e deduplicado.
- `verified_access_write_audit_event` e
  `verified_access_enqueue_outbox_event`: helpers internos, sem grant para
  papéis runtime.

### 3.3 Invariantes existentes

- Request, unidade, autor e policy são ligados por FKs compostas ao mesmo
  condomínio.
- `starts_at < ends_at` e `participant_limit` fica entre 1 e 100.
- Slots são únicos por `(request_id, slot_number)` e não excedem
  `participant_limit`.
- Detalhe de serviço só pertence a request `SERVICE_PROVIDER`.
- Tipos que exigem descrição rejeitam `other_description` vazio.
- State machines da Fase 1C rejeitam transições inválidas com SQLSTATE `P0001`.
- RLS está habilitada e não há acesso direto de `anon` ou `authenticated` às
  tabelas do Acesso Verificado.
- `VERIFIED_ACCESS` existe por condomínio e permanece desligada.

### 3.4 Contratos da Fase 1D

Os contratos e fakes de identity, background e messaging estão disponíveis em
`supabase/functions/_shared/verified-access/providers`, mas não são usados pela
Fase 2. Providers não decidem elegibilidade e nenhuma integração é chamada.

## 4. Atores e autorização

### 4.1 Morador autenticado

Uma operação futura exige simultaneamente:

1. bearer token válido;
2. `auth.uid()` presente;
3. `user_profiles` do usuário existente;
4. condomínio derivado por `current_user_condominium_id()`;
5. vínculo do usuário com a unidade solicitada no mesmo condomínio;
6. `member_type = 'RESIDENT'`;
7. condomínio e unidade considerados ativos segundo regra ainda a aprovar;
8. feature `VERIFIED_ACCESS` habilitada;
9. policy `ACTIVE` do mesmo condomínio.

O `unitId` é uma referência a validar, não uma fonte de tenant. Nenhum endpoint
aceita `condominiumId`, `requestedByUserId`, `policyId` ou `policyVersion`.

### 4.2 Visibilidade

Na Fase 2, o morador lê somente requests em que:

```text
condominium_id = current_user_condominium_id()
and requested_by_user_id = auth.uid()
```

Uma policy futura poderá ampliar visibilidade, mas isso não integra este plano.
IDs de outro tenant ou de outro autor retornam resposta indistinguível de item
inexistente. Nenhum dado da Rede Confia é consultado.

### 4.3 Papéis não autorizados

- `anon`: nenhum endpoint e nenhuma RPC.
- `authenticated` sem vínculo de morador: nenhum acesso de negócio.
- `DEVICE` e `PORTARIA`: não criam requests de morador.
- `service_role`: infraestrutura somente; nunca autorização de negócio.
- backoffice atual: fora do escopo desta fase.

## 5. Gaps e blockers de arquitetura

### P2-BLOCKER-01 — vínculo ativo

`unit_members` não possui `is_active`, `status`, `ended_at` ou equivalente.
`active_for_calls` controla chamadas e não pode ser reutilizado como autorização
de acesso verificado. Antes de implementar, o produto deve decidir se a
existência da linha significa vínculo ativo ou autorizar uma migration de
lifecycle.

### P2-BLOCKER-02 — condomínio e unidade ativos

`condominiums` e `units` não possuem estado ativo. A exigência de entidades
ativas não pode ser demonstrada pelo schema atual. É necessária decisão
documental; eventual migration deve receber contrato próprio.

### P2-BLOCKER-03 — habilitação do catálogo

Não existe regra implementada para a ausência de linha em
`verified_access_condominium_service_types`. A proposta segura é default-deny:
somente linha explícita com `is_enabled = true` e tipo global ativo aparece.
Essa semântica precisa de aprovação antes da execução.

### P2-BLOCKER-04 — idempotência persistente

As requests não armazenam idempotency key ou fingerprint. A outbox deduplica
eventos, mas não prova equivalência de comandos. Uma estrutura transacional de
idempotência é indispensável para cumprir o contrato.

### P2-BLOCKER-05 — atomicidade e auditoria do ator

Várias chamadas REST não criam request, detalhe, slots, audit e outbox na mesma
transação. Uma RPC transacional é indispensável. Além disso, o helper atual de
audit recebe `actor_id`, mas registra somente `actor_id_present`; a futura
execução deve criar um caminho que grave `actor_user_id = auth.uid()` sem
ampliar grants dos helpers existentes.

## 6. Decisões propostas para revisão

- Não coletar nome ou telefone na Fase 2. Eles não são necessários para criar
  vagas e o schema não possui armazenamento preliminar próprio no slot.
- `participantSlots` será um inteiro, não uma coleção de objetos: o servidor
  cria deterministicamente slots `1..N`.
- Requests nascem `DRAFT`; convites e transição para
  `INVITATIONS_PENDING` pertencem à Fase 3.
- Slots nascem `OPEN`; nenhum participant ou identity profile é criado.
- A ausência de configuração de tipo de serviço por condomínio é default-deny,
  sujeita à aprovação de `P2-BLOCKER-03`.
- A API será composta por Edge Functions autenticadas que chamam RPCs
  transacionais com o JWT do usuário, sem escrita direta do cliente nas tabelas.

## 7. Casos de uso planejados

1. Listar tipos de serviço globais ativos e explicitamente habilitados no
   condomínio do morador.
2. Criar request `VISITOR` com uma ou várias vagas.
3. Criar request `SERVICE_PROVIDER` com tipo de serviço e descrição quando
   exigida.
4. Listar requests do próprio morador com paginação por cursor.
5. Consultar request própria, detalhe de serviço e slots.
6. Cancelar request em estado permitido, cancelando slots abertos na mesma
   transação.
7. Repetir criação ou cancelamento sem duplicar domínio, audit ou outbox.
8. Produzir evento sanitizado para handoff futuro, sem processá-lo.

Não existe alteração geral de request nesta fase.

## 8. Contratos de input

### 8.1 Criação

Allowlist exata proposta:

```ts
type ResidentRequestCreateInput = {
  unitId: string;
  requestType: "VISITOR" | "SERVICE_PROVIDER";
  serviceTypeCode?: string;
  serviceDescription?: string;
  accessStartsAt: string;
  accessEndsAt: string;
  purpose?: string;
  operationalNote?: string;
  participantSlots: number;
  clientRequestId: string;
};
```

Regras:

- chaves desconhecidas são rejeitadas;
- `clientRequestId` é a idempotency key de criação, opaca, entre 16 e 128
  caracteres;
- `serviceTypeCode` é obrigatório apenas para `SERVICE_PROVIDER`;
- `serviceDescription` é obrigatório quando o catálogo exigir descrição e é
  proibido para visitante;
- `purpose` é texto operacional sanitizado de até 300 caracteres;
- `operationalNote` é texto sanitizado de até 1000 caracteres;
- `participantSlots` é inteiro positivo limitado pela policy aplicável;
- datas precisam ser ISO 8601 com offset, normalizadas para UTC;
- timezone, policy, autor, tenant, status, versão, expiração e números dos slots
  são definidos pelo servidor.

### 8.2 Cancelamento

```ts
type ResidentRequestCancelInput = {
  requestId: string;
  idempotencyKey: string;
  reasonCode?: "RESIDENT_CANCELLED";
};
```

Nenhum texto livre é aceito no cancelamento.

### 8.3 Campos proibidos

Rejeitar explicitamente:

```text
condominiumId
requestedByUserId
status
policyId
policyVersion
timezone
slotNumber
slotStatus
participantId
identityProfileId
identityLevel
identityStatus
backgroundStatus
networkStatus
eligibilityStatus
providerId
credential
case
signal
featureFlags
audit/outbox fields
createdAt/updatedAt/cancelledAt/expiresAt
```

Também são proibidos documento, CPF, nascimento, filiação, biometria e qualquer
payload de provider. `name` e `phone` ficam fora da allowlist e são adiados para
a Fase 3.

## 9. APIs internas planejadas

Todas são Edge Functions autenticadas, sem rota `anon`, com JSON estrito,
`Content-Type: application/json`, correlation ID técnico e respostas sem PII.

| Edge Function | Método | Finalidade | RPC interna planejada |
|---|---|---|---|
| `verified-access-service-types-list` | `GET` | catálogo habilitado do tenant derivado | `verified_access_list_resident_service_types` |
| `verified-access-request-create` | `POST` | criação transacional | `verified_access_create_resident_request` |
| `verified-access-request-list` | `GET` | lista própria paginada | `verified_access_list_resident_requests` |
| `verified-access-request-get` | `GET` | detalhe próprio | `verified_access_get_resident_request` |
| `verified-access-request-cancel` | `POST` | cancelamento transacional | `verified_access_cancel_resident_request` |

### 9.1 Autenticação comum

1. rejeitar ausência ou formato inválido do bearer token com HTTP 401;
2. validar token em Supabase Auth;
3. chamar a RPC com o mesmo JWT do usuário;
4. RPC deriva `auth.uid()` e `current_user_condominium_id()`;
5. nunca repassar `condominium_id` do body ou query string.

### 9.2 Outputs

Resumo de request:

```ts
type ResidentRequestSummary = {
  id: string;
  requestType: "VISITOR" | "SERVICE_PROVIDER";
  status: string;
  unitId: string;
  accessStartsAt: string;
  accessEndsAt: string;
  timezone: string;
  participantLimit: number;
  slotCounts: { open: number; reserved: number; claimed: number; cancelled: number; expired: number };
  service?: { typeCode: string; displayName: string; description?: string };
  createdAt: string;
};
```

O detalhe acrescenta slots com `id`, `slotNumber` e `status`. Não retorna perfil
de identidade, network subject, case, signal, audit ou outbox.

### 9.3 Paginação e limites

- ordenação estável por `created_at desc, id desc`;
- cursor opaco derivado desses dois campos;
- `limit` padrão 20, mínimo 1 e máximo 50;
- filtros permitidos: `status`, `requestType`, `from`, `to`;
- sem offset irrestrito e sem busca por texto livre;
- request body máximo proposto: 16 KiB;
- timeout proposto: 10 segundos;
- rate limiting por usuário e tenant é gate futuro, com limites a aprovar antes
  de habilitar a feature.

### 9.4 Erros estáveis

| HTTP | Código | Situação |
|---:|---|---|
| 400 | `REQUEST_PAYLOAD_INVALID` | JSON, tipo, chave desconhecida ou formato inválido |
| 401 | `AUTHENTICATION_REQUIRED` | token ausente ou inválido |
| 403 | `UNIT_NOT_ALLOWED` | usuário sem vínculo autorizado |
| 404 | `VERIFIED_ACCESS_NOT_AVAILABLE` | feature/policy indisponível, sem revelar dados |
| 404 | `REQUEST_NOT_FOUND` | request inexistente, de outro autor ou tenant |
| 409 | `IDEMPOTENCY_CONFLICT` | mesma chave com fingerprint diferente |
| 409 | `REQUEST_STATE_CONFLICT` | cancelamento fora da transição permitida |
| 422 | `REQUEST_PERIOD_INVALID` | janela viola policy |
| 422 | `PARTICIPANT_LIMIT_INVALID` | quantidade viola policy |
| 422 | `SERVICE_TYPE_NOT_AVAILABLE` | tipo inativo, não habilitado ou incompatível |
| 500 | `INTERNAL_ERROR` | falha sanitizada, com correlation ID |

Erros de domínio planejados usam SQLSTATE `P0001` e código estável separado da
mensagem. Constraints existentes continuam expondo `23503`, `23505` e `23514`
somente à camada interna; a Edge Function os normaliza sem detalhes do schema.

## 10. Regras de policy e negócio

Na mesma transação de criação, a RPC futura deve:

1. travar e validar o usuário e seu tenant;
2. validar vínculo de morador com a unidade;
3. validar lifecycle depois da resolução dos blockers 01 e 02;
4. exigir `condominium_feature_enabled(tenant, 'VERIFIED_ACCESS') = true`;
5. carregar a única policy `ACTIVE` do tenant;
6. escolher limite por `requestType`;
7. exigir janela futura, `starts_at < ends_at`, antecedência mínima/máxima e
   duração máxima da policy;
8. usar o timezone da policy, sem aceitá-lo do cliente;
9. validar serviço global ativo e habilitação do tenant;
10. validar descrição obrigatória;
11. rejeitar duplicidade por idempotência;
12. criar request, detalhe opcional, slots, audit e outbox atomicamente.

Quando a feature estiver desligada ou não houver policy ativa, a operação falha
com `VERIFIED_ACCESS_NOT_AVAILABLE` sem confirmar a existência de unidade,
policy ou dados do condomínio.

## 11. Estados e transições nesta fase

### 11.1 Request

Estado inicial: `DRAFT`.

Transição autorizada pela Fase 2:

```text
DRAFT -> CANCELLED
```

`INVITATIONS_PENDING`, `IN_PROGRESS`, `PARTIALLY_ELIGIBLE`, `ELIGIBLE` e
`COMPLETED` dependem de fases posteriores. `EXPIRED` será produzido por job
futuro. `COMPLETED`, `CANCELLED` e `EXPIRED` permanecem terminais.

### 11.2 Slots

Estado inicial: `OPEN`, com `claimed_at = null`.

Transição autorizada pela Fase 2:

```text
OPEN -> CANCELLED
```

`RESERVED` e `CLAIMED` pertencem ao convite/cadastro da Fase 3. `EXPIRED`
depende de job futuro.

### 11.3 Participants

Nenhum participant é criado pela Fase 2. Quando a Fase 3 criar um participante,
ele deverá respeitar a FK composta de request/slot/tenant e as state machines
existentes de registration, identity, background, network e eligibility.

### 11.4 Invariantes agregadas

- quantidade de slots é exatamente `participant_limit`;
- slot number é a sequência server-side `1..participant_limit`;
- todo slot pertence à mesma request e ao mesmo tenant;
- visitante não possui service detail;
- prestador possui exatamente um service detail válido;
- request cancelada não recebe novos slots, detalhes ou participants;
- cancelamento da request cancela todos os slots ainda não terminais;
- callback ou handoff futuro nunca reabre request cancelada.

## 12. Persistência e transação

### 12.1 Criação

Uma única RPC futura cria, em uma transação:

1. registro de idempotência em `verified_access_request_commands`;
2. `verified_access_requests` com tenant, autor, policy, timezone e status
   definidos pelo servidor;
3. `verified_access_service_request_details` somente para prestador;
4. N `verified_access_participant_slots` em `OPEN`;
5. audit `VerifiedAccessRequestCreated`;
6. outbox `VerifiedAccessRequestCreated`.

Nenhum `verified_access_participants` ou `verified_access_identity_profiles` é
criado.

### 12.2 Cancelamento

Na mesma transação:

1. travar a request própria;
2. validar estado e idempotência;
3. atualizar request para `CANCELLED`, `cancelled_at = now()` e incrementar
   `version`;
4. cancelar slots `OPEN` permitidos pela state machine;
5. gravar um audit e um outbox deduplicados;
6. retornar o mesmo resultado em repetição equivalente.

### 12.3 Audit e outbox

Payload permitido:

```json
{
  "requestId": "uuid",
  "requestType": "VISITOR",
  "slotCount": 2,
  "policyVersion": 3,
  "eventCode": "VerifiedAccessRequestCreated"
}
```

Payload proibido inclui nome, telefone, unidade em texto livre, finalidade,
observação, documentos, PII, token, perfil, case, signal ou payload de provider.

Deduplication keys propostas:

```text
verified-access:request:{requestId}:created:v1
verified-access:request:{requestId}:cancelled:v1
```

Audit e outbox são gravados pela RPC de domínio, na mesma transação, nunca pela
Edge Function em chamadas separadas.

## 13. Idempotência e concorrência

Tabela futura indispensável proposta:

```text
verified_access_request_commands
  condominium_id uuid
  actor_user_id uuid
  operation text
  idempotency_key_digest text
  input_fingerprint text
  resource_id uuid null
  response_sanitized jsonb
  created_at timestamptz
  expires_at timestamptz
```

Chave única:

```text
(condominium_id, actor_user_id, operation, idempotency_key_digest)
```

Regras:

- a Edge Function valida formato, mas a RPC adquire o lock e decide;
- mesma chave e fingerprint retorna a mesma request/resposta;
- mesma chave e fingerprint diferente retorna `IDEMPOTENCY_CONFLICT`;
- fingerprint usa JSON canônico da allowlist, sem timestamps de tentativa;
- nome e telefone não entram porque não pertencem à Fase 2;
- criação de slots usa `generate_series(1, participant_limit)` na transação;
- cancelamento usa lock de linha na request;
- repetição não duplica audit ou outbox;
- retenção da chave precisa ser maior que a janela máxima de retry e será
  definida na policy/contrato futuro.

## 14. Privacidade e minimização

Dados mínimos persistidos nesta fase:

- IDs técnicos de tenant, unidade, usuário, policy, request e slots;
- tipo de request e serviço;
- janela UTC e timezone da policy;
- quantidade;
- finalidade e observação operacionais opcionais e sanitizadas;
- descrição de serviço quando necessária;
- metadata técnica de idempotência sem PII.

Nome e telefone preliminares são adiados para a Fase 3 porque:

- não são necessários para criar a autorização e suas vagas;
- o slot atual não possui armazenamento protegido para esses dados;
- telefone não identifica pessoa;
- convite, finalidade, retenção e criptografia do contato ainda não estão
  autorizados.

Não há documento, CPF, nascimento, filiação, biometria, background, HMAC de PII,
busca global ou propagação entre condomínios. Textos operacionais são tratados
como potencialmente sensíveis: limitados, sanitizados, nunca copiados para log,
audit ou outbox e sujeitos à retenção da request.

## 15. Handoff futuro para a Fase 3

O outbox `VerifiedAccessRequestCreated` deixa a request disponível para um
processador futuro, mas nenhum consumidor é criado ou executado nesta fase.

A Fase 3 será responsável por:

- participantes preliminares;
- nome/telefone protegidos, se aprovados;
- convite, token e sessão pública;
- compartilhamento manual e messaging fake;
- reserva/reivindicação de slots;
- transição para `INVITATIONS_PENDING`.

O handoff não contém PII e não altera estado enquanto não houver contrato da
Fase 3.

## 16. Grants e RLS planejados

| Objeto | `PUBLIC` | `anon` | `authenticated` | `service_role` |
|---|---:|---:|---:|---:|
| Tabelas existentes e command table | nenhum | nenhum | nenhum direto | manter matriz mínima existente |
| Cinco RPCs de morador | revogado | nenhum | `EXECUTE` nas assinaturas exatas | revogado; não é ator de negócio |
| Helpers internos | revogado | revogado | revogado | revogado |
| Edge Functions | n/a | proibido | JWT obrigatório | chamada interna não autoriza negócio |

RPCs são `security definer`, com `search_path = public, pg_temp`, validação de
`auth.uid()`, tenant e vínculo antes de qualquer leitura ou escrita. Nenhuma
policy `USING (true)` e nenhum grant de tabela é adicionado a `authenticated`.

## 17. Migrations futuras propostas

Somente após novo contrato:

```text
supabase/migrations/<timestamp>_verified_access_phase_2_request_commands.sql
supabase/migrations/<timestamp>_verified_access_phase_2_resident_request_rpcs.sql
supabase/migrations/<timestamp>_verified_access_phase_2_resident_request_security.sql
supabase/rollback/<timestamp>_verified_access_phase_2_rollback.sql
```

Responsabilidades:

1. `request_commands`: tabela/constraints/índices de idempotência e, somente se
   aprovadas, mudanças mínimas exigidas pelos blockers de lifecycle;
2. `resident_request_rpcs`: cinco RPCs, validações, transação, audit e outbox;
3. `resident_request_security`: RLS, REVOKEs explícitos e grants mínimos das
   assinaturas exatas;
4. rollback: remover grants, RPCs, helpers novos e command table na ordem
   inversa, preservando integralmente Fases 1A–1D.

Nenhuma alteração das tabelas de rede, `persons` ou providers é prevista.

## 18. Allowlist futura de arquivos

### 18.1 Novos arquivos propostos

```text
supabase/migrations/<timestamp>_verified_access_phase_2_request_commands.sql
supabase/migrations/<timestamp>_verified_access_phase_2_resident_request_rpcs.sql
supabase/migrations/<timestamp>_verified_access_phase_2_resident_request_security.sql
supabase/rollback/<timestamp>_verified_access_phase_2_rollback.sql
supabase/functions/verified-access-service-types-list/index.ts
supabase/functions/verified-access-service-types-list/deno.json
supabase/functions/verified-access-request-create/index.ts
supabase/functions/verified-access-request-create/deno.json
supabase/functions/verified-access-request-list/index.ts
supabase/functions/verified-access-request-list/deno.json
supabase/functions/verified-access-request-get/index.ts
supabase/functions/verified-access-request-get/deno.json
supabase/functions/verified-access-request-cancel/index.ts
supabase/functions/verified-access-request-cancel/deno.json
supabase/functions/_shared/verified-access/resident-requests/contracts.ts
supabase/functions/_shared/verified-access/resident-requests/auth.ts
supabase/functions/_shared/verified-access/resident-requests/http.ts
supabase/functions/_shared/verified-access/resident-requests/tests/contracts.test.ts
supabase/functions/_shared/verified-access/resident-requests/tests/auth.test.ts
supabase/tests/verified_access_phase_2.sql
supabase/tests/verified_access_phase_2_integration.psql
.github/workflows/verified-access-phase-2.yml
docs/verified-access-phase-2-validation.md
```

### 18.2 Arquivos existentes autorizáveis

```text
supabase/config.toml
docs/product/verified-access/README.md
docs/product/verified-access/ROADMAP.md
docs/product/verified-access/execution/CURRENT_TASK.md
docs/product/verified-access/phases/PHASE_2.md
```

A implementação futura deve substituir placeholders de timestamp por nomes
exatos e reduzir essa allowlist se algum arquivo não for necessário. Qualquer
path adicional exige revisão documental. Não são previstos arquivos em
`apps/admin-web`, app Expo ou providers da Fase 1D.

## 19. Plano de testes

### 19.1 SQL/pgTAP

- command table, constraints, índices, RLS e grants;
- somente assinaturas exatas das cinco RPCs executáveis por `authenticated`;
- `PUBLIC`, `anon` e `service_role` sem EXECUTE;
- feature desligada e policy ausente;
- vínculo de unidade/tenant e papéis não residentes;
- catálogo global inativo e override desabilitado/ausente;
- visitor sem detail e service com detail obrigatório;
- período, duração, antecedência e limites da policy;
- criação exata de N slots e sequência `1..N`;
- audit append-only, outbox imutável e payload sanitizado;
- mesma key/input retorna mesmo ID; input diferente retorna conflito;
- cancelamento repetido sem novos eventos;
- terminal não reabre;
- `persons` e domínio de rede sem dependência.

### 19.2 Integração SQL

- tenants A/B e usuários distintos;
- usuário sem perfil ou vínculo;
- unidade de outro condomínio;
- request de outro autor indistinguível de inexistente;
- criação visitante individual e múltipla;
- criação prestador e `OTHER`;
- rollback e reaplicação;
- preservação integral das Fases 1A, 1B e 1C.

### 19.3 Deno/Edge

- autenticação ausente/inválida;
- allowlist e payload desconhecido;
- mass assignment de todos os campos proibidos;
- normalização de datas e paginação;
- mapeamento SQLSTATE/HTTP;
- feature desligada sem enumeração;
- mocks sem rede externa e sem service_role como autorização;
- logs, erros e correlation IDs sem PII;
- body e limites de paginação.

### 19.4 CI, rollback e reaplicação

Workflow futuro `verified-access-phase-2.yml`:

1. checkout, Node 24 e dependências;
2. Supabase local com diagnostics sanitizados;
3. `db reset`;
4. pgTAP 1A/1B/1C/2;
5. integrações 1A/1B/1C/2;
6. runtime role checks;
7. Deno fmt, lint, check e test dos módulos/endpoints da Fase 2;
8. `supabase db lint`;
9. rollback 2 e verificação de preservação 1A–1D;
10. reaplicação;
11. testes pós-reaplicação;
12. admin lint/build apenas como regressão, sem alterar admin-web.

Artifacts contêm somente logs sanitizados. Nenhuma chave local ou remota é
publicada.

## 20. Gates para autorização futura

A implementação não pode ser autorizada até confirmar:

- semântica de vínculo, condomínio e unidade ativos;
- comportamento da ausência de configuração de service type;
- estrutura e retenção de idempotência;
- cinco contratos de endpoint e RPC;
- grants mínimos e origem segura do tenant;
- regra final de cancelamento;
- ausência de nome/telefone ou aprovação explícita para coletá-los;
- audit com ator identificável e outbox sanitizada;
- migrations, rollback e allowlist final com timestamps reais;
- testes e workflow CI;
- feature continua desligada e nenhuma migration remota será executada.

Blockers humanos incluem mudança de produto, nova PII, telefone antes do
convite, alteração de policy, migration estrutural adicional, habilitação de
feature, migration remota, custo ou integração externa.

## 21. Fora de escopo explícito

- Implementar este plano.
- App Expo, admin-web ou UI do morador.
- Endpoint público ou acesso `anon`.
- Convite, token, sessão pública ou reivindicação de vaga.
- WhatsApp, SMS, e-mail ou provider real/fake em operação.
- Nome ou telefone preliminar.
- Cadastro público e aviso/receipt de privacidade.
- Documento, CPF, biometria, liveness ou face match.
- Background real ou fake operacional.
- Elegibilidade, decisão humana ou revisão.
- Network subject, case, signal ou Rede Confia operacional.
- Credencial, QR Code, portaria, check-in ou check-out.
- Processador de outbox, fila, cron, retry ou DLQ.
- Alterar `persons` ou qualquer tabela central de rede.
- Habilitar feature ou executar migration remota.
- Fase 3 ou qualquer fase posterior.

## 22. Condição de autorização

`CURRENT_TASK.md` permanece `CURRENT TASK — NO ACTIVE IMPLEMENTATION`.
Somente um novo contrato versionado, após revisão deste plano e resolução dos
blockers, poderá autorizar a execução técnica da Fase 2.
