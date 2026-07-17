# Fase 1C — invariantes, policies, audit e outbox

## 1. Status

Este documento é um plano para revisão humana. Ele não autoriza a implementação
da Fase 1C.

`CURRENT_TASK.md` permanece como `NO ACTIVE IMPLEMENTATION`. A execução da Fase
1C exige novo contrato versionado.

## 2. Objetivo Futuro

Completar as invariantes transacionais do Acesso Verificado local e da fundação
inerte da Rede Confia sem abrir operação de rede, providers, UI ou execução
remota.

Resultado esperado quando houver autorização futura:

```text
state machines protegidas
+ policies versionadas
+ audit append-only
+ outbox idempotente
+ rollback/reaplicação
+ CI verde
```

## 3. Escopo Futuro

- Máquinas de estado locais para requests, slots, identity profiles,
  participants, eligibility, audit e outbox.
- Máquinas de estado de network subjects, cases, signals e appeals.
- Validação de tenant nas relações locais.
- Policy ativa imutável.
- Uma policy ativa por condomínio.
- Validação de `network_signal_rules`.
- Bloqueio explícito de `AUTO_DENY_NETWORK`.
- Helpers transacionais de audit e outbox.
- RPCs restritas apenas para policy:
  - `verified_access_create_policy_draft`
  - `verified_access_activate_policy`
  - `verified_access_retire_policy`
- Reavaliação após revogação ou expiração.
- Testes de transição, autorização, idempotência, rollback e reaplicação.

## 4. Fora do Escopo

- Reportar ou substanciar case.
- Propor ou ativar signal.
- Appeal pública.
- Processador da outbox.
- Provider.
- UI.
- Convite.
- Solicitação do morador.
- Migration remota.
- Habilitação de feature.
- Fase 1D.

## 5. Regras Vinculantes

- `LOCAL_DENIED` não cria case ou signal.
- Case não substanciado não origina signal.
- Signal expirado ou revogado não afeta avaliação.
- `HOLD_CREDENTIAL` não vira `DENIED_MANUAL`.
- Policy ativa é imutável.
- Audit é append-only.
- Outbox é idempotente e sanitizada.
- Nenhuma função sensível fica aberta ao backoffice atual.
- Funções `security definer` somente quando justificadas, com `search_path`
  fixo e grants mínimos.

## 6. Segurança

- Manter RLS e grants mínimos.
- Não conceder acesso direto indevido a `PUBLIC`, `anon`, `authenticated` ou
  `service_role`.
- Não registrar PII em audit, outbox, logs ou mensagens de erro.
- Não criar HMAC real em SQL.
- Não criar API ou RPC operacional de rede.
- Não habilitar feature flags.

## 7. Gates

Antes de qualquer merge futuro da Fase 1C:

- CI verde.
- Rollback e reaplicação executados.
- Fase 1A preservada.
- Fase 1B preservada.
- Nenhum acesso direto indevido.
- Nenhuma PII central.
- Nenhuma feature habilitada.
- Nenhuma migration remota.
- Revisão humana concluída antes da execução.

## 8. Condição de Parada

Este plano deve permanecer documental até existir novo contrato em
`docs/product/verified-access/execution/CURRENT_TASK.md`.

Não prosseguir automaticamente a partir deste arquivo.
