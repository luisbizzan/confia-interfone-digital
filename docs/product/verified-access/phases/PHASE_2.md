# Fase 2 — solicitações do morador

## 1. Status

Stage: `Planejada / gate documental final / não autorizada`.

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
7. existência válida do condomínio e da unidade, com FKs de tenant íntegras;
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

## 5. Blockers documentalmente resolvidos

Os blockers abaixo estão resolvidos para o MVP no plano. Isso não autoriza
implementação; o gate `P2-GATE-EXECUTION-CONTRACT` continua pendente.

### P2-BLOCKER-01 — vínculo do morador: resolvido

A existência de uma linha em `unit_members` é o vínculo autorizado quando,
simultaneamente:

```text
user_id = auth.uid()
member_type = 'RESIDENT'
unit_id = p_unit_id
condominium_id = current_user_condominium_id()
units.id = p_unit_id and units.condominium_id = condominium_id
```

`active_for_calls` é ignorado: ele pertence exclusivamente ao fluxo de
chamadas. A Fase 2 não cria lifecycle de `unit_members`. Exclusão ou encerramento
do vínculo continua sob responsabilidade da gestão de moradores existente.

Débito futuro: `UNIT_MEMBER_LIFECYCLE_NOT_MODELED`.

### P2-BLOCKER-02 — condomínio e unidade: resolvido

Como `condominiums` e `units` não possuem lifecycle ou status, a existência das
entidades e a integridade das FKs de tenant são suficientes no MVP. A Fase 2
não adiciona `is_active`, `status`, lifecycle ou regra inferida para essas
tabelas.

Débito futuro: `CONDOMINIUM_UNIT_LIFECYCLE_NOT_MODELED`.

### P2-BLOCKER-03 — catálogo: resolvido

Semântica vinculante: default-deny. Um tipo só pode ser listado ou usado quando
`verified_access_service_types.is_active = true`, existe linha do mesmo tenant
em `verified_access_condominium_service_types` e essa linha possui
`is_enabled = true`. Ausência de configuração significa serviço indisponível;
não existe fallback permissivo para o catálogo global.

### P2-BLOCKER-04 — idempotência persistente: resolvido

A futura migration `verified_access_request_commands` está aprovada no plano.
Ela armazenará comando, fingerprint canônico, estado e resultado sanitizado na
mesma transação da alteração de domínio, audit e outbox. O contrato exato está
na seção 13.

### P2-BLOCKER-05 — atomicidade e ator: resolvido

As cinco operações serão RPCs específicas `security definer`, com
`search_path = public, pg_temp`, tenant e ator derivados no servidor. Create e
cancel serão transacionais; não haverá composição por múltiplas chamadas REST.
Audit gravará `actor_user_id = auth.uid()` e outbox conterá apenas IDs, códigos
e metadata sanitizada.

O helper atual de audit não grava `actor_user_id`; portanto, as RPCs farão a
inserção sanitizada de audit diretamente em sua transação, incluindo esse
campo. Helpers existentes não recebem novos grants, não mudam de assinatura e
não são expostos diretamente.

## 6. Decisões vinculantes do gate documental

- Nome e telefone permanecem fora da Fase 2.
- `participantSlots` é inteiro, nunca array de pessoas; o servidor cria slots
  `1..N`.
- Request nasce `DRAFT` e slots nascem `OPEN`.
- Nenhum participant ou identity profile é criado.
- Não existe transição para `INVITATIONS_PENDING` nem expiração automática.
- Catálogo usa default-deny conforme `P2-BLOCKER-03`.
- Todas as cinco operações exigem `VERIFIED_ACCESS` habilitada no futuro.
- Create, cancel e listagem de catálogo exigem policy `ACTIVE`.
- List/get de requests próprias históricas não exigem policy `ACTIVE` atual,
  mas continuam exigindo feature habilitada.
