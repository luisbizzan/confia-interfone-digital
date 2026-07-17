# Fase 1C — invariantes, policies, audit e outbox

## 1. Status

Este documento é um plano executável para revisão humana. Ele detalha a futura
Fase 1C, mas não autoriza sua implementação.

`CURRENT_TASK.md` permanece como `NO ACTIVE IMPLEMENTATION`. A execução da Fase
1C exige novo contrato versionado, com branch, base, migrations, testes e gates
explicitamente autorizados.

## 2. Objetivo

Completar as invariantes transacionais do Acesso Verificado local e da fundação
inerte da Rede Confia sem abrir operação de rede, providers, UI, busca global ou
migration remota.

Resultado esperado da Fase 1C, quando autorizada:

```text
state machines protegidas
+ policies versionadas e transacionais
+ audit append-only por helper
+ outbox idempotente por helper
+ rollback/reaplicação completos
+ CI verde preservando Fases 1A e 1B
```

## 3. Inventário das Invariantes Existentes

### 3.1 Fase 1A — fundação local

Objetos existentes:

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

Invariantes já implementadas:

- Features `VERIFIED_ACCESS` e `VERIFIED_ACCESS_BACKGROUND_CHECK` cadastradas e
  desligadas.
- `persons` não é reutilizada nem alterada.
- PII local em `verified_access_identity_profiles` usa ciphertext/HMAC local;
  não há CPF, documento, telefone, nome, filiação ou nascimento em texto aberto.
- CPF e documento possuem unicidade local por condomínio e versão de chave.
- Telefone é lookup local não único; duas pessoas do mesmo condomínio podem
  compartilhar telefone.
- Todas as tabelas locais operacionais carregam `condominium_id`.
- Relações críticas usam FKs compostas para tenant isolation:
  request-policy-version, request-unit, request-solicitante, detail-request,
  slot-request, participant-request-slot, participant-profile,
  evaluation-request-participant e evaluation-policy-version.
- `verified_access_policies.status` aceita somente `DRAFT`, `ACTIVE`,
  `RETIRED`.
- `visitor_identity_mode` e `service_identity_mode` aceitam somente
  `DISABLED`, `OPTIONAL`, `REQUIRED`.
- Identidade diferente de `DISABLED` exige `privacy_approval_reference`.
- Background diferente de `DISABLED` exige `background_approval_reference`.
- Rede diferente de `DISABLED`, ou hold de rede ligado, exige
  `network_approval_reference`.
- `network_identity_mode` aceita somente `DISABLED`, `EVALUATE_ONLY`.
- `network_signal_rules` deve ser objeto JSON.
- `AUTO_DENY_NETWORK`, `GLOBAL_DENIED` e `PERMANENT_BLACKLIST` são rejeitados
  por defesa em profundidade em `network_signal_rules`.
- `verified_access_requests.request_type` aceita somente `VISITOR`,
  `SERVICE_PROVIDER`.
- `verified_access_requests.status` aceita somente `DRAFT`,
  `INVITATIONS_PENDING`, `IN_PROGRESS`, `PARTIALLY_ELIGIBLE`, `ELIGIBLE`,
  `COMPLETED`, `CANCELLED`, `EXPIRED`.
- `verified_access_participant_slots.status` aceita somente `OPEN`,
  `RESERVED`, `CLAIMED`, `CANCELLED`, `EXPIRED`.
- Slot `OPEN` exige `claimed_at` nulo.
- Slot `RESERVED` ou `CLAIMED` exige `claimed_at` preenchido.
- Slot acima de `participant_limit` é bloqueado por
  `verified_access_validate_slot_capacity()`.
- `verified_access_participants.registration_status` aceita somente
  `NOT_STARTED`, `INVITED`, `IN_PROGRESS`, `SUBMITTED`, `CANCELLED`,
  `EXPIRED`.
- `verified_access_participants.identity_status` aceita somente
  `UNVERIFIED`, `SELF_DECLARED`, `CONTACT_VERIFIED`, `DOCUMENT_CAPTURED`,
  `DOCUMENT_VERIFIED`, `LIVENESS_VERIFIED`, `IDENTITY_VERIFIED`,
  `MANUAL_VERIFIED`, `INCONCLUSIVE`, `TECHNICAL_ERROR`.
- `verified_access_participants.background_status` aceita somente
  `NOT_REQUIRED`, `NOT_STARTED`, `PENDING`, `NEGATIVE_CERTIFICATE`,
  `ADVERSE_INFORMATION_REVIEW`, `MANUAL_CONFIRMATION_REQUIRED`,
  `INCONCLUSIVE`, `PROVIDER_ERROR`, `EXPIRED`.
- `verified_access_participants.network_status` aceita somente `NOT_ENABLED`,
  `NO_ACTIVE_NETWORK_SIGNAL`, `NETWORK_REVALIDATION_REQUIRED`,
  `NETWORK_MANUAL_REVIEW_REQUIRED`, `NETWORK_CREDENTIAL_HOLD`,
  `NETWORK_SIGNAL_EXPIRED`, `NETWORK_SIGNAL_REVOKED`.
- `verified_access_participants.eligibility_status` aceita somente `PENDING`,
  `ELIGIBLE`, `REVIEW_REQUIRED`, `CORRECTION_REQUIRED`, `DENIED_MANUAL`,
  `CANCELLED`, `EXPIRED`.
- `verified_access_eligibility_evaluations.outcome` aceita somente `ELIGIBLE`,
  `REVIEW_REQUIRED`, `CORRECTION_REQUIRED`, `DENIED_MANUAL`, `CANCELLED`,
  `EXPIRED`.
- `verified_access_eligibility_evaluations.decision_source` aceita somente
  `SYSTEM_RULES`, `HUMAN_REVIEW`, `TECHNICAL_RECONCILIATION`.
- `verified_access_outbox_events.status` aceita somente `PENDING`,
  `PROCESSING`, `PROCESSED`, `FAILED`, `DISCARDED`.
- `verified_access_outbox_events.payload` deve ser objeto JSON sanitizado.
- `verified_access_outbox_events.deduplication_key` é único.
- `verified_access_prevent_outbox_business_mutation()` permite atualizar apenas
  campos operacionais da outbox.
- `verified_access_audit_events.metadata` deve ser objeto JSON sanitizado.
- `verified_access_prevent_audit_mutation()` bloqueia update, delete e truncate
  de audit.
- `verified_access_validate_service_request_details()` garante que detalhes de
  serviço só existam para request `SERVICE_PROVIDER` e que `OTHER` possua
  `other_description`.
- `verified_access_validate_service_type_requirement_change()` impede mudar
  `requires_description` de `false` para `true` quando existirem detalhes sem
  descrição.
