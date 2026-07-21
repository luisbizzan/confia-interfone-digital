# CURRENT TASK — VA-P3A-LOCAL-INVITATIONS

## Objetivo

Executar exclusivamente a Fase 3A definida na seção 26 de
`docs/product/verified-access/phases/PHASE_3.md`: convite local, token opaco,
operações autenticadas do morador e mensageria fake.

## Base e branch

- Base: `a464de1175ae924644cfc2aa71eab7f27cc61cd5`.
- Branch: `agent/verified-access-phase-3`.
- PR: <https://github.com/luisbizzan/confia-interfone-digital/pull/7>.

## Entrega autorizada

- criar exatamente as duas migrations `20260721100000` e `20260721101000`;
- criar `verified_access_invitations` e
  `verified_access_invitation_commands` com RLS default-deny;
- criar exatamente quatro RPCs autenticadas e quatro Edge Functions;
- gerar token de 256 bits na Edge e persistir somente hash SHA-256 `v1`;
- manter slots `OPEN` e não criar participant;
- adaptar somente o contexto do MessagingProvider para alvo de convite;
- usar somente o fake existente, após commit e sem retry interno;
- criar testes SQL, Deno, runtime roles, rollback e workflow dedicados;
- atualizar o rollback cumulativo legado da Fase 1A;
- criar `docs/verified-access-phase-3a-validation.md`.

## Invariantes

- um convite ativo (`PENDING` ou `SENT`) por slot;
- request, slot, convite, comando e ator no mesmo tenant;
- request própria e vínculo RESIDENT derivados no servidor;
- feature obrigatória em todas as operações;
- policy `ACTIVE` obrigatória para ISSUE e RESEND;
- token bruto ausente de banco, command, audit, outbox, logs e erros;
- idempotência persistente para `ISSUE`, `RESEND` e `REVOKE`;
- replay idempotente não repete preview nem fake;
- audit/outbox sanitizados e na mesma transação do domínio;
- grants mínimos por assinatura exata, sem acesso direto às tabelas.

## Token e fake

O token usa 32 bytes aleatórios, base64url sem padding e hash persistido
`v1:<sha256-hex>`. A validade é limitada a 24 horas e ao fim da request. O fake
recebe contexto por `participantSlotId` e `invitationId`, roda somente após o
commit e não cria participant. Falha do fake mantém `PENDING`; retry operacional
usa RESEND, nova chave idempotente e token rotacionado.

## Allowlist

A allowlist exata e vinculante é a seção 26.5 de `PHASE_3.md`. Qualquer path
adicional exige parada antes da alteração.

## Testes e CI

Executar migrations do zero, pgTAP, integração 1A a 3A, runtime roles, Deno
fmt/lint/check/test, db lint, rollback 3A, preservação 1A a 2, reaplicação,
smokes pós-reaplicação e admin-web lint/build. O workflow 1A deve remover 3A
antes de 2, 1C, 1B e 1A.

## Fora de escopo

- Fases 3B e 3C;
- participant e identity profile;
- PII, telefone ou destino real;
- endpoint, sessão ou página pública;
- provider ou integração real;
- worker externo, cron ou DLQ;
- Expo, portaria e UI;
- migration remota e feature habilitada;
- merge, mark ready e force-push.

## Fechamento

Somente após todos os gates verdes, registrar evidências, fechar esta tarefa
como `CURRENT TASK — NO ACTIVE IMPLEMENTATION`, fazer push e manter o PR draft.
