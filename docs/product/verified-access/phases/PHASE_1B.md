# Fase 1B — fundação inerte da Rede Confia

## 1. Objetivo

Criar o modelo pseudonimizado central da Rede Confia, com segurança default-deny, sem disponibilizar correlação, busca, investigação operacional, ativação de sinal ou efeito sobre acessos.

Resultado:

```text
schema central
+ constraints estáticas
+ RLS/grants fechados
+ feature flags desligadas
+ testes de não propagação
+ rollback/reaplicação
```

## 2. Escopo incluído

- ADR da fundação de rede;
- três feature flags desligadas;
- sete tabelas centrais;
- FKs, constraints e índices;
- RLS;
- revogação total de grants públicos e de tenant;
- testes pgTAP e integração;
- rollback;
- workflow de CI.

## 3. Fora do escopo

- HMAC real;
- canonicalização;
- Edge Function;
- API;
- RPC de busca;
- criação operacional de sujeito;
- abertura/revisão de caso;
- ativação de sinal;
- contestação pública;
- alteração de participante;
- credencial hold;
- UI;
- provider.

## 4. Feature flags

Cadastrar com `enabled = false`:

```text
VERIFIED_ACCESS_NETWORK_IDENTITY
VERIFIED_ACCESS_NETWORK_SIGNALS
VERIFIED_ACCESS_NETWORK_HOLD
```

Não alterar:

```text
INTERCOM
VERIFIED_ACCESS
VERIFIED_ACCESS_BACKGROUND_CHECK
```

## 5. Tabelas

### 5.1 `verified_access_network_subjects`

Campos mínimos:

```text
id uuid PK
status text NOT NULL
identity_assurance_level text NOT NULL
first_verified_at timestamptz NOT NULL
last_verified_at timestamptz NOT NULL
revalidation_due_at timestamptz NULL
retention_until timestamptz NULL
merged_into_subject_id uuid NULL
created_at timestamptz NOT NULL
updated_at timestamptz NOT NULL
```

Status:

```text
ACTIVE
UNDER_REVIEW
DISPUTED
MERGED
RETIRED
```

Regras:

- sem PII;
- não pode mergear em si;
- `MERGED` exige destino;
- datas coerentes.

### 5.2 `verified_access_network_subject_identifiers`

```text
id uuid PK
network_subject_id uuid NOT NULL
identifier_type text NOT NULL
identifier_hmac text NOT NULL
hmac_key_version integer NOT NULL
canonicalization_version integer NOT NULL
status text NOT NULL
is_primary boolean NOT NULL
verified_at timestamptz NOT NULL
expires_at timestamptz NULL
revoked_at timestamptz NULL
created_at timestamptz NOT NULL
```

Tipos permitidos:

```text
CPF
RNM
PASSPORT_WITH_ISSUER
```

Proibidos:

```text
PHONE
EMAIL
NAME
FACE
BIOMETRIC
```

Unicidade ativa:

```text
identifier_type
identifier_hmac
hmac_key_version
canonicalization_version
```

No máximo um identificador primário ativo por sujeito/tipo.

Nenhuma função SQL calcula HMAC.

### 5.3 `verified_access_network_subject_links`

```text
id uuid PK
network_subject_id uuid NOT NULL
condominium_id uuid NOT NULL
identity_profile_id uuid NOT NULL
link_status text NOT NULL
link_reason text NOT NULL
identity_assurance_level text NOT NULL
linked_at timestamptz NOT NULL
unlinked_at timestamptz NULL
created_at timestamptz NOT NULL
```

Regras:

- FK composta para `verified_access_identity_profiles(id, condominium_id)`;
- um profile possui no máximo um link ativo;
- assurance aceita somente:

```text
DOCUMENT_VERIFIED
IDENTITY_VERIFIED
MANUAL_VERIFIED
```

- tenant não recebe `network_subject_id`.

### 5.4 `verified_access_network_security_cases`

```text
id uuid PK
network_subject_id uuid NOT NULL
source_type text NOT NULL
source_condominium_id uuid NULL
source_participant_id uuid NULL
category text NOT NULL
severity text NOT NULL
status text NOT NULL
evidence_assurance_level text NOT NULL
summary_code text NOT NULL
reported_by_actor_type text NOT NULL
reported_by_actor_id text NOT NULL
reported_at timestamptz NOT NULL
triaged_by_actor_id text NULL
triaged_at timestamptz NULL
review_due_at timestamptz NULL
substantiated_at timestamptz NULL
dismissed_at timestamptz NULL
closed_at timestamptz NULL
evidence_reference_hash text NULL
metadata_sanitized jsonb NOT NULL DEFAULT '{}'
created_at timestamptz NOT NULL
updated_at timestamptz NOT NULL
```

Source:

```text
CONDOMINIUM_REPORT
PLATFORM_SECURITY
IDENTITY_PROVIDER
BACKGROUND_PROVIDER
PRIVACY_CORRECTION
```

Status:

```text
REPORTED
TRIAGE
UNDER_REVIEW
SUBSTANTIATED
DISMISSED
CLOSED
EXPIRED
```

Categorias de abertura:

```text
IDENTITY_IMPERSONATION_SUSPECTED
DOCUMENT_FRAUD_SUSPECTED
CREDENTIAL_COMPROMISE_SUSPECTED
ACCOUNT_TAKEOVER_SUSPECTED
REPEATED_IDENTITY_MANIPULATION_SUSPECTED
PLATFORM_SECURITY_INCIDENT
OFFICIAL_SOURCE_REVALIDATION_REQUIRED
```

Caso aberto não cria sinal.

### 5.5 `verified_access_network_signals`

