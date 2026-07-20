# Roadmap — Acesso Verificado

Atualizado em 20 de julho de 2026.

| Fase | Estado | Evidência/Gate |
|---|---|---|
| Fase 0 — descoberta | Concluída | stack, tenant e módulos mapeados |
| Fase 1A — fundação local | Mergeada | `84077aa18731f83d6e8cfa505b7d10dec2b89026` |
| Fase 1B — fundação inerte da Rede Confia | Mergeada | `957b01351f412ad75e353e99643cbe99446f9bff` |
| Fase 1C — invariantes e operações restritas | Mergeada | `f2f5296882df158481e44ea604a60b4e5bda2fce` |
| Fase 1D — contratos e providers fake | Implementada / validada / aguardando merge | PR draft #5, head `b3dcf005eb0438d6cad724de95eba2aa51d6f84b` |
| Fase 2 — solicitações do morador | Não iniciada | depende da Fase 1 |
| Fase 3 — convites e cadastro público | Não iniciada | tokens e criptografia |
| Fase 4 — identidade fake | Não iniciada | adapters/orquestração |
| Fase 5 — identidade real | Bloqueada | POC, contrato e privacidade |
| Fases 6/7 — background | Bloqueadas | jurídico, POC e RBAC |
| Fase 8 — credencial e portaria | Não iniciada | hardware e operação |
| Fase 9 — hardening e rollout | Não iniciada | gates de produção |

## Fase 1A entregue

- catálogo;
- policies V2;
- requests;
- detalhes de serviço;
- slots;
- perfis protegidos;
- participantes;
- elegibilidade;
- outbox;
- auditoria;
- RLS/grants;
- testes;
- rollback/reaplicação.

As migrations ainda não foram aplicadas remotamente.

## Fase 1B atual

Mergeada na `main` pelo squash commit
`957b01351f412ad75e353e99643cbe99446f9bff`, de forma inerte:

- network subjects;
- identifiers;
- links;
- security cases;
- signals;
- signal reviews;
- appeals;
- feature flags desligadas;
- RLS/grants default-deny;
- testes de não propagação;
- rollback e CI.

Não foi criado:

- HMAC real;
- API;
- RPC pública;
- busca;
- ativação operacional;
- bloqueio;
- UI.

## Fase 1C

A Fase 1C foi mergeada na `main` pelo squash commit
`f2f5296882df158481e44ea604a60b4e5bda2fce`.

O plano e a evidência permanecem em:

```text
docs/product/verified-access/phases/PHASE_1C.md
docs/verified-access-phase-1c-validation.md
```

As migrations 1A/1B/1C permanecem somente no repositório e não foram aplicadas
remotamente. As features permanecem desligadas.

## Fase 1D

A Fase 1D foi implementada e validada no PR draft #5, com head aprovado
`b3dcf005eb0438d6cad724de95eba2aa51d6f84b`:

- contratos internos para identity, background check e messaging;
- fakes sintéticos, determinísticos e isolados por instância e condomínio;
- idempotência, fingerprint canônico, clock virtual e uma tentativa por chamada;
- testes Deno de contrato, cenários, segurança e isolamento;
- nenhuma rede, filesystem, Supabase, SDK externo, secret ou PII;
- nenhuma decisão de domínio, integração real ou feature habilitada.

O PR permanece draft e aguarda decisão humana de merge. A Fase 2 não foi
iniciada nem autorizada.

## Migration drift

Há migrations históricas aplicadas remotamente e ausentes da `main`, documentadas em:

```text
docs/verified-access-phase-1a-repository-drift.md
```

O drift bloqueia o primeiro deployment remoto do Acesso Verificado até reconciliação explícita.

## Ambientes

```text
Vercel deploy != Supabase migration deploy
```

A Fase 1A foi mergeada e publicada no Vercel, mas o schema remoto não foi aplicado.
