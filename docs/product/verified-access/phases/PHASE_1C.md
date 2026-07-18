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
state machines protegidas por triggers validadores
+ policies versionadas e transacionais
+ audit append-only por helper interno das RPCs de policy
+ outbox idempotente por helper interno das RPCs de policy
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
| 1 | `YYYYMMDDHHMM00_verified_access_state_machines.sql` | Funções e triggers de transição para requests, slots, participants, subjects, identifiers, links, cases, signals e appeals; validação exclusiva de `OLD`/`NEW`; timestamps obrigatórios já materializados em colunas; bloqueio de reabertura de estados finais; preservação dos checks existentes. |
| 2 | `YYYYMMDDHHMM10_verified_access_policy_rpcs.sql` | Imutabilidade de policy `ACTIVE`; uma policy `ACTIVE` por condomínio; validação transacional de `network_signal_rules`; RPCs restritas `verified_access_create_policy_draft`, `verified_access_activate_policy`, `verified_access_retire_policy`; grants mínimos. |
| 3 | `YYYYMMDDHHMM20_verified_access_audit_outbox_helpers.sql` | Helpers internos de audit/outbox usados somente pelas três RPCs de policy; deduplicação; payload sanitizado; eventos na mesma transação das operações de policy; grants/revokes dos helpers. |
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
- Triggers de state machine são sempre `security invoker` e apenas comparam
  `OLD` e `NEW`; eles não inserem audit, não inserem outbox, não chamam helpers
  `security definer` e não elevam privilégio.
- Na Fase 1C, audit/outbox transacionais são obrigatórios somente nas três RPCs
  de policy. Outras operações futuras que alterarem domínio deverão gravar
  audit/outbox por seus próprios caminhos autorizados em fases posteriores.

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
- `completed_at` futuro somente se coluna for criada; sem coluna dedicada, o
  trigger valida apenas `OLD`/`NEW` e não cria audit/outbox.

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
- `cancelled_at`/`expired_at` não existem hoje; o trigger valida apenas
  `OLD`/`NEW` e não cria audit/outbox para suprir coluna ausente.

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

- `submitted_at` futuro somente se coluna for criada.
- `cancelled_at`/`expired_at` futuro somente se coluna for criada; sem coluna,
  o trigger valida apenas `OLD`/`NEW`.

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
  exigem que o caminho operacional futuro registre audit sanitizado; o trigger
  da Fase 1C apenas valida a transição `OLD`/`NEW`.
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

- Resultado provider deverá registrar audit sanitizado quando providers forem
  autorizados em fase futura.
- Expiração que afete elegibilidade deverá gerar outbox por operação futura
  autorizada; o trigger da Fase 1C apenas valida `OLD`/`NEW`.

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

- Cada mudança operacional futura deverá gerar audit por caminho autorizado.
- Revogação/expiração de signal deverá gerar outbox de reavaliação quando
  houver operação de signal autorizada; o trigger da Fase 1C não escreve outbox.

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

- `DENIED_MANUAL` exige caminho operacional futuro com
  `decision_source = 'HUMAN_REVIEW'`; o trigger da Fase 1C não grava audit.
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
- `RETIRED` exige `retention_until` coerente quando aplicável.
- `UNDER_REVIEW`/`DISPUTED` exigirão audit sanitizado no caminho operacional
  futuro; o trigger da Fase 1C apenas valida `OLD`/`NEW`.

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
  quando coluna dedicada existir; sem coluna, o trigger não grava audit/outbox.
