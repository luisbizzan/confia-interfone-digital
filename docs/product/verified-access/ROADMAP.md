# Roadmap — Acesso Verificado

Atualizado em 16 de julho de 2026.

| Fase | Estado | Evidência/Gate |
|---|---|---|
| Fase 0 — descoberta | Concluída | stack, tenant e módulos mapeados |
| Fase 1A — fundação local | Mergeada | `84077aa18731f83d6e8cfa505b7d10dec2b89026` |
| Fase 1B — fundação inerte da Rede Confia | Autorizada | branch `agent/verified-access-phase-1b` |
| Fase 1C — invariantes e operações restritas | Não iniciada | depende da 1B |
| Fase 1D — contratos e providers fake | Não iniciada | depende das portas aprovadas |
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

Criar, de forma inerte:

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

Não criar:

- HMAC real;
- API;
- RPC pública;
- busca;
- ativação operacional;
- bloqueio;
- UI.

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