- Ausência de policy nunca ativa defaults silenciosos.
- Edge Functions autenticadas chamam as RPCs com o JWT do usuário; não há
  escrita direta nas tabelas nem `service_role` como autorização de negócio.

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
- `VISITOR` proíbe `serviceTypeCode` e `serviceDescription` e não cria detalhe
  de serviço;
- `SERVICE_PROVIDER` exige `serviceTypeCode` e cria exatamente um detalhe de
  serviço;
- `serviceDescription` é obrigatória somente quando
  `requires_description = true`; caso contrário deve ser nula;
- `serviceTypeCode` é normalizado com `trim` e uppercase antes da validação;
- `serviceDescription`, `purpose` e `operationalNote` usam trim, convertem texto
  vazio em nulo, rejeitam caracteres de controle e normalizam quebras de linha;
- `serviceDescription` possui limite de 300 caracteres;
- `purpose` possui limite de 300 caracteres;
- `operationalNote` possui limite de 1000 caracteres;
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
inputFingerprint
actorUserId
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

| HTTP | SQLSTATE | Código | Situação |
|---:|---|---|---|
| 400 | `22023` | `REQUEST_PAYLOAD_INVALID` | JSON, tipo, chave desconhecida ou formato inválido |
| 401 | `28000` | `AUTHENTICATION_REQUIRED` | token ausente ou inválido |
| 403 | `P0001` | `FEATURE_DISABLED` | feature base desligada |
| 403 | `P0001` | `UNIT_NOT_AUTHORIZED` | vínculo MVP de morador não demonstrado |
| 404 | `P0001` | `REQUEST_NOT_FOUND` | request inexistente, de outro autor ou tenant |
| 409 | `P0001` | `IDEMPOTENCY_CONFLICT` | mesma chave com fingerprint diferente |
| 409 | `P0001` | `COMMAND_IN_PROGRESS` | mesma chave ainda em processamento |
| 409 | `P0001` | `REQUEST_STATE_CONFLICT` | cancelamento fora da transição permitida |
| 422 | `P0001` | `POLICY_NOT_AVAILABLE` | operação exige policy `ACTIVE` inexistente |
| 422 | `P0001` | `ACCESS_WINDOW_INVALID` | janela viola policy |
| 422 | `P0001` | `PARTICIPANT_LIMIT_INVALID` | quantidade viola policy |
| 422 | `P0001` | `SERVICE_TYPE_NOT_AVAILABLE` | tipo inativo, não habilitado ou incompatível |
| 500 | `XX000` | `INTERNAL_ERROR` | falha sanitizada, com correlation ID |

Ausência de identidade usa SQLSTATE `28000`. Erros de domínio usam SQLSTATE
`P0001` com código estável separado da mensagem. Falta de `EXECUTE` permanece
`42501`. Constraints `23503`, `23505` e `23514` ficam internas e são
normalizadas sem detalhes do schema.

### 9.5 Contratos finais das RPCs

Todas as assinaturas abaixo são conceituais e vinculantes para a futura
migration. Todas são `security definer`, usam `search_path = public, pg_temp`,
derivam `auth.uid()` e `current_user_condominium_id()` e recebem `EXECUTE`
somente para `authenticated` na assinatura exata. `PUBLIC`, `anon` e
`service_role` têm `EXECUTE` explicitamente revogado. Nenhuma RPC aceita
`actor_user_id`, `condominium_id`, policy, status ou fingerprint do cliente.

#### `verified_access_list_resident_service_types`

```sql
verified_access_list_resident_service_types(p_unit_id uuid)
returns table (
  service_type_code text,
  display_name text,
  requires_description boolean
)
```

- valida feature, vínculo MVP e tenant da unidade;
- exige policy `ACTIVE`; sem ela retorna `POLICY_NOT_AVAILABLE`;
- aplica catálogo default-deny e ordena por display name/código;
- não adquire lock e não usa idempotência;
- filtros são fixos: tipo global ativo e override do tenant habilitado;
- não revela catálogo ou unidade de outro tenant.

