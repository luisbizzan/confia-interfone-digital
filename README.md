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

Base da Fase 7:

- Login do backoffice com sessao HttpOnly
- Perfis `ADMIN` e `CONSULTOR` por `BACKOFFICE_USERS_JSON`
- Middleware protegendo paginas e APIs internas
- APIs administrativas validando sessao server-side
- Criacao liberada para `ADMIN` e `CONSULTOR`; futuras exclusoes devem exigir `ADMIN`
- Tela de Portaria com dispositivo, status e login do usuario usado no app modo portaria

## Fluxos Principais

- Edge Function administrativa: `admin-create-condominium`
- Edge Function administrativa: `admin-create-unit-member`
- Edge Function administrativa: `admin-get-condominium`
- Onboarding administrativo: `admin_create_condominium_with_portaria`
- Portaria para unidade: `start_portaria_call`
- Unidade para portaria: `start_unit_to_portaria_call`
- Unidade para unidade: `start_unit_to_unit_call`
- Morador atende chamada da unidade: `answer_call`
- Portaria atende chamada recebida: `answer_portaria_call`
- Cancelar chamada: `cancel_call`
- Encerrar chamada: `end_call`
- Contexto do usuario: `get_current_user_context`
- Chamadas pendentes: `get_my_pending_calls`
- Historico de chamadas: `get_my_call_history`
- Realtime: `calls`, `call_attempts`, `call_events`
- Scheduler de timeout: `call-timeout-processor` chamando `process_expired_calls`
- O historico do app (`get_my_call_history`) e escopado ao usuario logado: unidades do morador ou dispositivo de portaria.
- Push notifications:
  - tabela `app_push_tokens`;
  - RPC `register_app_push_token`;
  - RPC `unregister_app_push_token`;
  - Edge Function `send-call-notification`.

## Regra de Ocupacao

O backend bloqueia nova chamada quando o destino operacional ja esta ocupado:

- portaria em `RINGING` ou `ANSWERED` bloqueia outra chamada para a portaria;
- unidade em `RINGING` ou `ANSWERED` bloqueia outra chamada para essa unidade;
- uma unidade que ja esta em chamada tambem nao inicia nova chamada;
- uma portaria que ja esta em chamada tambem nao inicia nova chamada.

Mensagens esperadas no app:

- `A portaria esta em atendimento. Tente novamente em alguns minutos.`
- `Esta unidade esta em atendimento. Tente novamente em alguns minutos.`
- `Sua unidade esta em atendimento. Encerre a chamada atual antes de iniciar outra.`

## Diagnostico de Chamadas

Eventos operacionais enviados pelo app ficam em `app_call_diagnostics`.

Essa tabela ajuda a investigar testes com multiplos celulares, registrando:

- clique/inicio da acao;
- sucesso ou erro da RPC;
- duracao em milissegundos;
- `call_id`, unidade de origem e destino;
- perfil do usuario e plataforma do app;
- mensagem de erro retornada ao usuario.

## Push Notifications

A base de notificacoes usa Expo Push Service para Android e iOS.

Fluxo atual:

- o app registra o `ExpoPushToken` apos login;
- o backend armazena o token em `app_push_tokens`;
- ao criar chamada, o app chama `send-call-notification` com o `call_id`;
- a Edge Function valida a chamada, encontra os destinatarios e envia a notificacao;
- se nao houver token cadastrado, o fluxo de chamada segue normalmente.

Pendencias para producao:

- configurar FCM V1 no Android;
- configurar APNs no iOS;
- validar push em segundo plano com APK/loja;
- processar receipts do Expo para limpar tokens invalidos.

Diagnostico:

- o app grava `push_registration` em `app_call_diagnostics`;
- a Edge Function grava `push_notification_dispatch` em `app_call_diagnostics`;
- esses eventos permitem separar falha de token, ausencia de destinatario, falha de envio Expo e falha de entrega Android/iOS.
- a Edge Function tambem registra retornos antecipados relevantes, como chamada nao encontrada, chamada que deixou de tocar e usuario sem permissao para disparar a notificacao.
- a Edge Function aceita formatos alternativos de payload de chamada (`call_id`, `callId` ou `body.call_id`) para tolerar diferencas do cliente Supabase no app nativo.
- se o valor vier serializado de forma nao padrao, a Edge Function procura um UUID valido dentro do payload antes de rejeitar o envio.
- como fallback operacional, se o payload nao trouxer UUID legivel, a Edge Function busca uma chamada `RINGING` recente do usuario autenticado antes de desistir.
- em Android, ticket `InvalidCredentials` do Expo significa que a credencial FCM V1 ainda precisa ser configurada no Expo/EAS para entrega real em background.
- a credencial FCM V1 Android foi vinculada no Expo/EAS em 25/05/2026; novos testes devem confirmar tickets Expo sem `InvalidCredentials`.
- em 25/05/2026 a entrega em background foi confirmada em Android.
- a Edge Function envia chamadas no canal `incoming-calls-v2` com som `call_ringtone.wav`; o APK precisa conter esse som e registrar o mesmo canal.
- notificacao comum toca uma vez; chamada persistente estilo WhatsApp/Telegram depende de camada nativa propria.