- Mudança de status deverá registrar actor code sanitizado no caminho
  operacional futuro, fora dos triggers de validação.

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
| `verified_access_validate_request_transition()` | trigger | trigger | security invoker | nenhum grant direto | nenhuma escrita própria; valida `verified_access_requests` via trigger | não grava audit/outbox |
| `verified_access_validate_slot_transition()` | trigger | trigger | security invoker | nenhum grant direto | nenhuma escrita própria; valida `verified_access_participant_slots` via trigger | não grava audit/outbox |
| `verified_access_validate_participant_transition()` | trigger | trigger | security invoker | nenhum grant direto | nenhuma escrita própria; valida `verified_access_participants` via trigger | não grava audit/outbox |
| `verified_access_validate_network_subject_transition()` | trigger | trigger | security invoker | nenhum grant direto | nenhuma escrita própria; valida `verified_access_network_subjects` via trigger | não grava audit/outbox |
| `verified_access_validate_network_identifier_transition()` | trigger | trigger | security invoker | nenhum grant direto | nenhuma escrita própria; valida `verified_access_network_subject_identifiers` via trigger | não grava audit/outbox |
| `verified_access_validate_network_link_transition()` | trigger | trigger | security invoker | nenhum grant direto | nenhuma escrita própria; valida `verified_access_network_subject_links` via trigger | não grava audit/outbox |
| `verified_access_validate_network_case_transition()` | trigger | trigger | security invoker | nenhum grant direto | nenhuma escrita própria; valida `verified_access_network_security_cases` via trigger | não grava audit/outbox |
| `verified_access_validate_network_signal_transition()` | trigger | trigger | security invoker | nenhum grant direto | nenhuma escrita própria; valida `verified_access_network_signals` via trigger | não grava audit/outbox |
| `verified_access_validate_network_appeal_transition()` | trigger | trigger | security invoker | nenhum grant direto | nenhuma escrita própria; valida `verified_access_network_appeals` via trigger | não grava audit/outbox |
| `verified_access_write_audit_event(...)` | `p_condominium_id uuid`, `p_actor_type text`, `p_actor_id text`, `p_aggregate_type text`, `p_aggregate_id uuid`, `p_event_type text`, `p_metadata jsonb default '{}'` | uuid | security definer com `search_path = public, pg_temp` | EXECUTE revogado de `PUBLIC`, `anon`, `authenticated` e `service_role`; nenhum grant direto | `verified_access_audit_events` | chamado somente internamente pelas três RPCs de policy |
| `verified_access_enqueue_outbox_event(...)` | `p_condominium_id uuid`, `p_aggregate_type text`, `p_aggregate_id uuid`, `p_event_type text`, `p_deduplication_key text`, `p_payload jsonb` | uuid | security definer com `search_path = public, pg_temp` | EXECUTE revogado de `PUBLIC`, `anon`, `authenticated` e `service_role`; nenhum grant direto | `verified_access_outbox_events` | chamado somente internamente pelas três RPCs de policy |
| `verified_access_validate_policy_rules(p_network_signal_rules jsonb)` | `jsonb` | void | security invoker | nenhum role direto | nenhuma | sem audit/outbox |
| `verified_access_assert_policy_mutable()` | trigger | trigger | security invoker | nenhum grant direto | nenhuma escrita própria; valida `verified_access_policies` via trigger | não grava audit/outbox |
| `verified_access_validate_single_active_policy()` | trigger | trigger | security invoker | nenhum grant direto | nenhuma escrita própria; valida `verified_access_policies` via trigger | não grava audit/outbox |

Helpers `security definer` de audit/outbox só são aceitáveis como rotinas
internas das três RPCs de policy. Eles devem conter `search_path = public,
pg_temp`, validação de payload sanitizado, EXECUTE revogado de `PUBLIC`, `anon`,
`authenticated` e `service_role`, e não podem ser chamados por triggers
`security invoker`.

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
- Aceita somente os campos de `p_policy` definidos na allowlist da seção 7.4.
- Rejeita chaves desconhecidas, campos controlados pelo servidor e tipos
  inválidos com SQLSTATE `22023`.
- Não usa `jsonb_populate_record` irrestrito; cada campo é mapeado
  explicitamente.
- `condominium_id`, `version`, `status`, `schema_version`,
  `content_checksum`, actor e timestamps são definidos somente pela RPC.
- `status` é sempre `DRAFT`.
- `version` é calculada sob lock das policies do condomínio.
- `content_checksum` é calculado no servidor a partir do payload normalizado.
- `p_actor_id` não pode ser sobrescrito por JSON.
- `p_base_policy_id`, quando informado, deve pertencer ao mesmo condomínio.
- Cópia de base policy usa a mesma allowlist; campos controlados pelo servidor
  da policy base não são copiados diretamente.
- Valida feature base desligada/ligada apenas como dependência, sem habilitar
  feature.
- Valida referências de aprovação exigidas.
- Valida `network_signal_rules`.
- Rejeita `AUTO_DENY_NETWORK`.
- Escreve audit `POLICY_DRAFT_CREATED`.
- Enfileira outbox idempotente `POLICY_DRAFT_CREATED` somente se o contrato
  futuro mantiver esse evento; se não houver consumidor autorizado, a RPC deve
  registrar apenas audit.

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
- É o único caminho permitido para substituir uma policy `ACTIVE`.
- Nunca deixa intervalo transacional sem policy ativa quando já havia uma
  `ACTIVE` anterior.