#### `verified_access_create_resident_request`

```sql
verified_access_create_resident_request(
  p_unit_id uuid,
  p_request_type text,
  p_service_type_code text,
  p_service_description text,
  p_access_starts_at timestamptz,
  p_access_ends_at timestamptz,
  p_purpose text,
  p_operational_note text,
  p_participant_slots integer,
  p_idempotency_key text,
  p_correlation_id text
) returns jsonb
```

- exige feature, vínculo MVP, policy `ACTIVE` e catálogo aplicável;
- trava o comando idempotente e a policy ativa selecionada;
- cria comando, request, detalhe opcional, slots, audit e outbox na mesma
  transação;
- retorna JSON com allowlist `requestId`, `requestStatus`, `unitId`,
  `accessStartsAt`, `accessEndsAt` e `participantLimit`;
- usa os códigos de 401/403/409/422 da seção 9.4;
- não cria participant e não realiza transição além de `DRAFT`/`OPEN`.

#### `verified_access_list_resident_requests`

```sql
verified_access_list_resident_requests(
  p_status text default null,
  p_request_type text default null,
  p_from timestamptz default null,
  p_to timestamptz default null,
  p_cursor_created_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 20
) returns table (
  id uuid,
  request_type text,
  status text,
  unit_id uuid,
  starts_at timestamptz,
  ends_at timestamptz,
  timezone text,
  participant_limit integer,
  slot_counts jsonb,
  service jsonb,
  created_at timestamptz
)
```

Retorno exato: `id`, `request_type`, `status`, `unit_id`, `starts_at`,
`ends_at`, `timezone`, `participant_limit`, `slot_counts` sanitizado,
`service` sanitizado ou nulo e `created_at`. Não retorna notas livres.

- exige feature, mas não policy `ACTIVE` atual;
- filtra obrigatoriamente tenant derivado e `requested_by_user_id = auth.uid()`;
- aceita somente os filtros declarados e limite `1..50`;
- pagina por `(created_at desc, id desc)`, sem lock ou idempotência;
- policy ausente não impede leitura histórica e nunca produz defaults.

#### `verified_access_get_resident_request`

```sql
verified_access_get_resident_request(p_request_id uuid)
returns jsonb
```

O JSON contém somente os campos do resumo e `slots`, cada slot restrito a
`id`, `slotNumber` e `status`.

- exige feature, mas não policy `ACTIVE` atual;
- aplica tenant e autor antes de retornar request, detalhe e slots;
- não adquire lock e não usa idempotência;
- request alheia, de outro tenant ou inexistente retorna `REQUEST_NOT_FOUND`;
- policy ausente não impede leitura histórica.

#### `verified_access_cancel_resident_request`

```sql
verified_access_cancel_resident_request(
  p_request_id uuid,
  p_idempotency_key text,
  p_reason_code text default 'RESIDENT_CANCELLED',
  p_correlation_id text default null
) returns jsonb
```

- exige feature e policy `ACTIVE`; ausência retorna `POLICY_NOT_AVAILABLE`;
- trava o comando, depois a request própria com `for update`;
- aceita cancelamento novo somente de request `DRAFT` cujos slots estejam todos
  `OPEN`; qualquer `RESERVED` ou `CLAIMED` retorna `REQUEST_STATE_CONFLICT` sem
  alteração parcial;
- cancela request e slots `OPEN`, grava audit/outbox e conclui o comando na
  mesma transação;
- retorna JSON com allowlist `requestId` e `requestStatus`;
- repetição equivalente já concluída retorna o resultado lógico anterior;
- request alheia ou de outro tenant retorna `REQUEST_NOT_FOUND`.

### 9.6 Contrato das Edge Functions

Cada uma das cinco Edge Functions valida bearer token, chama somente sua RPC
com o JWT do usuário e nunca usa `service_role` para regra de negócio. Elas:

