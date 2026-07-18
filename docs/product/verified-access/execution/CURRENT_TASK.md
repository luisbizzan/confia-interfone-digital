# CURRENT TASK — VA-1C-INVARIANTS-POLICY-AUDIT-OUTBOX

## Estado

A Fase 1B foi concluída e mergeada na `main`.

```text
PR: https://github.com/luisbizzan/confia-interfone-digital/pull/3
Squash: 957b01351f412ad75e353e99643cbe99446f9bff
```

A Fase 1C está autorizada para execução futura neste contrato. Este arquivo
autoriza somente o escopo descrito abaixo, derivado de:

```text
docs/product/verified-access/phases/PHASE_1C.md
```

## Objetivo

Implementar as invariantes transacionais da Fase 1C para o Acesso Verificado e
a fundação inerte da Rede Confia:

- state machines protegidas por triggers validadores;
- policies versionadas e transacionais;
- policy `ACTIVE` imutável;
- uma policy `ACTIVE` por condomínio;
- helpers internos de audit/outbox;
- audit/outbox transacionais somente nas três RPCs de policy;
- rollback, reaplicação e CI completos;
- preservação integral das Fases 1A e 1B.

## Migrations Autorizadas

Criar exatamente três migrations, com timestamp real da execução:

```text
*_verified_access_state_machines.sql
*_verified_access_policy_rpcs.sql
*_verified_access_audit_outbox_helpers.sql
```

Criar exatamente um rollback dedicado:

```text
supabase/rollback/*_verified_access_phase_1c_rollback.sql
```

Não criar migrations de Fase 1D, providers, Edge Functions, views públicas,
jobs, cron, processador de outbox ou UI.

## State Machines

Autorizar funções e triggers de state machine para:

- `verified_access_requests`;
- `verified_access_participant_slots`;
- `verified_access_participants.registration_status`;
- `verified_access_participants.identity_status`;
- `verified_access_participants.background_status`;
- `verified_access_participants.network_status`;
- `verified_access_participants.eligibility_status`;
- `verified_access_network_subjects`;
- `verified_access_network_subject_identifiers`;
- `verified_access_network_subject_links`;
- `verified_access_network_security_cases`;
- `verified_access_network_signals`;
- `verified_access_network_appeals`.

Regras obrigatórias:

- triggers são `security invoker`;
- triggers apenas validam `OLD` e `NEW`;
- triggers não gravam audit;
- triggers não gravam outbox;
- triggers não chamam helpers `security definer`;
- triggers não elevam privilégio;
- transições proibidas devem falhar com `P0001`;
- valores fora do domínio existente continuam falhando com `23514`;
- FKs/tenant inválidos continuam falhando com `23503`;
- unicidade continua falhando com `23505`.

## Policies

Implementar:

- policy `ACTIVE` imutável;
- no máximo uma policy `ACTIVE` por condomínio;
- validação estrita de `network_signal_rules`;
- bloqueio de `AUTO_DENY_NETWORK`, `GLOBAL_DENIED`,
  `PERMANENT_BLACKLIST` e aliases em qualquer casing;
- dependências de features sem habilitar feature flag;
- referências obrigatórias de aprovação para identidade, background e rede;
- validação de payload sanitizado em JSON.

`verified_access_activate_policy` é o único caminho para substituir uma policy
`ACTIVE`.

`verified_access_retire_policy` aposenta somente policy `DRAFT`. Tentativa de
aposentar `ACTIVE` deve falhar com SQLSTATE `P0001` e reason:

```text
POLICY_ACTIVE_REPLACEMENT_REQUIRED
```

## RPCs Autorizadas

Criar somente estas RPCs:

```text
verified_access_create_policy_draft
verified_access_activate_policy
verified_access_retire_policy
```

### `verified_access_create_policy_draft`

Regras:

- recebe `p_policy jsonb` com allowlist estrita definida em
  `PHASE_1C.md`;
- rejeita payload que não seja objeto com `22023`;
- rejeita chave desconhecida com `22023`;
- rejeita campo proibido com `22023`;
- rejeita tipo inválido com `22023`;
- não usa `jsonb_populate_record` irrestrito;
- não permite mass assignment;
- `condominium_id` vem somente do parâmetro da RPC;
- `version` é calculada sob lock;
- `status` é sempre `DRAFT`;
- `schema_version` e `content_checksum` são definidos pelo servidor;
- actor vem somente dos parâmetros da RPC;
- `p_actor_id` não pode ser sobrescrito pelo JSON;
- base policy, quando informada, deve pertencer ao mesmo condomínio;
- copia de base policy deve usar a mesma allowlist.

### `verified_access_activate_policy`

Regras:

- único caminho para substituir `ACTIVE`;
- executa em uma única transação;
- bloqueia policies do condomínio;
- exige policy atual em `DRAFT`;
- aposenta a `ACTIVE` anterior e ativa a nova `DRAFT` na mesma transação;
- nunca deixa intervalo transacional sem `ACTIVE` quando já havia uma ativa;
- grava audit e outbox idempotente na mesma transação;
- não habilita feature flag.

