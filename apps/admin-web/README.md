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

## Fase 2

A base reutilizavel do backoffice ja inclui:

- Shell responsivo com menu lateral e drawer mobile
- Paginas iniciais para todos os modulos operacionais
- Cards de metrica, estados vazios, chips de status e listas responsivas
- Rota interna `/api/admin/condominiums` para chamar o backend sem expor segredo no browser