- possuem JSON/query allowlist e rejeitam unknown fields;
- geram ou validam correlation ID técnico, fora do fingerprint;
- não registram body, `Authorization`, `purpose` ou `operationalNote`;
- limitam o request a 16 KiB e aplicam os limites de paginação;
- não habilitam CORS amplo sem justificativa versionada;
- não aceitam chamada `anon` e sanitizam mensagens SQL.

## 10. Regras de policy e negócio

Na mesma transação de criação, a RPC futura deve:

1. travar e validar o usuário e seu tenant;
2. validar vínculo de morador com a unidade;
3. aplicar as decisões MVP dos blockers 01 e 02, sem consultar campos de
   lifecycle inexistentes e sem usar `active_for_calls`;
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

Quando a feature estiver desligada, a operação falha com `FEATURE_DISABLED`
antes de consultar recurso do cliente. Quando a operação exigir policy e não
houver `ACTIVE`, falha com `POLICY_NOT_AVAILABLE`; nunca usa defaults
silenciosos. List/get históricos são a única exceção à exigência de policy.

## 11. Estados e transições nesta fase

### 11.1 Request

Estado inicial: `DRAFT`.

Transição autorizada pela Fase 2:

```text
DRAFT -> CANCELLED
```

Embora a state machine da Fase 1C permita cancelamentos em outros estados, a
RPC de morador da Fase 2 aceita novo cancelamento somente em `DRAFT`. Isso evita
operar fluxos de fases posteriores. `INVITATIONS_PENDING`, `IN_PROGRESS`,
`PARTIALLY_ELIGIBLE`, `ELIGIBLE` e `COMPLETED` não são produzidos nem alterados
nesta fase. `EXPIRED` depende de job futuro; a Fase 2 não expira requests.
`COMPLETED`, `CANCELLED` e `EXPIRED` permanecem terminais.

### 11.2 Slots

Estado inicial: `OPEN`, com `claimed_at = null`.

Transição autorizada pela Fase 2:

```text
OPEN -> CANCELLED
```

`RESERVED` e `CLAIMED` pertencem ao convite/cadastro da Fase 3 e não devem
existir em requests criadas pela Fase 2. Se forem encontrados no cancelamento,
a transação inteira falha com `REQUEST_STATE_CONFLICT`; não há cancelamento
parcial. `EXPIRED` depende de job futuro e não é produzido nesta fase.

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
- cancelamento da request `DRAFT` cancela todos os slots `OPEN` somente depois
  de confirmar que não existe slot `RESERVED` ou `CLAIMED`;
- callback ou handoff futuro nunca reabre request cancelada.
- repetição do cancelamento terminal com a mesma chave e fingerprint retorna o
  resultado anterior sem novo evento;
- nenhum participant é criado e nenhuma transição para
  `INVITATIONS_PENDING` ocorre.

## 12. Persistência e transação

### 12.1 Criação

Uma única RPC futura cria, em uma transação:

1. registro de idempotência em `verified_access_request_commands`;
2. `verified_access_requests` com tenant, autor, policy, timezone e status
   definidos pelo servidor;
3. `verified_access_service_request_details` somente para prestador;
4. N `verified_access_participant_slots` em `OPEN`;
5. audit `VERIFIED_ACCESS_REQUEST_CREATED`;
6. outbox `VERIFIED_ACCESS_REQUEST_CREATED`.

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

Eventos mínimos:

```text
VERIFIED_ACCESS_REQUEST_CREATED
VERIFIED_ACCESS_REQUEST_CANCELLED
```

Audit grava `actor_user_id = auth.uid()`, `condominium_id`, `request_id`, action
code e correlation ID. Não grava `purpose`, `operationalNote` ou conteúdo
pessoal. Payload permitido:

```json
{
  "requestId": "uuid",
  "requestType": "VISITOR",
  "slotCount": 2,
  "policyVersion": 3,
  "eventCode": "VERIFIED_ACCESS_REQUEST_CREATED"
}
```

