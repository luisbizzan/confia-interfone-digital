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

Base da Fase 4:

- Tela real de unidades por condominio consumindo `/api/admin/condominiums/[id]`
- Tela real de moradores por condominio usando o mesmo overview administrativo
- Criacao de unidade + morador pela rota `/api/admin/unit-members/create`
- Vinculo de morador a unidade existente ou criacao de nova unidade no mesmo formulario
- Configuracoes iniciais de chamada: ativo, recebe chamadas, liga para portaria e ordem

Base da Fase 5:

- Tela real de chamadas por condominio usando `recent_calls`
- Metricas operacionais: recentes, tocando, atendidas e perdidas
- Historico recente com fluxo, unidade, status e data
- Atualizacao automatica da tela de chamadas a cada 20 segundos

Base da Fase 6:

- Tela de auditoria MVP com eventos operacionais derivados das chamadas recentes
- Tela de configuracoes com health check administrativo em `/api/admin/health`
- Checklist de fechamento MVP do backoffice
- Validacao de ambiente sem expor segredos no browser

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