- RLS está habilitada nas tabelas novas.
- `PUBLIC`, `anon` e `authenticated` não têm grants diretos nas tabelas locais.
- Helpers locais não são executáveis por `PUBLIC`, `anon` ou `authenticated`.
- `service_role` possui grants mínimos por tabela; audit é append-only.

### 3.2 Fase 1B — fundação inerte da Rede Confia

Objetos existentes:

- `verified_access_network_subjects`
- `verified_access_network_subject_identifiers`
- `verified_access_network_subject_links`
- `verified_access_network_security_cases`
- `verified_access_network_signals`
- `verified_access_network_signal_reviews`
- `verified_access_network_appeals`

Invariantes já implementadas:

- Features `VERIFIED_ACCESS_NETWORK_IDENTITY`,
  `VERIFIED_ACCESS_NETWORK_SIGNALS` e `VERIFIED_ACCESS_NETWORK_HOLD`
  cadastradas e desligadas.
- Nenhuma API, RPC, view, provider, HMAC real em SQL ou operação de rede foi
  criada.
- Tabelas centrais de rede não pertencem a tenant e ficam default-deny.
- `PUBLIC`, `anon`, `authenticated` e `service_role` não têm grants diretos nas
  tabelas centrais.
- Funções estruturais de validação da rede não têm grants de execução para
  `PUBLIC`, `anon`, `authenticated` ou `service_role`.
- `verified_access_network_subjects.status` aceita somente `ACTIVE`,
  `UNDER_REVIEW`, `DISPUTED`, `MERGED`, `RETIRED`.
- Subject `MERGED` exige `merged_into_subject_id` e não pode apontar para si
  mesmo.
- Identificadores de rede aceitam somente `CPF`, `RNM`,
  `PASSPORT_WITH_ISSUER`.
- `verified_access_network_subject_identifiers.status` aceita somente `ACTIVE`,
  `REVOKED`, `EXPIRED`.
- Identificador `REVOKED` exige `revoked_at` e `revoked_reason_code`.
- Identificador `EXPIRED` exige `expires_at`.
- Identificador ativo é único por `identifier_type`, `identifier_hmac`,
  `hmac_key_version` e `canonicalization_version`.
- `verified_access_network_subject_links.link_status` aceita somente `ACTIVE`,
  `DISPUTED`, `UNLINKED`.
- `verified_access_network_subject_links.link_reason` aceita somente
  `IDENTITY_VERIFIED`, `MANUAL_VERIFIED`, `IDENTIFIER_ROTATION`,
  `SUBJECT_MERGE`, `CORRECTION`.
- Link `ACTIVE` ou `DISPUTED` exige `unlinked_at` nulo.
- Link `UNLINKED` exige `unlinked_at`.
- Link para identity profile usa FK composta com `condominium_id`.
- `verified_access_network_security_cases.source_type` aceita somente
  `CONDOMINIUM_REPORT`, `PLATFORM_SECURITY`, `IDENTITY_PROVIDER`,
  `BACKGROUND_PROVIDER`, `PRIVACY_CORRECTION`.
- `CONDOMINIUM_REPORT` exige `source_condominium_id` e
  `source_participant_id`.
- Fontes não locais exigem `source_condominium_id` e `source_participant_id`
  nulos.
- `verified_access_network_validate_case_source_subject()` garante que
  `source_participant_id` pertença ao `source_condominium_id`, possua
  `identity_profile_id` e tenha link `ACTIVE` ou `DISPUTED` para o mesmo
  `network_subject_id`.
- `verified_access_network_security_cases.status` aceita somente `REPORTED`,
  `TRIAGE`, `UNDER_REVIEW`, `SUBSTANTIATED`, `DISMISSED`, `CLOSED`,
  `EXPIRED`.
- Categorias de abertura aceitas:
  `IDENTITY_IMPERSONATION_SUSPECTED`, `DOCUMENT_FRAUD_SUSPECTED`,
  `CREDENTIAL_COMPROMISE_SUSPECTED`, `ACCOUNT_TAKEOVER_SUSPECTED`,
  `REPEATED_IDENTITY_MANIPULATION_SUSPECTED`,
  `PLATFORM_SECURITY_INCIDENT`, `OFFICIAL_SOURCE_REVALIDATION_REQUIRED`.
- Categorias genéricas como `POLICY_VIOLATION`, `LOCAL_DENIED`,
  `ACCESS_INCIDENT` e `SECURITY_REVIEW` são rejeitadas.
- `verified_access_network_signals` referencia case do mesmo subject por FK
  composta.
- `verified_access_network_validate_signal_source_case()` exige case
  `SUBSTANTIATED` para qualquer signal.
- Categorias confirmadas de signal aceitas:
  `IDENTITY_IMPERSONATION_CONFIRMED`, `DOCUMENT_FRAUD_CONFIRMED`,
  `CREDENTIAL_COMPROMISED`, `ACCOUNT_TAKEOVER_CONFIRMED`,
  `REPEATED_IDENTITY_MANIPULATION_CONFIRMED`,
  `PLATFORM_SECURITY_SUSPENSION`, `OFFICIAL_SOURCE_REVALIDATION_REQUIRED`.
- Efeitos aceitos: `INFORM_AUTHORIZED_REVIEWER`, `REVALIDATE_IDENTITY`,
  `REQUERY_OFFICIAL_SOURCE`, `REQUIRE_MANUAL_REVIEW`, `HOLD_CREDENTIAL`.
- `AUTO_DENY_NETWORK` é impossível por check.
- `verified_access_network_signals.status` aceita somente `DRAFT`,
  `UNDER_REVIEW`, `ACTIVE`, `SUSPENDED`, `REVOKED`, `EXPIRED`, `REJECTED`.
- Signal exige `expires_at > valid_from` e `review_due_at` entre `valid_from`
  e `expires_at`.
- Timestamps de signal já são coerentes por status estático.
- `verified_access_network_signal_reviews.decision` aceita somente `APPROVE`,
  `REJECT`, `REQUEST_CHANGES`.
- `verified_access_network_appeals.status` aceita somente `OPEN`,
  `UNDER_REVIEW`, `UPHELD`, `AMENDED`, `REVOKED`, `CLOSED`.
- Appeal com `signal_id` referencia signal do mesmo `network_subject_id` por FK
  composta.
- Appeal sem signal continua permitido.
- `LOCAL_DENIED` não cria case nem signal.
- Case aberto, em triagem ou revisão não afeta outro condomínio.
- Signal `DRAFT` ou `UNDER_REVIEW` não afeta outro condomínio.

## 4. Migrations Futuras da Fase 1C

A Fase 1C deve criar exatamente estas migrations, com timestamp real da
execução futura:

| Ordem | Nome sugerido | Responsabilidade |
|---|---|---|
| 1 | `YYYYMMDDHHMM00_verified_access_state_machines.sql` | Funções e triggers de transição para requests, slots, participants, subjects, identifiers, links, cases, signals e appeals; timestamps obrigatórios; bloqueio de reabertura de estados finais; preservação dos checks existentes. |
| 2 | `YYYYMMDDHHMM10_verified_access_policy_rpcs.sql` | Imutabilidade de policy `ACTIVE`; uma policy `ACTIVE` por condomínio; validação transacional de `network_signal_rules`; RPCs restritas `verified_access_create_policy_draft`, `verified_access_activate_policy`, `verified_access_retire_policy`; grants mínimos. |
| 3 | `YYYYMMDDHHMM20_verified_access_audit_outbox_helpers.sql` | Helpers internos de audit/outbox; deduplicação; payload sanitizado; eventos na mesma transação das alterações de domínio; eventos de reavaliação após expiração/revogação futura de signal; grants/revokes dos helpers. |
| 4 | `supabase/rollback/YYYYMMDDHHMM00_verified_access_phase_1c_rollback.sql` | Rollback único da Fase 1C, removendo triggers, RPCs, helpers, funções e índices/constraints auxiliares na ordem inversa, preservando 1A e 1B. |

Não criar migration de Fase 1D, provider, Edge Function, view, job, cron,
processador de outbox ou API nesta fase.

## 5. Máquinas de Estado Planejadas

Regras comuns:

- Valor fora do domínio existente continua rejeitado por `23514`.
- Transição válida em domínio errado ou FK inválida continua rejeitada por
  `23503`.
- Unicidade continua rejeitada por `23505`.
- Transição proibida por trigger da Fase 1C deve rejeitar com `P0001`.
- Timestamp obrigatório ausente deve rejeitar com `23514` quando for check
  estático e `P0001` quando depender da transição anterior.

### 5.1 `verified_access_requests.status`

| De | Para permitido |
|---|---|
| `DRAFT` | `INVITATIONS_PENDING`, `CANCELLED`, `EXPIRED` |
| `INVITATIONS_PENDING` | `IN_PROGRESS`, `CANCELLED`, `EXPIRED` |
| `IN_PROGRESS` | `PARTIALLY_ELIGIBLE`, `ELIGIBLE`, `CANCELLED`, `EXPIRED` |
| `PARTIALLY_ELIGIBLE` | `ELIGIBLE`, `COMPLETED`, `CANCELLED`, `EXPIRED` |
| `ELIGIBLE` | `COMPLETED`, `CANCELLED`, `EXPIRED` |
| `COMPLETED` | nenhuma |
| `CANCELLED` | nenhuma |
| `EXPIRED` | nenhuma |

Estados finais: `COMPLETED`, `CANCELLED`, `EXPIRED`.

Transições proibidas: pular de `DRAFT` para `COMPLETED`, reabrir final,
retroceder para `DRAFT`, mover `CANCELLED` para qualquer estado operacional,
marcar `COMPLETED` sem todos os participantes finais.

Timestamps obrigatórios planejados:

- `cancelled_at` quando `status = 'CANCELLED'`.
- `expires_at` já deve existir para expiração; se `status = 'EXPIRED'`,
  `expires_at <= now()` ou motivo técnico explícito.
- `completed_at` futuro somente se coluna for criada; caso contrário, registrar
  audit event `REQUEST_COMPLETED`.

SQLSTATE esperado: `P0001` para transição proibida; `23514` para domínio de
status inválido.

### 5.2 `verified_access_participant_slots.status`

| De | Para permitido |
|---|---|
| `OPEN` | `RESERVED`, `CLAIMED`, `CANCELLED`, `EXPIRED` |
| `RESERVED` | `CLAIMED`, `CANCELLED`, `EXPIRED` |
| `CLAIMED` | `CANCELLED`, `EXPIRED` |
| `CANCELLED` | nenhuma |
| `EXPIRED` | nenhuma |

Estados finais: `CANCELLED`, `EXPIRED`.

Transições proibidas: `CLAIMED` para `OPEN`, `RESERVED` sem `claimed_at`,
`OPEN` com `claimed_at`, reabertura de `CANCELLED` ou `EXPIRED`, slot acima de
capacidade.

Timestamps obrigatórios:

- `claimed_at` para `RESERVED` e `CLAIMED`.
- `claimed_at` nulo para `OPEN`.
- `cancelled_at`/`expired_at` não existem hoje; a Fase 1C deve registrar audit
  event sanitizado quando não houver coluna.

SQLSTATE esperado: `23514` para invariantes de `claimed_at`; `P0001` para
transição proibida ou capacidade; `23505` para slot duplicado.

### 5.3 `verified_access_participants.registration_status`

| De | Para permitido |
|---|---|
| `NOT_STARTED` | `INVITED`, `IN_PROGRESS`, `CANCELLED`, `EXPIRED` |
| `INVITED` | `IN_PROGRESS`, `SUBMITTED`, `CANCELLED`, `EXPIRED` |
| `IN_PROGRESS` | `SUBMITTED`, `CANCELLED`, `EXPIRED` |
| `SUBMITTED` | `CANCELLED`, `EXPIRED` |
| `CANCELLED` | nenhuma |
| `EXPIRED` | nenhuma |

Estados finais: `SUBMITTED` para cadastro concluído; `CANCELLED` e `EXPIRED`
para encerramento operacional.

Transições proibidas: reabrir `CANCELLED`/`EXPIRED`, voltar de `SUBMITTED` para
`IN_PROGRESS`, submeter participante sem slot compatível, submeter sem perfil
quando o fluxo exigir identidade.

Timestamps obrigatórios:

- `submitted_at` futuro somente se coluna for criada; sem coluna, audit event
  `PARTICIPANT_SUBMITTED`.
- `cancelled_at`/`expired_at` por audit event se não houver coluna.

SQLSTATE esperado: `P0001` para transição proibida; `23514` para status fora do
domínio.

### 5.4 `verified_access_participants.identity_status`