- A substituição direta por `UPDATE` fora desta RPC deve falhar por trigger de
  imutabilidade ou índice/constraint.
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
- Aposenta somente policy `DRAFT`.
- Tentar aposentar policy `ACTIVE` deve falhar com SQLSTATE `P0001` e reason
  code `POLICY_ACTIVE_REPLACEMENT_REQUIRED`.
- Policy `ACTIVE` só pode ser substituída por `verified_access_activate_policy`.
- Não permite deixar condomínio sem policy ativa.
- `RETIRED` só pode ser tratado como idempotente quando a mesma
  `p_idempotency_key` já tiver concluído a aposentadoria da mesma policy.
- Escreve audit `POLICY_RETIRED`.
- Enfileira outbox idempotente `POLICY_DRAFT_RETIRED` se o contrato futuro
  mantiver esse evento; não gera reavaliação de policy ativa.

### 7.4 Contrato de `p_policy jsonb`

`p_policy` deve ser objeto JSON. Payload que não seja objeto, contenha chave
desconhecida, contenha campo proibido ou contenha tipo inválido deve falhar com
SQLSTATE `22023`. Checks de domínio das constraints existentes continuam
falhando com `23514`; unicidade continua falhando com `23505`.

Allowlist exata de campos configuráveis:

| Campo | Tipo JSON | Regra |
|---|---|---|
| `visitor_identity_mode` | string | `DISABLED`, `OPTIONAL` ou `REQUIRED` |
| `service_identity_mode` | string | `DISABLED`, `OPTIONAL` ou `REQUIRED` |
| `minimum_identity_assurance_level` | string | `SELF_DECLARED`, `CONTACT_VERIFIED`, `DOCUMENT_CAPTURED`, `DOCUMENT_VERIFIED`, `LIVENESS_VERIFIED`, `IDENTITY_VERIFIED` ou `MANUAL_VERIFIED` |
| `visitor_background_mode` | string | `DISABLED`, `OPTIONAL` ou `REQUIRED` |
| `service_background_mode` | string | `DISABLED`, `OPTIONAL` ou `REQUIRED` |
| `network_identity_mode` | string | `DISABLED` ou `EVALUATE_ONLY` |
| `network_signal_mode` | string | `DISABLED`, `EVALUATE_ONLY` ou `APPLY_CONFIGURED_EFFECT` |
| `network_signal_min_severity` | string | `LOW`, `MEDIUM`, `HIGH` ou `CRITICAL` |
| `network_signal_rules` | object | objeto sanitizado; efeitos somente da allowlist; sem `AUTO_DENY_NETWORK`, `GLOBAL_DENIED` ou `PERMANENT_BLACKLIST` |
| `network_hold_enabled` | boolean | `true` somente com `network_signal_mode = 'APPLY_CONFIGURED_EFFECT'`; não habilita feature |
| `timezone` | string | timezone IANA não vazio, validado pela mesma regra da policy |
| `invitation_ttl_minutes` | number integer | inteiro entre 5 e 43200 |
| `public_session_ttl_minutes` | number integer | inteiro entre 5 e 1440 |
| `max_visitor_participants` | number integer | inteiro entre 1 e 100 |
| `max_service_participants` | number integer | inteiro entre 1 e 100 |
| `max_request_duration_minutes` | number integer | inteiro entre 15 e 525600 |
| `min_notice_minutes` | number integer | inteiro entre 0 e 525600 |
| `max_notice_days` | number integer | inteiro entre 1 e 3650 |
| `allow_open_slots` | boolean | booleano |
| `privacy_approval_reference` | string ou null | obrigatória quando identidade for `OPTIONAL` ou `REQUIRED` |
| `background_approval_reference` | string ou null | obrigatória quando background for diferente de `DISABLED` |
| `network_approval_reference` | string ou null | obrigatória quando rede for diferente de `DISABLED` ou houver regra/hold de rede |
| `retention_settings` | object | objeto sanitizado, sem PII/secrets |
| `additional_settings` | object | objeto sanitizado, sem PII/secrets |

Campos proibidos em `p_policy`:

- `id`
- `condominium_id`
- `version`
- `status`
- `schema_version`
- `content_checksum`
- `created_by_actor_type`
- `created_by_actor_id`
- `created_at`
- `approved_by_actor_id`
- `approved_at`
- `activated_by_actor_type`
- `activated_by_actor_id`
- `activated_at`
- `retired_at`
- `updated_at`

