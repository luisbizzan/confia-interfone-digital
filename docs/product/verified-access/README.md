# Acesso Verificado — documentação canônica

Este diretório é a fonte de verdade de produto, domínio, segurança e execução do **Acesso Verificado para visitantes e prestadores** e da futura **Rede Confia**.

## Ordem de leitura

| Documento | Finalidade |
|---|---|
| [`DECISIONS.md`](DECISIONS.md) | Decisões vinculantes de produto e arquitetura |
| [`ROADMAP.md`](ROADMAP.md) | Estado das fases e gates |
| [`execution/CURRENT_TASK.md`](execution/CURRENT_TASK.md) | Contrato exato da execução autorizada |
| [`phases/PHASE_1B.md`](phases/PHASE_1B.md) | Fundação inerte da Rede Confia entregue na Fase 1B |
| [`phases/PHASE_1C.md`](phases/PHASE_1C.md) | Plano e escopo entregue da Fase 1C |
| [`phases/PHASE_1D.md`](phases/PHASE_1D.md) | Plano dos contratos e providers fake da Fase 1D |
| [`phases/PHASE_2.md`](phases/PHASE_2.md) | Plano das solicitações autenticadas do morador |
| [`phases/PHASE_3.md`](phases/PHASE_3.md) | Planejamento de convites e cadastro público |
| [`phases/PHASE_3B.md`](phases/PHASE_3B.md) | Contrato proposto do cadastro público da Fase 3B |
| [`SPECIFICATION.md`](SPECIFICATION.md) | Especificação funcional e técnica completa |
| [`SECURITY_AND_PRIVACY.md`](SECURITY_AND_PRIVACY.md) | Segurança, LGPD, retenção, revisão e contestação |
| [`INTEGRATIONS.md`](INTEGRATIONS.md) | Estratégia de providers e integrações |
| [`reference/PHASE_1_PLAN_V2.md`](reference/PHASE_1_PLAN_V2.md) | Plano de referência completo da Fase 1 |

## Precedência

```text
DECISIONS.md
    > execution/CURRENT_TASK.md
    > plano da fase em execução, quando autorizado
    > SPECIFICATION.md
    > documentos de referência/históricos
```

## Estado atual

- Fase 0 — descoberta: concluída.
- Fase 1A — fundação local: mergeada na `main`.
- Commit da Fase 1A: `84077aa18731f83d6e8cfa505b7d10dec2b89026`.
- Fase 1B — fundação inerte da Rede Confia: mergeada na `main`.
- Commit da Fase 1B: `957b01351f412ad75e353e99643cbe99446f9bff`.
- Fase 1C — invariantes, policies, audit e outbox: mergeada na `main`.
- Commit da Fase 1C: `f2f5296882df158481e44ea604a60b4e5bda2fce`.
- Fase 1D — mergeada na `main`.
- Commit da Fase 1D: `4284085959e185892f00c77dd89138838ba1dcdb`.
- Fase 2 — solicitações autenticadas do morador: mergeada na `main`.
- Commit da Fase 2: `a464de1175ae924644cfc2aa71eab7f27cc61cd5`.
- Fase 3A — convites locais: mergeada na `main`.
- Commit da Fase 3A: `4b4c24e3d85669acbcfb439eb7bcfd544beb2114`.
- Fase 3B — cadastro público web: planejada, em revisão humana e não
  autorizada para implementação.
- Fase 3C — hardening: não autorizada.
- Nenhuma migration do Acesso Verificado foi aplicada ao Supabase remoto.
- Todas as features permanecem desligadas.
- O deploy Vercel do merge é independente das migrations Supabase.

## Evidências históricas

Continuam em:

- `docs/verified-access-phase-1a.md`
- `docs/verified-access-phase-1a-validation.md`
- `docs/verified-access-phase-1a-repository-drift.md`
- `docs/verified-access-phase-1c-validation.md`
- `docs/adr/20260714-verified-access-local-foundation.md`

## Regra operacional

Uma fase só pode ser executada quando estiver explicitamente autorizada por `execution/CURRENT_TASK.md`.