| De | Para permitido |
|---|---|
| `UNVERIFIED` | `SELF_DECLARED`, `CONTACT_VERIFIED`, `DOCUMENT_CAPTURED`, `INCONCLUSIVE`, `TECHNICAL_ERROR` |
| `SELF_DECLARED` | `CONTACT_VERIFIED`, `DOCUMENT_CAPTURED`, `INCONCLUSIVE`, `TECHNICAL_ERROR` |
| `CONTACT_VERIFIED` | `DOCUMENT_CAPTURED`, `INCONCLUSIVE`, `TECHNICAL_ERROR` |
| `DOCUMENT_CAPTURED` | `DOCUMENT_VERIFIED`, `LIVENESS_VERIFIED`, `INCONCLUSIVE`, `TECHNICAL_ERROR` |
| `DOCUMENT_VERIFIED` | `IDENTITY_VERIFIED`, `MANUAL_VERIFIED`, `INCONCLUSIVE`, `TECHNICAL_ERROR` |
| `LIVENESS_VERIFIED` | `IDENTITY_VERIFIED`, `MANUAL_VERIFIED`, `INCONCLUSIVE`, `TECHNICAL_ERROR` |
| `IDENTITY_VERIFIED` | `MANUAL_VERIFIED`, `INCONCLUSIVE`, `TECHNICAL_ERROR` |
| `MANUAL_VERIFIED` | `INCONCLUSIVE`, `TECHNICAL_ERROR` |
| `INCONCLUSIVE` | `DOCUMENT_CAPTURED`, `DOCUMENT_VERIFIED`, `LIVENESS_VERIFIED`, `IDENTITY_VERIFIED`, `MANUAL_VERIFIED`, `TECHNICAL_ERROR` |
| `TECHNICAL_ERROR` | `DOCUMENT_CAPTURED`, `INCONCLUSIVE` |

Estados finais: nenhum estado é permanentemente final nesta fase; verificações
podem ser corrigidas ou reprocessadas por fluxo autorizado futuro.

Transições proibidas: `LIVENESS_VERIFIED` isolado virar `IDENTITY_VERIFIED` sem
documento válido; `TECHNICAL_ERROR` virar `IDENTITY_VERIFIED` diretamente;
`UNVERIFIED` virar `IDENTITY_VERIFIED` sem etapas ou evento autorizado.

Timestamps obrigatórios:

- Mudanças para `DOCUMENT_VERIFIED`, `IDENTITY_VERIFIED` e `MANUAL_VERIFIED`
  exigem audit event sanitizado com source code e sem PII.
- Vínculo de rede futuro só pode usar `DOCUMENT_VERIFIED`, `IDENTITY_VERIFIED`
  ou `MANUAL_VERIFIED` conforme regra do link.

SQLSTATE esperado: `P0001` para transição proibida; `23514` para status fora do
domínio.

### 5.5 `verified_access_participants.background_status`

| De | Para permitido |
|---|---|
| `NOT_REQUIRED` | nenhuma, exceto correção para `NOT_STARTED` antes de avaliação |
| `NOT_STARTED` | `PENDING`, `INCONCLUSIVE`, `PROVIDER_ERROR`, `EXPIRED` |
| `PENDING` | `NEGATIVE_CERTIFICATE`, `ADVERSE_INFORMATION_REVIEW`, `MANUAL_CONFIRMATION_REQUIRED`, `INCONCLUSIVE`, `PROVIDER_ERROR`, `EXPIRED` |
| `NEGATIVE_CERTIFICATE` | `EXPIRED` |
| `ADVERSE_INFORMATION_REVIEW` | `MANUAL_CONFIRMATION_REQUIRED`, `INCONCLUSIVE`, `EXPIRED` |
| `MANUAL_CONFIRMATION_REQUIRED` | `NEGATIVE_CERTIFICATE`, `INCONCLUSIVE`, `EXPIRED` |
| `INCONCLUSIVE` | `PENDING`, `PROVIDER_ERROR`, `EXPIRED` |
| `PROVIDER_ERROR` | `PENDING`, `INCONCLUSIVE`, `EXPIRED` |
| `EXPIRED` | nenhuma, exceto novo ciclo por registro novo/autorizado |

Estados finais: `NEGATIVE_CERTIFICATE` para o ciclo vigente; `EXPIRED` para
encerramento do resultado.

Transições proibidas: adverso virar `DENIED_MANUAL` automaticamente, provider
error virar negativa, inconclusivo virar negativa, `EXPIRED` reabrir sem novo
ciclo.

Timestamps obrigatórios:

- Resultado provider deve registrar audit event sanitizado.
- Expiração deve registrar audit/outbox de reavaliação se afetar elegibilidade.

SQLSTATE esperado: `P0001` para transição proibida; `23514` para status fora do
domínio.

### 5.6 `verified_access_participants.network_status`

| De | Para permitido |
|---|---|
| `NOT_ENABLED` | `NO_ACTIVE_NETWORK_SIGNAL` somente se feature/policy permitir avaliação |
| `NO_ACTIVE_NETWORK_SIGNAL` | `NETWORK_REVALIDATION_REQUIRED`, `NETWORK_MANUAL_REVIEW_REQUIRED`, `NETWORK_CREDENTIAL_HOLD`, `NETWORK_SIGNAL_EXPIRED`, `NETWORK_SIGNAL_REVOKED`, `NOT_ENABLED` |
| `NETWORK_REVALIDATION_REQUIRED` | `NO_ACTIVE_NETWORK_SIGNAL`, `NETWORK_MANUAL_REVIEW_REQUIRED`, `NETWORK_CREDENTIAL_HOLD`, `NETWORK_SIGNAL_EXPIRED`, `NETWORK_SIGNAL_REVOKED`, `NOT_ENABLED` |
| `NETWORK_MANUAL_REVIEW_REQUIRED` | `NO_ACTIVE_NETWORK_SIGNAL`, `NETWORK_CREDENTIAL_HOLD`, `NETWORK_SIGNAL_EXPIRED`, `NETWORK_SIGNAL_REVOKED`, `NOT_ENABLED` |
| `NETWORK_CREDENTIAL_HOLD` | `NO_ACTIVE_NETWORK_SIGNAL`, `NETWORK_MANUAL_REVIEW_REQUIRED`, `NETWORK_SIGNAL_EXPIRED`, `NETWORK_SIGNAL_REVOKED`, `NOT_ENABLED` |
| `NETWORK_SIGNAL_EXPIRED` | `NO_ACTIVE_NETWORK_SIGNAL`, `NOT_ENABLED` |
| `NETWORK_SIGNAL_REVOKED` | `NO_ACTIVE_NETWORK_SIGNAL`, `NOT_ENABLED` |

Estados finais: nenhum; rede é avaliação derivada e pode mudar por expiração,
revogação ou feature.

Transições proibidas: qualquer network status produzir `DENIED_MANUAL`
automaticamente; `LOCAL_DENIED` criar network status; aplicar rede com feature
desligada; usar signal `DRAFT`, `UNDER_REVIEW`, `SUSPENDED`, `REVOKED` ou
`EXPIRED` como ativo.

Timestamps obrigatórios:

- Cada mudança deve gerar audit event.
- Revogação/expiração de signal deve gerar outbox de reavaliação sem PII.