```text
id uuid PK
network_subject_id uuid NOT NULL
source_case_id uuid NOT NULL
category text NOT NULL
severity text NOT NULL
effect text NOT NULL
status text NOT NULL
policy_version integer NOT NULL
reason_code text NOT NULL
valid_from timestamptz NOT NULL
expires_at timestamptz NOT NULL
review_due_at timestamptz NOT NULL
proposed_by_actor_type text NOT NULL
proposed_by_actor_id text NOT NULL
proposed_at timestamptz NOT NULL
activated_by_actor_id text NULL
activated_at timestamptz NULL
suspended_at timestamptz NULL
revoked_at timestamptz NULL
revocation_reason_code text NULL
created_at timestamptz NOT NULL
updated_at timestamptz NOT NULL
```

Categorias confirmadas:

```text
IDENTITY_IMPERSONATION_CONFIRMED
DOCUMENT_FRAUD_CONFIRMED
CREDENTIAL_COMPROMISED
ACCOUNT_TAKEOVER_CONFIRMED
REPEATED_IDENTITY_MANIPULATION_CONFIRMED
PLATFORM_SECURITY_SUSPENSION
OFFICIAL_SOURCE_REVALIDATION_REQUIRED
```

Efeitos permitidos:

```text
INFORM_AUTHORIZED_REVIEWER
REVALIDATE_IDENTITY
REQUERY_OFFICIAL_SOURCE
REQUIRE_MANUAL_REVIEW
HOLD_CREDENTIAL
```

Status:

```text
DRAFT
UNDER_REVIEW
ACTIVE
SUSPENDED
REVOKED
EXPIRED
REJECTED
```

Regras estáticas:

- expiração obrigatória;
- `expires_at > valid_from`;
- sem auto-deny;
- sem permanência;
- source case obrigatório;
- nesta fase nenhuma operação ativa sinal.

### 5.6 `verified_access_network_signal_reviews`

```text
id uuid PK
signal_id uuid NOT NULL
reviewer_actor_id text NOT NULL
reviewer_role text NOT NULL
decision text NOT NULL
reason_code text NOT NULL
reviewed_at timestamptz NOT NULL
created_at timestamptz NOT NULL
UNIQUE(signal_id, reviewer_actor_id)
```

Decisão:

```text
APPROVE
REJECT
REQUEST_CHANGES
```

A Fase 1C implementará contagem e independência operacional.

### 5.7 `verified_access_network_appeals`

```text
id uuid PK
network_subject_id uuid NOT NULL
signal_id uuid NULL
status text NOT NULL
request_reference_hash text NOT NULL
opened_at timestamptz NOT NULL
review_due_at timestamptz NOT NULL
resolution_code text NULL
resolved_by_actor_id text NULL
resolved_at timestamptz NULL
created_at timestamptz NOT NULL
updated_at timestamptz NOT NULL
```

Status:

```text
OPEN
UNDER_REVIEW
UPHELD
AMENDED
REVOKED
CLOSED
```

Sem texto livre ou PII.

## 6. Integridade

- Relações centrais por FKs.
- Relação com profile local usa FK composta.
- Participant de origem, quando informado, pertence ao condomínio de origem.
- Não aceitar self-merge.
- Sinal nunca sem expiração.
- Metadata JSON deve ser objeto e sanitizada.
- Não armazenar valor canônico de identificador.
- Não criar trigger local que propague negativa.

## 7. RLS e grants

Para as sete tabelas:

- RLS habilitada;
- sem policy;
- `REVOKE ALL` de `PUBLIC`, `anon`, `authenticated` e `service_role`;
- sem view;
- sem RPC;
- sem função `security definer`.

A Fase 1C adicionará portas restritas.

## 8. Testes obrigatórios

### Schema

- sete tabelas existem;
- features existem e estão false;
- nenhuma coluna com semântica de PII;
- RLS habilitada;
- nenhuma policy;
- nenhum grant direto;
- nenhuma função de HMAC;
- nenhum efeito proibido.

### Identifiers

- tipos permitidos;
- tipos proibidos;
- unicidade ativa;
- múltiplas versões controladas;
- `REVOKED` exige timestamp;
- `EXPIRED` exige expiração;
- primário ativo único.

### Links

- profile/condomínio coerentes;
- assurance insuficiente rejeitado;
- dois links ativos para o mesmo profile rejeitados;
- links de condomínios diferentes podem apontar ao mesmo subject sem exposição.

### Cases/signals

- case aberto não cria signal;
- signal sem expiração rejeitado;
- efeito proibido rejeitado;
- signal não altera participante;
- nenhuma negativa local cria case/signal;
- source participant cruzado rejeitado.

### RLS/grants

Testar:

```text
anon
authenticated
service_role
```

Nenhum possui acesso operacional às tabelas centrais.

### Rollback

- remover somente objetos da 1B;
- preservar Fase 1A;
- preservar `persons`;
- preservar `INTERCOM`;
- preservar features da 1A;
- reaplicar e retestar.

## 9. Migrations

Sugestão:

```text
*_verified_access_network_foundation.sql
*_verified_access_network_security.sql
```

Criar rollback específico da 1B.

Não alterar migrations da 1A.

## 10. CI

Workflow:

```text
.github/workflows/verified-access-phase-1b.yml
```

Jobs:

```text
database
admin-web
```

Database:

- start Supabase;
- reset;
- pgTAP 1A + 1B;
- integração;
- role checks;
- db lint;
- rollback 1B;
- verificar preservação 1A;
- reset/reapply;
- smoke.

Artifacts sanitizados.

## 11. Gate de conclusão

- CI verde;
- rollback e reaplicação verdes;
- nenhum acesso central;
- nenhuma PII;
- nenhuma propagação;
- features desligadas;
- nenhuma migration remota;
- PR draft para revisão.