Payload proibido inclui nome, telefone, unidade em texto livre, finalidade,
observação, documentos, PII, token, perfil, case, signal ou payload de provider.

Outbox contém apenas `request_id`, `condominium_id`, `unit_id`, `request_type`,
`participant_limit`, janela de acesso e event code. Não contém texto livre,
nome, telefone ou PII. Deduplication keys são vinculadas ao ID imutável do
comando idempotente:

```text
verified-access:command:{commandId}:request-created:v1
verified-access:command:{commandId}:request-cancelled:v1
```

Audit e outbox são gravados pela RPC de domínio, na mesma transação, nunca pela
Edge Function em chamadas separadas.

## 13. Idempotência e concorrência

Contrato futuro vinculante:

```sql
verified_access_request_commands (
  id uuid primary key,
  condominium_id uuid not null,
  actor_user_id uuid not null,
  command_type text not null,
  idempotency_key text not null,
  input_fingerprint text not null,
  request_id uuid null,
  status text not null,
  result_code text null,
  result_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null,
  completed_at timestamptz null
)
```

Constraints mínimas:

- `command_type in ('CREATE_REQUEST', 'CANCEL_REQUEST')`;
- `status in ('PROCESSING', 'COMPLETED')`;
- unique `(condominium_id, actor_user_id, command_type, idempotency_key)`;
- FK `condominium_id -> condominiums(id)`;
- FK composta `(actor_user_id, condominium_id) ->
  user_profiles(id, condominium_id)`;
- FK composta nullable `(request_id, condominium_id) ->
  verified_access_requests(id, condominium_id)`;
- `input_fingerprint` obrigatório e com formato/versão canônicos;
- `PROCESSING` exige `completed_at is null`;
- `COMPLETED` exige `request_id`, `result_code` e `completed_at`;
- `result_payload` deve ser objeto sanitizado com allowlist exata por comando:
  create `{requestId, requestStatus, participantLimit}` e cancel
  `{requestId, requestStatus}`;
- RLS habilitada e grants de tabela revogados de `PUBLIC`, `anon`,
  `authenticated` e `service_role`.

O payload nunca contém PII, observação, finalidade, nome, telefone, documento
ou biometria. A idempotency key é opaca, validada entre 16 e 128 caracteres e
não pode carregar dado pessoal.

Comportamento transacional:

- a RPC insere ou trava o comando e decide; a Edge Function apenas valida
  formato;
- mesma key, mesmo fingerprint e `COMPLETED` retorna o resultado anterior;
- mesma key com fingerprint divergente retorna `IDEMPOTENCY_CONFLICT`;
- mesma key em `PROCESSING` retorna `COMMAND_IN_PROGRESS`;
- falha de domínio faz rollback do comando, domínio, audit e outbox; nunca deixa
  `COMPLETED` sem domínio correspondente;
- criação do comando, domínio, audit e outbox ocorre na mesma transação;
- slots são criados com `generate_series(1, participant_limit)`;
- cancelamento trava comando e request em ordem estável;
- repetição não duplica audit nem outbox.

### 13.1 Fingerprint canônico

O servidor normaliza os valores, monta objeto com chaves em ordem fixa,
serializa JSON canônico e calcula SHA-256 com prefixo de versão. O fingerprint
é calculado pela RPC; nunca é aceito do cliente.

`CREATE_REQUEST` usa exclusivamente:

```text
unitId
requestType
serviceTypeCode normalizado ou null
serviceDescription normalizada ou null
accessStartsAt UTC
accessEndsAt UTC
purpose normalizado ou null
operationalNote normalizada ou null
participantSlots
```

`CANCEL_REQUEST` usa exclusivamente:

```text
requestId
reasonCode
```

