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