SQLSTATE esperado: `P0001` para transição proibida; `23514` para status fora do
domínio.

### 5.7 `verified_access_participants.eligibility_status`

| De | Para permitido |
|---|---|
| `PENDING` | `ELIGIBLE`, `REVIEW_REQUIRED`, `CORRECTION_REQUIRED`, `DENIED_MANUAL`, `CANCELLED`, `EXPIRED` |
| `ELIGIBLE` | `REVIEW_REQUIRED`, `CANCELLED`, `EXPIRED` |
| `REVIEW_REQUIRED` | `ELIGIBLE`, `CORRECTION_REQUIRED`, `DENIED_MANUAL`, `CANCELLED`, `EXPIRED` |
| `CORRECTION_REQUIRED` | `PENDING`, `REVIEW_REQUIRED`, `CANCELLED`, `EXPIRED` |
| `DENIED_MANUAL` | `REVIEW_REQUIRED`, `CANCELLED`, `EXPIRED` somente por revisão humana futura autorizada |
| `CANCELLED` | nenhuma |
| `EXPIRED` | nenhuma |

Estados finais: `CANCELLED`, `EXPIRED`; `DENIED_MANUAL` é terminal operacional
até revisão humana autorizada, mas não é gerado automaticamente por rede.

Transições proibidas: `HOLD_CREDENTIAL` virar `DENIED_MANUAL`; background
inconclusivo virar negativa; provider indisponível virar negativa; network
signal virar negativa definitiva.

Timestamps obrigatórios:

- `DENIED_MANUAL` exige audit event com `decision_source = 'HUMAN_REVIEW'`.
- `ELIGIBLE` deve registrar avaliação correspondente em
  `verified_access_eligibility_evaluations`.

SQLSTATE esperado: `P0001` para transição proibida; `23514` para status fora do
domínio.

### 5.8 `verified_access_network_subjects.status`

| De | Para permitido |
|---|---|
| `ACTIVE` | `UNDER_REVIEW`, `DISPUTED`, `MERGED`, `RETIRED` |
| `UNDER_REVIEW` | `ACTIVE`, `DISPUTED`, `MERGED`, `RETIRED` |
| `DISPUTED` | `ACTIVE`, `UNDER_REVIEW`, `MERGED`, `RETIRED` |
| `MERGED` | nenhuma |
| `RETIRED` | nenhuma |

Estados finais: `MERGED`, `RETIRED`.

Transições proibidas: reabrir `MERGED` ou `RETIRED`, `MERGED` sem
`merged_into_subject_id`, merge para si mesmo, merge para subject final inválido.

Timestamps obrigatórios:

- `MERGED` exige `merged_into_subject_id` já existente.
- `RETIRED` exige audit event e `retention_until` coerente quando aplicável.
- `UNDER_REVIEW`/`DISPUTED` exigem audit event sanitizado.

SQLSTATE esperado: `P0001` para transição proibida; `23514` para checks
estáticos.

### 5.9 `verified_access_network_security_cases.status`

| De | Para permitido |
|---|---|
| `REPORTED` | `TRIAGE`, `UNDER_REVIEW`, `DISMISSED`, `EXPIRED` |
| `TRIAGE` | `UNDER_REVIEW`, `DISMISSED`, `EXPIRED` |
| `UNDER_REVIEW` | `SUBSTANTIATED`, `DISMISSED`, `EXPIRED` |
| `SUBSTANTIATED` | `CLOSED`, `EXPIRED` |
| `DISMISSED` | `CLOSED` |
| `CLOSED` | nenhuma |
| `EXPIRED` | nenhuma |

Estados finais: `CLOSED`, `EXPIRED`; `DISMISSED` é conclusivo, mas pode ser
fechado administrativamente.

Transições proibidas: `REPORTED` para `SUBSTANTIATED` sem revisão,
`DISMISSED` para `SUBSTANTIATED`, reabrir `CLOSED`/`EXPIRED`, criar signal a
partir de case não `SUBSTANTIATED`.

Timestamps obrigatórios:

- `SUBSTANTIATED`, `DISMISSED`, `CLOSED` e `EXPIRED` exigem timestamp de decisão
  ou audit event se coluna dedicada não existir.
- Mudança de status deve registrar actor code sanitizado.

SQLSTATE esperado: `P0001` para transição proibida; `23514` para status fora do
domínio.

### 5.10 `verified_access_network_signals.status`

| De | Para permitido |
|---|---|
| `DRAFT` | `UNDER_REVIEW`, `REJECTED`, `EXPIRED` |
| `UNDER_REVIEW` | `ACTIVE`, `REJECTED`, `EXPIRED` |
| `ACTIVE` | `SUSPENDED`, `REVOKED`, `EXPIRED` |
| `SUSPENDED` | `ACTIVE`, `REVOKED`, `EXPIRED` |
| `REVOKED` | nenhuma |
| `EXPIRED` | nenhuma |
| `REJECTED` | nenhuma |

Estados finais: `REVOKED`, `EXPIRED`, `REJECTED`.

Transições proibidas: ativar signal sem case `SUBSTANTIATED`, ativar sem
revisões suficientes quando ativação de signal existir em fase futura, proponente
aprovar sozinho signal crítico, reabrir `REVOKED`/`EXPIRED`/`REJECTED`, signal
permanente sem expiração, efeito `AUTO_DENY_NETWORK`.

Timestamps obrigatórios:

- `ACTIVE` exige `activated_at`.
- `SUSPENDED` exige `activated_at` e `suspended_at`.
- `REVOKED` exige `revoked_at` e `revocation_reason_code`.
- `EXPIRED` exige `expired_at`.
- `REJECTED` exige `rejected_at` e `rejection_reason_code`.

SQLSTATE esperado: `P0001` para transição proibida; `23514` para timestamps
estáticos ou efeito inválido.

### 5.11 `verified_access_network_appeals.status`

| De | Para permitido |
|---|---|
| `OPEN` | `UNDER_REVIEW`, `CLOSED` |
| `UNDER_REVIEW` | `UPHELD`, `AMENDED`, `REVOKED`, `CLOSED` |
| `UPHELD` | `CLOSED` |
| `AMENDED` | `CLOSED` |
| `REVOKED` | `CLOSED` |
| `CLOSED` | nenhuma |

Estados finais: `CLOSED`; `UPHELD`, `AMENDED` e `REVOKED` são resoluções que
podem ser fechadas.

Transições proibidas: resolver sem `resolved_at`, `resolution_code` e
`resolved_by_actor_id`; appeal com signal de outro subject; reabrir `CLOSED`;
alterar `request_reference_hash`.

Timestamps obrigatórios:

- `OPEN`/`UNDER_REVIEW` exigem `resolved_at`, `resolution_code` e
  `resolved_by_actor_id` nulos.