Regras de mapeamento:

- Rejeitar qualquer chave que não esteja na allowlist ou na lista proibida.
- Rejeitar campo proibido mesmo que o valor seja `null`.
- Validar tipo antes de aplicar domínio.
- Mapear explicitamente cada chave permitida para coluna conhecida.
- Não aceitar `actor`, `actor_id`, `created_by_*` ou equivalentes dentro do
  JSON.
- `p_actor_id` vem somente do parâmetro da RPC e não pode ser sobrescrito.
- `condominium_id` vem somente de `p_condominium_id`.
- `version` é calculada sob lock como próxima versão do condomínio.
- `status` é sempre `DRAFT` na criação.
- `schema_version` e `content_checksum` são calculados/definidos no servidor.
- `p_base_policy_id` de outro condomínio falha com `23503` ou `P0001`,
  conforme a implementação futura escolher para validação transacional.

## 8. Regras Transacionais de Policies

- Deve existir no máximo uma policy `ACTIVE` por condomínio.
- Implementar índice único parcial sugerido:
  `ux_verified_access_policies_one_active_per_condominium` sobre
  `(condominium_id)` onde `status = 'ACTIVE'`.
- Policy `ACTIVE` é imutável, exceto campos operacionais explicitamente
  permitidos pelo contrato futuro, se houver.
- `verified_access_activate_policy` é o único caminho para substituir uma policy
  `ACTIVE`; ele aposenta a `ACTIVE` anterior e ativa a nova `DRAFT` na mesma
  transação.
- `verified_access_retire_policy` aposenta somente `DRAFT`; `ACTIVE` falha com
  `P0001` e reason `POLICY_ACTIVE_REPLACEMENT_REQUIRED`.
- Nenhuma operação pode deixar um condomínio sem policy ativa quando já existia
  uma `ACTIVE`.
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
- As três RPCs de policy são os únicos caminhos da Fase 1C que escrevem
  audit/outbox transacionais. Triggers de state machine e policy não escrevem
  audit/outbox.
- Ativação de policy deve registrar audit e outbox idempotente na mesma
  transação. Aposentadoria de `DRAFT` deve registrar audit e só enfileirar
  outbox se o contrato futuro mantiver evento específico para draft.

## 9. Audit e Outbox

### 9.1 Payload permitido

Audit/outbox podem conter:

- IDs UUID internos.
- `condominium_id` quando a entidade for local.
- `network_subject_id` somente em eventos internos de RPC autorizada, nunca em
  payload público. Na Fase 1C documental final, as RPCs permitidas são apenas de
  policy e normalmente não precisam de `network_subject_id`.
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
- `verified_access:policy:draft_created:{policy_id}:{version}`
- `verified_access:policy:draft_retired:{policy_id}:{reason_code}`

### 9.4 Garantias

- Audit é append-only.
- Outbox é idempotente por `deduplication_key`.
- Helper de outbox deve retornar o evento existente quando a chave já existir,
  mas somente quando chamado internamente por uma das três RPCs de policy.
- Campos de negócio da outbox permanecem imutáveis depois de inseridos.
- Audit/outbox devem ser gravados na mesma transação da alteração de domínio
  executada pelas RPCs de policy.
- Falha ao escrever audit/outbox deve abortar a alteração de domínio.
- Triggers de validação de state machine não chamam helpers e não gravam
  audit/outbox.
- Processador externo permanece fora de escopo.

## 10. Matriz de RLS e Grants Planejada

