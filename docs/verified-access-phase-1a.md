# Acesso Verificado - Fase 1A

Data: 2026-07-14

Esta fase cria somente a fundacao local do dominio Acesso Verificado no Supabase. Ela nao disponibiliza telas, convites, WhatsApp, QR Code, credenciais, check-in/check-out, Edge Functions publicas, providers reais ou tabelas centrais da Rede Confia.

## Objetos criados

- `verified_access_service_types`
- `verified_access_condominium_service_types`
- `verified_access_policies`
- `verified_access_requests`
- `verified_access_service_request_details`
- `verified_access_participant_slots`
- `verified_access_identity_profiles`
- `verified_access_participants`
- `verified_access_eligibility_evaluations`
- `verified_access_outbox_events`
- `verified_access_audit_events`

## Features

As features sao cadastradas no mecanismo existente `condominium_features`:

- `VERIFIED_ACCESS`
- `VERIFIED_ACCESS_BACKGROUND_CHECK`

As migrations deixam ambas desligadas para todos os condominios existentes.

## Dados sensiveis

Nenhuma coluna de CPF, nome completo, nome normalizado, data de nascimento, telefone, filiacao, numero de documento ou documento de empresa e armazenada em texto aberto. A fundacao usa:

- campos `bytea` para ciphertext;
- campos de HMAC/fingerprint locais;
- versoes de chaves;
- nenhum secret em migration;
- nenhuma descriptografia em SQL.

A tabela legada `persons` nao e usada nem alterada.

## Tenant isolation

Todas as tabelas locais operacionais carregam `condominium_id`. As relacoes principais usam chaves compostas com `condominium_id` para impedir vinculos cruzados entre tenants, incluindo request-policy, request-unit, request-solicitante, detail-request, slot-request, participant-slot, participant-profile e evaluation-participant.

## RLS e grants

Todas as tabelas novas tem RLS habilitada. A Fase 1A usa postura default-deny:

- `anon` nao le nem escreve diretamente;
- `authenticated` nao escreve diretamente;
- dados sensiveis nao possuem `SELECT` direto para usuarios do condominio;
- acesso operacional devera ser exposto por RPCs em fases futuras.

## Rollback

O plano de rollback local esta em `supabase/rollback/20260714100000_verified_access_phase_1a_rollback.sql`.

## Validacao

Validacoes esperadas:

```powershell
npx supabase db push --dry-run
npm run admin:lint
npm run admin:build
```

Quando houver banco local descartavel, executar tambem o teste SQL:

```powershell
psql "$env:SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/verified_access_phase_1a.sql
```

## Fora desta fase

- Fase 1B: tabelas centrais da Rede Confia.
- Fase 1C: state machines, RPCs de policy, helpers transacionais e invariantes avancados.
- Fase 1D: contratos internos e providers fake.