- `UPHELD`, `AMENDED`, `REVOKED`, `CLOSED` exigem `resolved_at`,
  `resolution_code` e `resolved_by_actor_id`.

SQLSTATE esperado: `23514` para timestamps/resolução estáticos; `P0001` para
transição proibida; `23503` para signal de outro subject.

## 6. Funções Internas Planejadas

Todas as funções devem começar com `public.verified_access_`, usar
`set search_path = public, pg_temp` quando `security definer`, revogar execução
de `PUBLIC`, `anon`, `authenticated` e `service_role` por padrão e receber grant
somente quando listado nesta seção.

| Função | Parâmetros | Retorno | Segurança | Grants | Tabelas alteradas | Audit/outbox |
|---|---|---|---|---|---|---|
| `verified_access_validate_request_transition()` | trigger | trigger | security invoker | nenhum grant direto | `verified_access_requests` via trigger | audit `REQUEST_STATUS_CHANGED`; outbox quando final afeta participantes |
| `verified_access_validate_slot_transition()` | trigger | trigger | security invoker | nenhum grant direto | `verified_access_participant_slots` via trigger | audit `SLOT_STATUS_CHANGED` |
| `verified_access_validate_participant_transition()` | trigger | trigger | security invoker | nenhum grant direto | `verified_access_participants` via trigger | audit `PARTICIPANT_STATUS_CHANGED`; outbox para reavaliação quando elegibilidade/rede muda |
| `verified_access_validate_network_subject_transition()` | trigger | trigger | security invoker | nenhum grant direto | `verified_access_network_subjects` via trigger | audit `NETWORK_SUBJECT_STATUS_CHANGED`; outbox em merge/retire |
| `verified_access_validate_network_identifier_transition()` | trigger | trigger | security invoker | nenhum grant direto | `verified_access_network_subject_identifiers` via trigger | audit `NETWORK_IDENTIFIER_STATUS_CHANGED`; outbox em revoke/expire |
| `verified_access_validate_network_link_transition()` | trigger | trigger | security invoker | nenhum grant direto | `verified_access_network_subject_links` via trigger | audit `NETWORK_LINK_STATUS_CHANGED`; outbox em unlink/dispute |
| `verified_access_validate_network_case_transition()` | trigger | trigger | security invoker | nenhum grant direto | `verified_access_network_security_cases` via trigger | audit `NETWORK_CASE_STATUS_CHANGED`; sem outbox para case não substanciado |
| `verified_access_validate_network_signal_transition()` | trigger | trigger | security invoker | nenhum grant direto | `verified_access_network_signals` via trigger | audit `NETWORK_SIGNAL_STATUS_CHANGED`; outbox em `ACTIVE`, `REVOKED`, `EXPIRED` |
| `verified_access_validate_network_appeal_transition()` | trigger | trigger | security invoker | nenhum grant direto | `verified_access_network_appeals` via trigger | audit `NETWORK_APPEAL_STATUS_CHANGED`; outbox em `AMENDED`/`REVOKED` |
| `verified_access_write_audit_event(...)` | `p_condominium_id uuid`, `p_actor_type text`, `p_actor_id text`, `p_aggregate_type text`, `p_aggregate_id uuid`, `p_event_type text`, `p_metadata jsonb default '{}'` | uuid | security definer | somente RPCs de policy e triggers internos; nenhum role direto | `verified_access_audit_events` | insere audit append-only |
| `verified_access_enqueue_outbox_event(...)` | `p_condominium_id uuid`, `p_aggregate_type text`, `p_aggregate_id uuid`, `p_event_type text`, `p_deduplication_key text`, `p_payload jsonb` | uuid | security definer | somente RPCs de policy e triggers internos; nenhum role direto | `verified_access_outbox_events` | insere ou retorna evento idempotente |
| `verified_access_validate_policy_rules(p_network_signal_rules jsonb)` | `jsonb` | void | security invoker | nenhum role direto | nenhuma | sem audit/outbox |
| `verified_access_assert_policy_mutable()` | trigger | trigger | security invoker | nenhum grant direto | `verified_access_policies` via trigger | audit para tentativa não é obrigatório; rejeição sem PII |
| `verified_access_validate_single_active_policy()` | trigger | trigger | security invoker | nenhum grant direto | `verified_access_policies` via trigger | sem outbox |

Helpers `security definer` só são aceitáveis para escrita controlada em audit e
outbox ou para RPCs transacionais de policy. Eles devem conter `search_path`
fixo, validação de payload sanitizado e grants mínimos.

## 7. RPCs Permitidas

Somente estas RPCs podem ser criadas na Fase 1C:

### 7.1 `verified_access_create_policy_draft`

Parâmetros planejados:

- `p_condominium_id uuid`
- `p_base_policy_id uuid default null`
- `p_policy jsonb`
- `p_actor_id text`
- `p_idempotency_key text default null`

Retorno: `uuid` da policy draft.

Segurança: `security definer`, `search_path = public, pg_temp`.

Grants: nenhum para `PUBLIC` ou `anon`; grant futuro somente a role técnica
autorizada no contrato da execução. Não conceder a `authenticated` sem RBAC
estável.

Regras:

- Não ativa policy.
- Valida feature base desligada/ligada apenas como dependência, sem habilitar
  feature.
- Valida referências de aprovação exigidas.
- Valida `network_signal_rules`.
- Rejeita `AUTO_DENY_NETWORK`.
- Escreve audit `POLICY_DRAFT_CREATED`.
- Enfileira outbox somente se houver consumidor futuro autorizado; caso
  contrário, apenas audit.

### 7.2 `verified_access_activate_policy`

Parâmetros planejados:

- `p_condominium_id uuid`
- `p_policy_id uuid`
- `p_actor_id text`
- `p_approval_reference text`
- `p_idempotency_key text default null`

Retorno: `uuid` da policy ativa.

Segurança: `security definer`, `search_path = public, pg_temp`.

Grants: nenhum para `PUBLIC`, `anon` ou `authenticated` sem contrato de RBAC.

Regras:

- Executa em uma única transação.
- Bloqueia as policies do condomínio com `for update`.
- Exige policy atual em `DRAFT`.
- Retira a policy `ACTIVE` anterior para `RETIRED` na mesma transação.
- Ativa exatamente uma policy por condomínio.
- Policy `ACTIVE` passa a ser imutável.
- Exige `approval_reference` compatível com identidade/background/rede.
- Escreve audit `POLICY_ACTIVATED`.
- Enfileira outbox idempotente `POLICY_ACTIVATED` para reavaliar pendências do
  condomínio, sem PII.

### 7.3 `verified_access_retire_policy`

