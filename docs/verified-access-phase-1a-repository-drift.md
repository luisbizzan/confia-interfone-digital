# Acesso Verificado - Drift de migrations

Data: 2026-07-15

Fonte: diagnostico sanitizado com `git ls-files`, `git ls-files --others --exclude-standard`, `npx supabase migration list` e `npx supabase db push --dry-run`.

## Resumo

`origin/main` nao contem quatro migrations que aparecem na checkout original local e ja constam como aplicadas no historico remoto de migrations. Essas migrations nao fazem parte da Fase 1A do Acesso Verificado e nao foram incluidas nesta branch.

As migrations da Fase 1A (`20260714100000` e `20260714101000`) estao presentes nesta branch e aparecem como pendentes no historico remoto. Por isso foram corrigidas diretamente antes de merge, sem criar migration corretiva posterior.

## Tabela de drift

| Migration | Presente na checkout original | Presente em `origin/main` | Presente no historico remoto | Depende da Fase 1A | Risco de rebuild | Acao recomendada | Blocker desta branch |
|---|---:|---:|---:|---:|---|---|---:|
| `20260526090000_add_app_version_policies.sql` | Sim, untracked | Nao | Sim | Nao | Alto se reconstruir banco somente de `origin/main`, pois o remoto tem migration sem arquivo versionado | Resolver em branch propria de reconciliacao de migrations | Nao |
| `20260606093000_add_decline_call.sql` | Sim, untracked | Nao | Sim | Nao | Alto se reconstruir banco somente de `origin/main` | Resolver em branch propria de reconciliacao de migrations | Nao |
| `20260606133000_add_messaging_module.sql` | Sim, untracked | Nao | Sim | Nao | Alto se reconstruir banco somente de `origin/main` | Resolver em branch propria de reconciliacao de migrations | Nao |
| `20260606140500_schedule_message_attachment_cleanup.sql` | Sim, untracked | Nao | Sim | Nao | Alto se reconstruir banco somente de `origin/main` | Resolver em branch propria de reconciliacao de migrations | Nao |
| `20260714100000_verified_access_local_foundation.sql` | Sim | Sim nesta branch | Nao | Sim | Sem drift remoto; pendente | Revisar, testar em banco descartavel e aplicar apenas via fluxo aprovado posterior | Nao |
| `20260714101000_verified_access_local_security.sql` | Sim | Sim nesta branch | Nao | Sim | Sem drift remoto; pendente | Revisar, testar em banco descartavel e aplicar apenas via fluxo aprovado posterior | Nao |

## Observacoes

- Nenhuma migration remota foi executada nesta sprint.
- O comando `db push --dry-run` na checkout original listou somente as duas migrations da Fase 1A como pendentes.
- O drift antigo e relevante para reproducibilidade global do banco, mas nao e dependencia funcional da Fase 1A.
- Esta branch nao deve incorporar os quatro arquivos antigos automaticamente para nao misturar funcionalidades.
