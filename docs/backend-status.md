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

### GitHub Actions

- `SUPABASE_CRON_SECRET`

O valor de `SUPABASE_CRON_SECRET` precisa ser igual ao valor de `CRON_SECRET`.

## Contrato inicial para o frontend

- Iniciar chamada: `rpc/start_call` com `{ "p_unit_id": "<uuid>" }`
- Atender chamada: `rpc/answer_call` com `{ "p_call_id": "<uuid>", "p_user_id": "<auth.uid()>" }`

O frontend nao deve escrever diretamente em `calls` ou `call_attempts`.