Parâmetros planejados:

- `p_condominium_id uuid`
- `p_policy_id uuid`
- `p_actor_id text`
- `p_reason_code text`
- `p_idempotency_key text default null`

Retorno: `uuid` da policy aposentada.

Segurança: `security definer`, `search_path = public, pg_temp`.

Grants: nenhum para `PUBLIC`, `anon` ou `authenticated` sem contrato de RBAC.

Regras:

- Executa em uma única transação.
- Permite aposentar policy `DRAFT` ou `ACTIVE`.
- Se aposentar `ACTIVE`, exige que outra policy seja ativada na mesma transação
  ou que o contrato futuro aceite condomínio temporariamente sem policy ativa.
- Escreve audit `POLICY_RETIRED`.
- Enfileira outbox idempotente para reavaliação quando policy ativa muda.

## 8. Regras Transacionais de Policies

- Deve existir no máximo uma policy `ACTIVE` por condomínio.
- Implementar índice único parcial sugerido:
  `ux_verified_access_policies_one_active_per_condominium` sobre
  `(condominium_id)` onde `status = 'ACTIVE'`.
- Policy `ACTIVE` é imutável, exceto campos operacionais explicitamente
  permitidos pelo contrato futuro, se houver.
- Ativação e aposentadoria ocorrem na mesma transação.
- `visitor_identity_mode` ou `service_identity_mode` diferente de `DISABLED`
  exige `privacy_approval_reference`.
- `visitor_background_mode` ou `service_background_mode` diferente de
  `DISABLED` exige `background_approval_reference`.
- `network_identity_mode` diferente de `DISABLED`, hold de rede ou regra de
  rede operacional exige `network_approval_reference`.
- Feature `VERIFIED_ACCESS_NETWORK_IDENTITY` depende de `VERIFIED_ACCESS`.
- Feature `VERIFIED_ACCESS_NETWORK_SIGNALS` depende de
  `VERIFIED_ACCESS_NETWORK_IDENTITY`.
- Feature `VERIFIED_ACCESS_NETWORK_HOLD` depende de
  `VERIFIED_ACCESS_NETWORK_SIGNALS`.
- Nenhuma RPC habilita feature flag.
- `network_signal_rules` deve ser objeto JSON.
- `network_signal_rules` só pode conter efeitos permitidos:
  `INFORM_AUTHORIZED_REVIEWER`, `REVALIDATE_IDENTITY`,
  `REQUERY_OFFICIAL_SOURCE`, `REQUIRE_MANUAL_REVIEW`, `HOLD_CREDENTIAL`.
- `AUTO_DENY_NETWORK`, `GLOBAL_DENIED`, `PERMANENT_BLACKLIST` e aliases em
  qualquer casing devem ser rejeitados.
- `HOLD_CREDENTIAL` nunca produz `DENIED_MANUAL`.
- Mudanças de policy devem registrar audit e, quando ativação/retirement afetar
  solicitações pendentes, outbox idempotente na mesma transação.

## 9. Audit e Outbox

### 9.1 Payload permitido

Audit/outbox podem conter:

- IDs UUID internos.
- `condominium_id` quando a entidade for local.
- `network_subject_id` somente em eventos internos, nunca em payload público.
- Códigos de status, categoria, efeito, razão e evento.
- Versões de policy.
- Timestamps.
- Flags booleanas.
- Contadores.
- Hashes de referência já aprovados como não reversíveis e não PII.

### 9.2 Payload proibido

Audit/outbox não podem conter:

- CPF, RNM, passaporte ou documento em texto aberto.
- Nome, telefone, e-mail, nascimento, filiação ou endereço.
- Selfie, face, template, embedding ou dado biométrico.
- Certidão, antecedente, evidência bruta ou narrativa livre sensível.
- Token, secret, chave, URL assinada ou payload de provider.
- `network_hmac` ou HMAC local quando não houver necessidade operacional
  explícita.

### 9.3 Deduplication key

Formato sugerido:

```text
verified_access:{domain}:{event}:{aggregate_id}:{version_or_status}:{reason_code}
```

Exemplos:

- `verified_access:policy:activated:{policy_id}:{version}`
- `verified_access:signal:revoked:{signal_id}:{revocation_reason_code}`
- `verified_access:participant:reevaluate:{participant_id}:{policy_version}`

### 9.4 Garantias

- Audit é append-only.
- Outbox é idempotente por `deduplication_key`.
- Helper de outbox deve retornar o evento existente quando a chave já existir.
- Campos de negócio da outbox permanecem imutáveis depois de inseridos.
- Audit/outbox devem ser gravados na mesma transação da alteração de domínio.
- Falha ao escrever audit/outbox deve abortar a alteração de domínio.
- Processador externo permanece fora de escopo.

## 10. Matriz de RLS e Grants Planejada

| Superfície | PUBLIC | anon | authenticated | service_role | Funções internas | RPCs de policy |
|---|---|---|---|---|---|---|
| Tabelas locais 1A | nenhum grant novo | nenhum grant novo | nenhum grant direto novo | preservar grants mínimos existentes; não ampliar sem teste | acesso via trigger/helper conforme owner | sem acesso direto; RPC opera por validação própria |
| Tabelas centrais 1B | nenhum | nenhum | nenhum | nenhum | somente via owner/trigger, sem grant direto | nenhum acesso central salvo audit/outbox aprovado |
| `verified_access_audit_events` | nenhum | nenhum | nenhum | preservar mínimo existente | helper pode inserir | RPCs inserem via helper |
| `verified_access_outbox_events` | nenhum | nenhum | nenhum | preservar mínimo existente | helper pode inserir/idempotência | RPCs inserem via helper |
| Helpers `security invoker` | execute revogado | execute revogado | execute revogado | execute revogado | chamados por triggers | não chamados diretamente |
| Helpers `security definer` audit/outbox | execute revogado | execute revogado | execute revogado | execute revogado salvo contrato explícito | chamados internamente | chamados por RPCs |
| `verified_access_create_policy_draft` | revogado | revogado | revogado por padrão | grant somente se contrato autorizar role técnica | n/a | security definer com validação |
| `verified_access_activate_policy` | revogado | revogado | revogado por padrão | grant somente se contrato autorizar role técnica | n/a | security definer com validação |
| `verified_access_retire_policy` | revogado | revogado | revogado por padrão | grant somente se contrato autorizar role técnica | n/a | security definer com validação |

Princípios:

- Revogar privilégios preexistentes antes de conceder grants mínimos.
- Não criar policy RLS `USING (true)`.
- Não conceder operação sensível ao backoffice atual sem RBAC forte.
- Testar permissões com roles reais: `anon`, `authenticated`, `service_role`.

## 11. Plano de Testes da Fase 1C