| Superfície | PUBLIC | anon | authenticated | service_role | Funções internas | RPCs de policy |
|---|---|---|---|---|---|---|
| Tabelas locais 1A | nenhum grant novo | nenhum grant novo | nenhum grant direto novo | preservar grants mínimos existentes; não ampliar sem teste | triggers `security invoker` apenas validam `OLD`/`NEW` | sem acesso direto; RPC opera por validação própria |
| Tabelas centrais 1B | nenhum | nenhum | nenhum | nenhum | triggers `security invoker` apenas validam `OLD`/`NEW` | nenhum acesso central |
| `verified_access_audit_events` | nenhum | nenhum | nenhum | preservar mínimo existente; nenhum EXECUTE em helper | sem chamada por triggers | RPCs inserem via helper interno |
| `verified_access_outbox_events` | nenhum | nenhum | nenhum | preservar mínimo existente; nenhum EXECUTE em helper | sem chamada por triggers | RPCs inserem via helper interno |
| Helpers `security invoker` | execute revogado | execute revogado | execute revogado | execute revogado | chamados por triggers; só validam | não chamados diretamente |
| Helpers `security definer` audit/outbox | execute revogado | execute revogado | execute revogado | execute revogado | não chamados por triggers | chamados somente internamente pelas três RPCs de policy |
| `verified_access_create_policy_draft` | revogado | revogado | revogado por padrão | grant somente se contrato autorizar role técnica; não herda acesso aos helpers | n/a | security definer com validação e allowlist de `p_policy` |
| `verified_access_activate_policy` | revogado | revogado | revogado por padrão | grant somente se contrato autorizar role técnica; único caminho para substituir `ACTIVE` | n/a | security definer transacional |
| `verified_access_retire_policy` | revogado | revogado | revogado por padrão | grant somente se contrato autorizar role técnica; aposenta somente `DRAFT` | n/a | security definer transacional |

Princípios:

- Revogar privilégios preexistentes antes de conceder grants mínimos.
- Não criar policy RLS `USING (true)`.
- Não conceder operação sensível ao backoffice atual sem RBAC forte.
- Testar permissões com roles reais: `anon`, `authenticated`, `service_role`.
- Confirmar que `service_role` não possui EXECUTE nos helpers
  `security definer` de audit/outbox.

## 11. Plano de Testes da Fase 1C

### 11.1 pgTAP

- Existência das novas funções, triggers, constraints e RPCs.
- `search_path` fixo em funções `security definer`.
- Execução revogada de `PUBLIC`, `anon`, `authenticated` e `service_role`
  quando aplicável.
- Índice único parcial de uma policy `ACTIVE` por condomínio.
- Checks de payload sanitizado em audit/outbox.
- Checks de `network_signal_rules` rejeitando auto-deny e aliases.
- Triggers de state machine existem como `security invoker` e não dependem dos
  helpers `security definer` de audit/outbox.
- Helpers de audit/outbox possuem `search_path = public, pg_temp` e EXECUTE
  revogado de `PUBLIC`, `anon`, `authenticated` e `service_role`.

### 11.2 Integração SQL

- Transições válidas de cada state machine.
- Transições proibidas retornando `P0001`.
- Estados fora do domínio retornando `23514`.
- FKs compostas preservando tenant isolation retornando `23503`.
- Policy draft criada sem ativar.
- `p_policy` válido cria policy `DRAFT` com `condominium_id`, `version`,
  `status`, checksum e actor definidos pela RPC.
- `p_policy` com chave desconhecida falha com `22023`.
- `p_policy` com campo proibido falha com `22023`.
- `p_policy` com tipo inválido falha com `22023`.
- Tentativa de definir `ACTIVE`, `version`, checksum ou actor via `p_policy`
  falha com `22023`.
- Base policy de outro condomínio falha.
- Ativação aposenta policy ativa anterior e ativa a nova na mesma transação.
- `verified_access_activate_policy` é o único caminho para substituir `ACTIVE`.
- Tentativa de alterar policy `ACTIVE` falha.
- `verified_access_retire_policy` aposenta somente `DRAFT`.
- `verified_access_retire_policy` em `ACTIVE` falha com `P0001` e reason
  `POLICY_ACTIVE_REPLACEMENT_REQUIRED`.
- Retirement de `RETIRED` só é idempotente com a mesma idempotency key já
  concluída.

### 11.3 Runtime role checks

- `anon` não lê nem escreve tabelas locais ou centrais.
- `authenticated` não escreve diretamente.
- `service_role` não ganha grants centrais da rede.
- RPCs de policy não ficam executáveis por roles não autorizadas.
- Helpers internos não ficam executáveis por roles públicas.
- Helpers internos não ficam executáveis por `service_role`.

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
- Triggers de state machine não gravam audit/outbox.
- Audit/outbox transacionais são verificados somente nas três RPCs de policy.

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
6. Dropar funções de validação de policy.
7. Dropar funções de state machine locais.
8. Dropar funções de state machine centrais.
9. Dropar helpers de audit/outbox criados na Fase 1C.
10. Dropar índices/constraints auxiliares da Fase 1C, incluindo o índice único
    parcial de policy ativa, se criado.
11. Preservar todas as tabelas 1A e 1B.
12. Preservar feature flags 1A e 1B desligadas.
13. Preservar `persons`, app Expo e objetos não relacionados.

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
