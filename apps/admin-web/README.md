# Backoffice Web

Aplicacao administrativa do Confia Interfone Digital.

## Comandos

```powershell
npm run dev
npm run lint
npm run build
```

No monorepo, tambem e possivel executar pela raiz:

```powershell
npm run admin:dev
npm run admin:lint
npm run admin:build
```

## Ambiente

Copie `.env.example` para `.env.local` e preencha:

- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`
- `ADMIN_API_SECRET`
- `BACKOFFICE_SESSION_SECRET`
- `BACKOFFICE_USERS_JSON`

## Fase 2

A base reutilizavel do backoffice ja inclui:

- Shell responsivo com menu lateral e drawer mobile
- Paginas iniciais para todos os modulos operacionais
- Cards de metrica, estados vazios, chips de status e listas responsivas
- Rota interna `/api/admin/condominiums` para chamar o backend sem expor segredo no browser

## Fase 3

A tela de condominios ja usa dados reais do backend:

- Listagem pela rota interna `/api/admin/condominiums`
- Criacao pela rota interna `/api/admin/condominiums/create`
- Formulario com dados do condominio, email/senha da portaria e nome do dispositivo
- Criacao opcional de unidade padrao
- Status de carregamento, erro e validacao

## Fase 4

Unidades e moradores ja usam dados reais do backend:

- Listagem por condominio pela rota `/api/admin/condominiums/[id]`
- Criacao de unidade e morador pela rota `/api/admin/unit-members/create`
- Dialog compartilhado para criar nova unidade ou vincular morador a unidade existente
- Configuracao inicial de chamada do morador

## Fase 5

Chamadas ja possui visao operacional:

- Listagem por condominio usando `recent_calls`
- Metricas de chamadas recentes, tocando, atendidas e perdidas
- Atualizacao automatica a cada 20 segundos

## Fase 6

Fechamento MVP do backoffice:

- Auditoria MVP baseada nas chamadas recentes
- Health check administrativo em `/api/admin/health`
- Checklist de configuracao e prontidao

## Fase 7

Seguranca e operacao real:

- Login em `/login`
- Sessao HttpOnly assinada no servidor
- Perfis `ADMIN` e `CONSULTOR`
- Middleware protegendo paginas e APIs
- Rotas `/api/admin/*` exigindo sessao valida
- Tela `/portaria` mostrando o login/dispositivo da portaria por condominio