Ficam fora do fingerprint: correlation ID, timestamp da tentativa,
`auth.uid()`, `condominiumId`, policy calculada, status calculado e a própria
idempotency key.

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
| Tabelas existentes | nenhum | nenhum | nenhum direto | manter matriz mínima já versionada |
| `verified_access_request_commands` | nenhum | nenhum | nenhum | nenhum |
| Cinco RPCs de morador | revogado | nenhum | `EXECUTE` nas assinaturas exatas | revogado; não é ator de negócio |
| Helpers internos | revogado | revogado | revogado | revogado |
| Edge Functions | n/a | proibido | JWT obrigatório | chamada interna não autoriza negócio |

RPCs são `security definer`, com `search_path = public, pg_temp`, validação de
`auth.uid()`, tenant e vínculo antes de qualquer leitura ou escrita. Nenhuma
policy `USING (true)` e nenhum grant de tabela é adicionado a `authenticated`.

## 17. Migrations e rollback futuros

Somente após `P2-GATE-EXECUTION-CONTRACT`, a execução poderá criar:

```text
supabase/migrations/20260720100000_verified_access_request_commands.sql
supabase/migrations/20260720101000_verified_access_resident_request_rpcs.sql
supabase/rollback/verified_access_phase_2_rollback.sql
```

Responsabilidades exatas:

1. `verified_access_request_commands`: tabela, tenant FKs, checks, unique,
   índices, RLS e REVOKEs default-deny;
2. `verified_access_resident_request_rpcs`: cinco RPCs, normalização,
   fingerprint, locks, transações, audit/outbox, REVOKEs e grants das
   assinaturas exatas;
3. rollback dedicado: revogar `EXECUTE`, remover as cinco RPCs, remover funções
   internas criadas exclusivamente pela Fase 2 caso existam, e por último
   remover `verified_access_request_commands`.

Uma terceira migration de helpers/constraints só poderá ser adicionada ao
contrato executável se uma necessidade indispensável for demonstrada na revisão
da implementação. Ela não integra a allowlist atual e não pode alterar lifecycle
de `unit_members`, `units` ou `condominiums`.

O rollback preserva todas as tabelas e dados das Fases 1A–1D, `persons`, Rede
Confia central e providers da Fase 1D. Não altera feature flags nem executa
operação remota.

## 18. Allowlist futura de arquivos

### 18.1 Allowlist exata da execução futura

```text
supabase/migrations/20260720100000_verified_access_request_commands.sql
supabase/migrations/20260720101000_verified_access_resident_request_rpcs.sql
supabase/rollback/verified_access_phase_2_rollback.sql
supabase/functions/verified-access-service-types-list/index.ts
supabase/functions/verified-access-service-types-list/index.test.ts
supabase/functions/verified-access-request-create/index.ts
supabase/functions/verified-access-request-create/index.test.ts
supabase/functions/verified-access-request-list/index.ts
supabase/functions/verified-access-request-list/index.test.ts
supabase/functions/verified-access-request-get/index.ts
supabase/functions/verified-access-request-get/index.test.ts
supabase/functions/verified-access-request-cancel/index.ts
supabase/functions/verified-access-request-cancel/index.test.ts
supabase/functions/_shared/verified-access/resident-requests/contracts.ts
supabase/functions/_shared/verified-access/resident-requests/auth.ts
supabase/functions/_shared/verified-access/resident-requests/http.ts
supabase/functions/_shared/verified-access/resident-requests/fingerprint.ts
supabase/tests/verified_access_phase_2.sql
supabase/tests/verified_access_phase_2_integration.psql
supabase/tests/verified_access_phase_2_runtime_roles.psql
.github/workflows/verified-access-phase-2.yml
supabase/config.toml
docs/product/verified-access/execution/CURRENT_TASK.md
docs/verified-access-phase-2-validation.md
```

`supabase/config.toml` pode somente registrar as cinco funções autenticadas. O
workflow é estritamente necessário porque não existe workflow da Fase 2.
Qualquer path adicional, inclusive terceira migration, exige revisão e alteração
do contrato executável antes da edição. UI, `apps/admin-web`, app Expo,
`persons` e providers da Fase 1D não estão autorizados.

