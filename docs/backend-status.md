# Confia Interfone Digital - Backend Status

## Decisoes atuais

- Supabase continua sendo a base do MVP.
- Regras sensiveis de chamada ficam em RPCs transacionais no Postgres.
- A Edge Function `call-timeout-processor` fica responsavel apenas por validar o segredo do scheduler e chamar `process_expired_calls()`.
- O scheduler do GitHub Actions chama a Edge Function a cada minuto.

## Status oficiais

### `calls.status`

- `RINGING`
- `ANSWERED`
- `MISSED`
- `CANCELLED`

### `call_attempts.status`

- `RINGING`
- `ANSWERED`
- `NO_ANSWER`
- `FAILED`

Registros antigos com `TIMEOUT` devem ser migrados para `NO_ANSWER`.

## Segredos necessarios

### Supabase Edge Function

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `CRON_SECRET`
- `ADMIN_API_SECRET`

### GitHub Actions

- `SUPABASE_CRON_SECRET`

O valor de `SUPABASE_CRON_SECRET` precisa ser igual ao valor de `CRON_SECRET`.

## Contrato inicial para o frontend

- Portaria ligar para unidade: `rpc/start_portaria_call` com `{ "p_unit_id": "<uuid>" }`
- Unidade ligar para portaria: `rpc/start_unit_to_portaria_call` com `{ "p_unit_id": "<uuid>" }`
- Atender chamada: `rpc/answer_call` com `{ "p_call_id": "<uuid>", "p_user_id": "<auth.uid()>" }`
- Portaria atender chamada recebida: `rpc/answer_portaria_call` com `{ "p_call_id": "<uuid>" }`
- Cancelar chamada em andamento: `rpc/cancel_call` com `{ "p_call_id": "<uuid>", "p_reason": "opcional" }`
- Encerrar chamada: `rpc/end_call` com `{ "p_call_id": "<uuid>", "p_reason": "opcional" }`
- Compatibilidade temporaria: `rpc/start_call` chama internamente `start_portaria_call`.

O frontend nao deve escrever diretamente em `calls` ou `call_attempts`.

## Portaria

Cada condominio deve ter pelo menos um usuario/dispositivo de portaria em `portaria_devices`.

Esse usuario existe por tres motivos:

- casas/unidades chamarem a portaria;
- a portaria chamar casas/unidades;
- ambas as pontas verem quem esta ligando.

### Cadastro de condominio

Ao cadastrar um condominio, o fluxo administrativo deve tambem cadastrar ou convidar o usuario da portaria.

O backend espera:

- usuario criado no Supabase Auth;
- `user_profiles` vinculado ao `condominium_id` com role `PORTARIA`;
- `portaria_devices` ativo para esse `user_id`.

### RPC administrativa de onboarding

Use `admin_create_condominium_with_portaria(...)` depois de criar o usuario da portaria no Supabase Auth via Admin API.

Essa RPC e restrita a `service_role`.

Contrato:

```json
{
  "p_condominium_name": "Condominio Exemplo",
  "p_condominium_document": "00.000.000/0000-00",
  "p_portaria_user_id": "<auth.users.id>",
  "p_portaria_device_name": "Portaria Principal",
  "p_create_default_unit": false,
  "p_default_unit_type": "APARTMENT",
  "p_default_unit_block": "A",
  "p_default_unit_number": "101"
}
```

Ela cria:

- `condominiums`;
- `user_profiles` do usuario da portaria com role `PORTARIA`;
- `portaria_devices` ativo;
- opcionalmente uma unidade inicial.

### Edge Function administrativa

Use `admin-create-condominium` para fazer o fluxo completo em uma chamada protegida por `x-admin-secret`.

Endpoint:

```text
POST /functions/v1/admin-create-condominium
```

Headers:

```text
Content-Type: application/json
x-admin-secret: <ADMIN_API_SECRET>
```

Body:

```json
{
  "condominium_name": "Condominio Exemplo",
  "condominium_document": "00.000.000/0000-00",
  "portaria_email": "portaria@example.com",
  "portaria_password": "senha-inicial-forte",
  "portaria_device_name": "Portaria Principal",
  "create_default_unit": true,
  "default_unit_type": "APARTMENT",
  "default_unit_block": "A",
  "default_unit_number": "101"
}
```

Use `admin-create-unit-member` para cadastrar uma unidade e um morador, ou vincular um morador novo a uma unidade existente.

Endpoint:

```text
POST /functions/v1/admin-create-unit-member
```

Headers:

```text
Content-Type: application/json
x-admin-secret: <ADMIN_API_SECRET>
```

Body para criar unidade + morador:

```json
{
  "condominium_id": "<uuid>",
  "unit_type": "APARTMENT",
  "unit_block": "A",
  "unit_number": "102",
  "resident_email": "morador@example.com",
  "resident_password": "senha-inicial-forte",
  "member_type": "RESIDENT",
  "active_for_calls": true,
  "can_receive_calls": true,
  "can_make_calls": true
}
```

Body para adicionar morador a unidade existente:

```json
{
  "condominium_id": "<uuid>",
  "unit_id": "<uuid>",
  "resident_email": "morador2@example.com",
  "resident_password": "senha-inicial-forte",
  "call_order": 2
}
```

Resposta:

```json
{
  "unit_id": "<uuid>",
  "resident_user_id": "<uuid>",
  "unit_member_id": "<uuid>"
}
```

Use `admin-get-condominium` para consultar dados administrativos.

Listar condominios:

```text
GET /functions/v1/admin-get-condominium
```

Obter visao completa de um condominio:

```text
GET /functions/v1/admin-get-condominium?condominium_id=<uuid>
```

Headers:

```text
x-admin-secret: <ADMIN_API_SECRET>
```

A resposta de detalhe inclui:

- dados do condominio;
- dispositivos de portaria;
- unidades;
- membros de cada unidade;
- chamadas recentes.

## Auditoria de chamadas

A tabela `call_events` registra o ciclo de vida da chamada:

- `CALL_CREATED`
- `ATTEMPT_CREATED`
- `ATTEMPT_NO_ANSWER`
- `CALL_ANSWERED`
- `CALL_MISSED`
- `CALL_CANCELLED`
- `CALL_ENDED`

Eventos possuem:

- `condominium_id`
- `call_id`
- `event_type`
- `actor_user_id`
- `actor_type`
- `metadata`
- `created_at`

## Leituras para o app

RPCs autenticadas para o frontend/app:

- `get_current_user_context()`: retorna perfil, unidades vinculadas e dispositivos de portaria do usuario logado.
- `get_my_pending_calls()`: retorna chamadas pendentes para o morador e para a portaria.
- `get_my_call_history(p_limit)`: retorna historico de chamadas visivel para o usuario.

## Realtime

Realtime esta habilitado para:

- `calls`
- `call_attempts`
- `call_events`

O app deve assinar eventos filtrando pelo `condominium_id`, `unit_id` ou ids especificos de chamada conforme a tela.

Eventos recomendados:

- tela de chamada do morador: observar `call_attempts` e `calls`;
- tela da portaria: observar `calls` com `target_type = PORTARIA` e `call_events`;
- historico/auditoria: observar `call_events`.

## Segurança final do MVP

Tabelas sensiveis nao devem receber `insert`, `update` ou `delete` diretamente de `anon` ou `authenticated`.

Escritas de negócio devem passar por RPCs ou Edge Functions:

- chamadas: `start_portaria_call`, `start_unit_to_portaria_call`, `answer_call`, `answer_portaria_call`, `cancel_call`, `end_call`;
- administracao: Edge Functions com `x-admin-secret`;
- timeout: Edge Function `call-timeout-processor` com `x-cron-secret`.

Resposta:

```json
{
  "condominium_id": "<uuid>",
  "portaria_user_id": "<uuid>",
  "portaria_device_id": "<uuid>",
  "default_unit_id": "<uuid ou null>"
}
```

### Direcoes de chamada

#### Portaria para unidade

Use `start_portaria_call(p_unit_id)`.

Regras:

- `auth.uid()` precisa ter um `portaria_devices` ativo;
- o dispositivo precisa ter `can_make_calls = true`;
- a unidade precisa pertencer ao mesmo condominio;
- a chamada nasce com `origin_type = PORTARIA` e `target_type = UNIT`;
- o primeiro morador ativo da unidade recebe o primeiro `call_attempt`.

#### Unidade para portaria

Use `start_unit_to_portaria_call(p_unit_id)`.

Regras:

- `auth.uid()` precisa ser membro da unidade;
- o membro precisa ter `can_make_calls = true`;
- o backend escolhe o primeiro `portaria_devices` ativo do condominio;
- a chamada nasce com `origin_type = UNIT` e `target_type = PORTARIA`;
- chamadas para portaria nao criam `call_attempts` de morador.
