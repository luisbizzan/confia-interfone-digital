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

## Policy V2 local

`verified_access_policies` modela configuracoes separadas para visitante e prestador:

- `visitor_identity_mode`
- `service_identity_mode`
- `visitor_background_mode`
- `service_background_mode`
- limites de participantes por tipo;
- janela, TTLs, timezone e antecedencia;
- referencias de aprovacao de privacidade, background e rede;
- `retention_settings` e `additional_settings` como objetos JSON;
- campos de rede inertes, sem tabelas de rede e sem `AUTO_DENY_NETWORK`.

Identidade de visitante ou prestador diferente de `DISABLED` exige `privacy_approval_reference`. Background diferente de `DISABLED` exige `background_approval_reference`. Rede diferente de `DISABLED`, ou hold de rede ligado, exige `network_approval_reference`. A migration nao ativa policies nem features.

## Dados sensiveis

Nenhuma coluna de CPF, nome completo, nome normalizado, data de nascimento, telefone, filiacao, numero de documento ou documento de empresa e armazenada em texto aberto.

A fundacao usa:

- campos `bytea` para ciphertext;
- HMAC local por condominio apenas para CPF, documento e telefone;
- versoes de chaves obrigatorias quando houver ciphertext ou HMAC;
- nenhum HMAC de rede;
- nenhum hash sem segredo;
- nenhum secret em migration;
- nenhuma descriptografia em SQL.

Nome, filiacao e nascimento ficam sem HMAC por minimizacao. CPF e documento continuam com unicidade local forte por condominio e versao de chave. Telefone pode ser compartilhado e nao e usado como chave unica de identidade; o HMAC de telefone possui apenas indice operacional nao unico. A tabela legada `persons` nao e usada nem alterada.

## Tenant isolation e invariantes

Todas as tabelas locais operacionais carregam `condominium_id`. As relacoes principais usam chaves compostas para impedir vinculos cruzados, incluindo:

- request-policy-version;
- request-unit;
- request-solicitante;
- detail-request;
- slot-request;
- participant-request-slot;
- participant-profile;
- evaluation-request-participant;
- evaluation-policy-version.

Triggers estruturais cobrem regras que dependem de outra linha:

- detalhes de servico so podem existir para request `SERVICE_PROVIDER`;
- `OTHER` exige `other_description` nao vazia;
- `requires_description` nao pode mudar de `false` para `true` se ja houver detalhes daquele tipo sem `other_description`;
- slot nao pode ultrapassar `participant_limit`;
- outbox permite atualizar apenas campos operacionais;
- audit bloqueia update, delete e truncate.

## JSON e campos livres

Checks de blacklist em JSON sao defesa em profundidade, nao garantia universal contra PII. `payload`, `metadata`, `input_snapshot_sanitized`, `retention_settings`, `additional_settings` e `network_signal_rules` devem ser objetos JSON.

Campos livres como `operational_notes`, `visit_reason`, `work_description`, `destination_area`, `company_name` e `other_description` possuem limites de tamanho e comentarios de finalidade. Eles nao devem receber documentos, antecedentes, biometria ou secrets.

## RLS e grants

Todas as tabelas novas tem RLS habilitada. A Fase 1A usa postura default-deny:

- `anon` nao le nem escreve diretamente;
- `authenticated` nao le tabelas sensiveis nem escreve diretamente;
- helper functions nao sao executaveis por `public`, `anon` ou `authenticated`;
- `service_role` recebe grants minimos por tabela;
- auditoria recebe apenas `SELECT` e `INSERT`.

## Rollback

O rollback local esta em `supabase/rollback/20260714100000_verified_access_phase_1a_rollback.sql`.

Ele remove somente objetos da Fase 1A, incluindo os indices auxiliares `ux_units_id_condominium_id` e `ux_user_profiles_id_condominium_id`, e preserva `persons`, `condominium_features`, `condominium_feature_enabled(uuid,text)` e a feature `INTERCOM`.

## Validacao

Validacoes esperadas:

```powershell
npm ci
npm run admin:lint
npm run admin:build
npx supabase db push --dry-run
npx supabase start
npx supabase db reset
npx supabase test db
psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -v ON_ERROR_STOP=1 -f supabase/tests/verified_access_phase_1a_integration.psql
npx supabase db lint
```

O workflow `.github/workflows/verified-access-phase-1a.yml` executa banco descartavel, rollback, reaplicacao e smoke test.

Run verde de validacao da Fase 1A:

- SHA: `7aeed1cf1f0027a8b3aa99fd4657ce842a70cc3a`
- Run: `29436074139`
- URL: `https://github.com/luisbizzan/confia-interfone-digital/actions/runs/29436074139`
- `database`: success
- `admin-web`: success

No job `database`, passaram migrations do zero, pgTAP com 239 testes, integracao SQL, runtime role checks, `supabase db lint`, rollback, verificacao de rollback, reaplicacao, pgTAP pos-reaplicacao e integracao pos-reaplicacao.

O Gate 1A-REVIEW acrescentou:

- constraint `verified_access_policies_privacy_approval_check`;
- indice nao unico `idx_verified_access_identity_profiles_phone_tenant_hmac`;
- funcao `verified_access_validate_service_type_requirement_change()`;
- trigger `verified_access_service_types_validate_requirement_change`;
- testes negativos e positivos para aprovacao de privacidade;
- testes de telefone compartilhado mantendo CPF/documento unicos;
- testes de protecao contra alteracao retroativa de catalogo que deixaria detalhes sem descricao.

O workflow publica apenas diagnostics sanitizados em falhas. O log bruto de `supabase start` nao e enviado como artifact.

## Fora desta fase

- Fase 1B: tabelas centrais da Rede Confia.
- Fase 1C: state machines completas, RPCs de policy e providers.
- Fase 1D: contratos internos e providers fake.
