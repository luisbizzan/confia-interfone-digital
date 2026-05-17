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

Base da Fase 2:

- Navegacao responsiva com sidebar no desktop e drawer no mobile
- Rotas iniciais: dashboard, condominios, unidades, moradores, chamadas, auditoria e configuracoes
- Componentes reutilizaveis: metric card, page header, status chip, empty state e lista responsiva
- Rota server-side inicial: `/api/admin/condominiums`
- Wrapper server-side para a Edge Function `admin-get-condominium`, mantendo `ADMIN_API_SECRET` fora do browser

Base da Fase 3:

- Tela real de condominios consumindo `/api/admin/condominiums`
- Criacao de condominio via `/api/admin/condominiums/create`
- Formulario de onboarding com usuario da portaria e dispositivo vinculado
- Opcao de criar unidade padrao durante o cadastro
- Tratamento de loading, erro e validacao sem expor `ADMIN_API_SECRET` no browser

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