### `verified_access_retire_policy`

Regras:

- executa em uma única transação;
- aposenta somente `DRAFT`;
- `ACTIVE` falha com `P0001` e reason
  `POLICY_ACTIVE_REPLACEMENT_REQUIRED`;
- `RETIRED` só é idempotente com a mesma idempotency key concluída;
- não permite condomínio sem policy ativa;
- grava audit e outbox idempotente apenas conforme evento de draft autorizado.

## Helpers de Audit e Outbox

Criar helpers internos para uso exclusivo das três RPCs de policy:

- `verified_access_write_audit_event(...)`;
- `verified_access_enqueue_outbox_event(...)`.

Regras obrigatórias:

- `security definer`;
- `search_path = public, pg_temp`;
- sem EXECUTE para `PUBLIC`;
- sem EXECUTE para `anon`;
- sem EXECUTE para `authenticated`;
- sem EXECUTE para `service_role`;
- chamados apenas internamente pelas três RPCs de policy;
- não chamados por triggers;
- payload somente com IDs, códigos e metadata sanitizada;
- nenhuma PII em audit/outbox;
- outbox idempotente por `deduplication_key`;
- audit append-only;
- falha de audit/outbox aborta a RPC na mesma transação.

## Grants e RLS

Manter postura default-deny:

- nenhum grant novo para `PUBLIC`;
- nenhum grant novo para `anon`;
- nenhum grant para `authenticated`;
- `service_role` sem grant central novo;
- helpers `security definer` sem EXECUTE direto para roles runtime;
- RPCs revogadas por padrão;
- qualquer grant técnico futuro deve ser mínimo, explícito e testado;
- não criar policy RLS `USING (true)`;
- tabelas centrais da Rede Confia continuam inacessíveis ao tenant.

## Testes Obrigatórios

Adicionar cobertura para:

- pgTAP de funções, triggers, RPCs, grants e `search_path`;
- state machines válidas e inválidas;
- SQLSTATEs definidos no plano;
- tenant isolation;
- allowlist estrita de `p_policy`;
- idempotência;
- uma `ACTIVE` por condomínio;
- policy `ACTIVE` imutável;
- ativação atômica;
- retirement apenas de `DRAFT`;
- audit append-only;
- outbox idempotente;
- payload sanitizado;
- falha de audit/outbox abortando RPC;
- roles `anon`, `authenticated` e `service_role`;
- rollback 1C;
- preservação das Fases 1A e 1B;
- reaplicação;
- smoke tests pós-reaplicação;
- `npm run admin:lint`;
- `npm run admin:build`.

## CI Obrigatório

Criar workflow:

```text
.github/workflows/verified-access-phase-1c.yml
```

O workflow deve executar:

- migrations do zero;
- pgTAP;
- integração SQL;
- runtime role checks;
- db lint;
- rollback 1C;
- verificação de rollback;
- reaplicação;
- pgTAP pós-reaplicação;
- integração pós-reaplicação;
- preservação 1A/1B;
- admin lint/build;
- diagnostics sanitizados, sem logs brutos de `supabase start`.

## Rollback

O rollback dedicado deve remover, em ordem segura:

1. grants das RPCs de policy;
2. RPCs de policy;
3. triggers de policy;
4. triggers de state machine locais;
5. triggers de state machine centrais;
6. funções de validação de policy;
7. funções de state machine locais;
8. funções de state machine centrais;
9. helpers de audit/outbox da Fase 1C;
10. índices/constraints auxiliares da Fase 1C.

O rollback deve preservar:

- tabelas e dados das Fases 1A e 1B;
- feature flags existentes, desligadas;
- `persons`;
- app Expo;
- objetos não relacionados.

## Fora de Escopo

Não implementar nesta fase:

- report case;
- substantiate case;
- propose signal;
- approve signal;
- activate signal;
- appeal pública;
- processador de outbox;
- provider real ou fake;
- Edge Function;
- UI;
- app Expo;
- solicitação do morador;
- convite;
- WhatsApp;
- QR Code;
- credencial;
- check-in/check-out;
- HMAC real;
- Fase 1D;
- migration remota;
- habilitação de feature.

## Condições de Parada

Parar e reportar antes de prosseguir se:

- a worktree não estiver limpa antes da implementação;
- `origin/main` não estiver no squash da Fase 1B esperado;
- alguma migration do Acesso Verificado tiver sido aplicada remotamente;
- a solução exigir alterar `persons`;
- a solução exigir alterar app Expo;
- a solução exigir habilitar features;
- a solução exigir grants diretos para tenant nas tabelas centrais;
- a solução exigir operação de case/signal/appeal;
- rollback/reaplicação não puderem ser validados;
- CI expuser chaves, URLs sensíveis ou logs brutos.

## Restrições Permanentes

- Não executar migrations remotas.
- Não habilitar feature flags.
- Não alterar `persons`.
- Não alterar o app Expo.
- Não implementar Fase 1D.
- Não criar API pública, busca global, provider, UI ou operação de rede fora do
  escopo acima.