### 11.1 pgTAP

- Existência das novas funções, triggers, constraints e RPCs.
- `search_path` fixo em funções `security definer`.
- Execução revogada de `PUBLIC`, `anon`, `authenticated` e `service_role`
  quando aplicável.
- Índice único parcial de uma policy `ACTIVE` por condomínio.
- Checks de payload sanitizado em audit/outbox.
- Checks de `network_signal_rules` rejeitando auto-deny e aliases.

### 11.2 Integração SQL

- Transições válidas de cada state machine.
- Transições proibidas retornando `P0001`.
- Estados fora do domínio retornando `23514`.
- FKs compostas preservando tenant isolation retornando `23503`.
- Policy draft criada sem ativar.
- Ativação aposenta policy ativa anterior e ativa a nova na mesma transação.
- Tentativa de alterar policy `ACTIVE` falha.
- Retirement idempotente falha ou retorna estado conforme contrato futuro.

### 11.3 Runtime role checks

- `anon` não lê nem escreve tabelas locais ou centrais.
- `authenticated` não escreve diretamente.
- `service_role` não ganha grants centrais da rede.
- RPCs de policy não ficam executáveis por roles não autorizadas.
- Helpers internos não ficam executáveis por roles públicas.

### 11.4 Tenant isolation

- Tenant A não ativa policy do tenant B.
- Tenant A não reavalia participant do tenant B.
- Link central não expõe `network_subject_id` a tenant.
- `CONDOMINIUM_REPORT` continua exigindo participant do mesmo condomínio e link
  do mesmo subject.

### 11.5 Idempotência, audit e outbox

- Mesmo `deduplication_key` não duplica outbox.
- Segunda chamada idempotente retorna o mesmo evento ou mesma policy conforme
  contrato.
- Audit não aceita update/delete/truncate.
- Payload com aliases de PII é rejeitado.
- Falha de audit/outbox aborta alteração de domínio.

### 11.6 Rollback e reaplicação

- Aplicar migrations 1A, 1B e 1C do zero.
- Executar pgTAP e integração.
- Executar rollback 1C.
- Verificar que objetos 1C sumiram.
- Verificar que objetos e testes smoke 1A/1B continuam íntegros.
- Reaplicar 1C.
- Reexecutar pgTAP e integração pós-reaplicação.

### 11.7 Preservação das Fases 1A e 1B

- Reexecutar workflow da Fase 1A.
- Reexecutar workflow da Fase 1B.
- Confirmar features desligadas.
- Confirmar nenhuma PII central.
- Confirmar `LOCAL_DENIED` sem case/signal.
- Confirmar signal exige case `SUBSTANTIATED`.

## 12. Rollback Planejado

Ordem exata:

1. Revogar grants das RPCs de policy.
2. Dropar RPCs:
   `verified_access_retire_policy`,
   `verified_access_activate_policy`,
   `verified_access_create_policy_draft`.
3. Dropar triggers de policy.
4. Dropar triggers de state machine locais.
5. Dropar triggers de state machine centrais.
6. Dropar triggers de audit/outbox criados na Fase 1C.
7. Dropar funções de validação de policy.
8. Dropar funções de state machine locais.
9. Dropar funções de state machine centrais.
10. Dropar helpers de audit/outbox criados na Fase 1C.
11. Dropar índices/constraints auxiliares da Fase 1C, incluindo o índice único
    parcial de policy ativa, se criado.
12. Preservar todas as tabelas 1A e 1B.
13. Preservar feature flags 1A e 1B desligadas.
14. Preservar `persons`, app Expo e objetos não relacionados.

Rollback não deve apagar dados das tabelas 1A/1B, exceto se o contrato futuro
criar tabelas auxiliares exclusivas da Fase 1C.

## 13. Workflow CI Planejado

Criar ou atualizar workflow dedicado, sugerido:

```text
.github/workflows/verified-access-phase-1c.yml
```

Jobs mínimos:

- `phase-1c-database`
  - checkout;
  - instalar dependências;
  - iniciar Supabase local com diagnostics sanitizados;
  - aplicar migrations do zero;
  - executar pgTAP 1A, 1B e 1C;
  - executar integração 1A, 1B e 1C;
  - runtime role checks;
  - `supabase db lint`;
  - rollback 1C;
  - verificação de rollback;
  - reaplicação 1C;
  - pgTAP pós-reaplicação;
  - integração pós-reaplicação.
- `phase-1c-admin-web`
  - `npm ci`;
  - `npm run admin:lint`;
  - `npm run admin:build`.
- Checks de preservação:
  - workflow 1A verde;
  - workflow 1B verde;
  - features desligadas;
  - nenhuma migration remota.

Diagnostics:

- Não publicar log bruto de `supabase start`.
- Sanitizar chaves, URLs sensíveis e connection strings.
- Não usar wildcard que capture arquivo bruto.

## 14. Condições de Parada e Blockers

Parar antes de alterar schema se:

- `origin/main` não contiver os squashs 1A e 1B esperados.
- Worktree não estiver limpa.
- Houver drift novo não documentado que afete migrations 1A/1B.
- Alguma migration 1A/1B já tiver sido aplicada remotamente sem gate específico.
- A solução exigir alterar `persons`.
- A solução exigir app Expo, UI, provider, Edge Function pública ou Fase 1D.
- A solução exigir habilitar feature flag.
- A solução exigir grants diretos para tenant nas tabelas centrais.
- A solução exigir abrir operação sensível ao backoffice atual.
- Não for possível garantir rollback/reaplicação em banco descartável.
- CI expuser chave, URL sensível ou log bruto.

## 15. Fora de Escopo Explícito

- Implementar Fase 1C a partir deste documento.
- Migration remota.
- Habilitar features.
- Criar provider real ou fake.
- Criar Edge Function.
- Criar API, view pública, busca global ou RPC operacional de rede.
- Reportar case por RPC.
- Substanciar case por RPC.
- Propor, aprovar ou ativar signal por RPC.
- Appeal pública.
- Processador de outbox.
- UI de backoffice.
- App Expo.
- Solicitação do morador.
- Convite.
- WhatsApp.
- QR Code.
- Credencial.
- Check-in/check-out.
- Alterar `persons`.
- HMAC real em SQL.
- Reconhecimento facial 1:N ou galeria biométrica.
- Fase 1D.

## 16. Condição de Execução Futura

A Fase 1C só pode começar quando um novo contrato versionado substituir
`CURRENT_TASK.md` e autorizar explicitamente:

- worktree e branch;
- base SHA;
- migrations exatas;
- testes;
- CI;
- rollback;
- limites de grants;
- formato do relatório final.

Não prosseguir automaticamente a partir deste plano.