## 19. Plano de testes

### 19.1 SQL/pgTAP

- command table, constraints, índices, RLS e grants;
- somente assinaturas exatas das cinco RPCs executáveis por `authenticated`;
- `PUBLIC`, `anon` e `service_role` sem EXECUTE;
- feature desligada e policy ausente;
- existência da linha `unit_members` como vínculo MVP;
- `active_for_calls = false` não bloqueia morador válido;
- ausência de campos de status em unit/condominium não é contornada nem
  consultada;
- vínculo de unidade/tenant e papéis não residentes;
- catálogo global inativo e override desabilitado/ausente;
- visitor sem detail e service com detail obrigatório;
- período, duração, antecedência e limites da policy;
- criação exata de N slots e sequência `1..N`;
- audit append-only, outbox imutável e payload sanitizado;
- comando `PROCESSING` retorna `COMMAND_IN_PROGRESS`;
- comando `COMPLETED` retorna resultado lógico anterior;
- mesma key/input retorna mesmo ID; fingerprint divergente retorna conflito;
- fingerprint é calculado no servidor e exclui campos proibidos;
- concorrência sobre a mesma key produz um único domínio;
- cancelamento repetido sem novos eventos;
- rollback transacional não deixa comando `COMPLETED` órfão;
- `actor_user_id` é derivado de `auth.uid()`;
- `service_role` não possui autorização de negócio;
- list/get histórico funciona sem policy `ACTIVE` atual;
- create/cancel e catálogo falham sem policy `ACTIVE`;
- nenhum participant, nome ou telefone é criado;
- purpose/note não aparecem em audit ou outbox;
- terminal não reabre;
- `persons` e domínio de rede sem dependência.

### 19.2 Integração SQL

- tenants A/B e usuários distintos;
- usuário sem perfil ou vínculo;
- unidade de outro condomínio;
- request de outro autor indistinguível de inexistente;
- criação visitante individual e múltipla;
- criação prestador e `OTHER`;
- cancelamento falha integralmente diante de slot `RESERVED` ou `CLAIMED`;
- repetição concorrente de create/cancel;
- rollback e reaplicação;
- preservação integral das Fases 1A, 1B, 1C e 1D.

### 19.3 Deno/Edge

- autenticação ausente/inválida;
- allowlist e payload desconhecido;
- mass assignment de todos os campos proibidos;
- normalização de datas e paginação;
- mapeamento SQLSTATE/HTTP;
- feature desligada sem enumeração;
- mocks sem rede externa e sem service_role como autorização;
- logs, erros e correlation IDs sem PII;
- logs não contêm body, Authorization, purpose ou operationalNote;
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
9. rollback 2 e verificação de preservação 1A–1D, inclusive providers;
10. reaplicação;
11. testes pós-reaplicação;
12. admin lint/build apenas como regressão, sem alterar admin-web.

Artifacts contêm somente logs sanitizados. Nenhuma chave local ou remota é
publicada.

## 20. Gates para autorização futura

`P2-BLOCKER-01` a `P2-BLOCKER-05` estão documentalmente resolvidos neste plano.
A Fase 2 continua não autorizada devido ao gate final pendente:

### P2-GATE-EXECUTION-CONTRACT

Exige cumulativamente:

- revisão humana deste contrato final;
- confirmação da allowlist exata de arquivos;
- migrations finais e ordem de rollback;
- contrato executável em `CURRENT_TASK.md`;
- testes SQL, integração, runtime roles e Deno autorizados;
- workflow CI com rollback, reaplicação e preservação 1A–1D;
- feature mantida desligada e nenhuma migration remota.

Qualquer mudança de produto, nova PII, lifecycle estrutural, terceira migration,
alteração de policy, habilitação de feature, migration remota, custo ou
integração externa reabre revisão documental e bloqueia a execução.

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
