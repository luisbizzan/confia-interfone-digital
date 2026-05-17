# Confia Interfone Digital

Backend Supabase para o MVP do Confia Interfone Digital.

## CLI

Este projeto usa o Supabase CLI como dependencia local:

```powershell
npm install
npx supabase --version
```

Comandos principais:

```powershell
npx supabase link --project-ref uvdwoisdcikzhqjwbhog
npx supabase db push
npx supabase functions deploy call-timeout-processor --no-verify-jwt
```

## Backoffice Web

O backoffice fica em `apps/admin-web`.

```powershell
npm install
npm run admin:dev
```

Stack inicial:

- Next.js
- TypeScript
- MUI
- TanStack Query
- Supabase JS
- React Hook Form
- Zod

## Fluxos Principais

- Edge Function administrativa: `admin-create-condominium`
- Edge Function administrativa: `admin-create-unit-member`
- Edge Function administrativa: `admin-get-condominium`
- Onboarding administrativo: `admin_create_condominium_with_portaria`
- Portaria para unidade: `start_portaria_call`
- Unidade para portaria: `start_unit_to_portaria_call`
- Morador atende chamada da unidade: `answer_call`
- Portaria atende chamada recebida: `answer_portaria_call`
- Cancelar chamada: `cancel_call`
- Encerrar chamada: `end_call`
- Contexto do usuario: `get_current_user_context`
- Chamadas pendentes: `get_my_pending_calls`
- Historico de chamadas: `get_my_call_history`
- Realtime: `calls`, `call_attempts`, `call_events`
- Scheduler de timeout: `call-timeout-processor` chamando `process_expired_calls`
