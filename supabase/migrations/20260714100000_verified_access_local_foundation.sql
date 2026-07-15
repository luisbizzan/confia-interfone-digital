insert into public.condominium_features (condominium_id, feature_key, enabled)
select id, 'VERIFIED_ACCESS', false
from public.condominiums
on conflict (condominium_id, feature_key) do update
  set enabled = public.condominium_features.enabled;

insert into public.condominium_features (condominium_id, feature_key, enabled)
select id, 'VERIFIED_ACCESS_BACKGROUND_CHECK', false
from public.condominiums
on conflict (condominium_id, feature_key) do update
  set enabled = public.condominium_features.enabled;

create unique index if not exists ux_units_id_condominium_id
on public.units(id, condominium_id);

create unique index if not exists ux_user_profiles_id_condominium_id
on public.user_profiles(id, condominium_id);

create table if not exists public.verified_access_service_types (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  default_name text not null,
  requires_description boolean not null default false,
  is_active boolean not null default true,
  sort_order integer not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint verified_access_service_types_code_uppercase_check
    check (code = upper(trim(code))),
  constraint verified_access_service_types_code_allowed_check
    check (code in (
      'CONSTRUCTION',
      'GARDENING',
      'PLUMBING',
      'ELECTRICAL',
      'POOL',
      'CLEANING',
      'ELEVATOR_MAINTENANCE',
      'TELECOM',
      'DELIVERY_ASSEMBLY',
      'OTHER'
    )),
  constraint verified_access_service_types_default_name_check
    check (char_length(trim(default_name)) between 1 and 120),
  constraint verified_access_service_types_sort_order_check
    check (sort_order > 0),
  constraint verified_access_service_types_other_description_check
    check (code <> 'OTHER' or requires_description = true)
);

insert into public.verified_access_service_types (code, default_name, requires_description, sort_order)
values
  ('CONSTRUCTION', 'Obra', false, 10),
  ('GARDENING', 'Jardinagem', false, 20),
  ('PLUMBING', 'Hidraulica', false, 30),
  ('ELECTRICAL', 'Eletrica', false, 40),
  ('POOL', 'Piscina', false, 50),
  ('CLEANING', 'Limpeza', false, 60),
  ('ELEVATOR_MAINTENANCE', 'Manutencao de elevador', false, 70),
  ('TELECOM', 'Telecomunicacoes', false, 80),
  ('DELIVERY_ASSEMBLY', 'Entrega ou montagem', false, 90),
  ('OTHER', 'Outros', true, 100)
on conflict (code) do update
  set default_name = excluded.default_name,
      requires_description = excluded.requires_description,
      sort_order = excluded.sort_order,
      updated_at = now();

create or replace function public.verified_access_service_type_requires_description(p_service_type_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(vast.requires_description, false)
  from public.verified_access_service_types vast
  where vast.id = p_service_type_id
$$;

create table if not exists public.verified_access_condominium_service_types (
  condominium_id uuid not null references public.condominiums(id) on delete cascade,
  service_type_id uuid not null references public.verified_access_service_types(id) on delete restrict,
  is_enabled boolean not null default true,
  display_name_override text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (condominium_id, service_type_id),
  constraint verified_access_condominium_service_name_check
    check (display_name_override is null or char_length(trim(display_name_override)) between 1 and 120)
);

create table if not exists public.verified_access_policies (
  id uuid primary key default gen_random_uuid(),
  condominium_id uuid not null references public.condominiums(id) on delete cascade,
  version integer not null,
  schema_version integer not null default 2,
  status text not null default 'DRAFT',
  identity_mode text not null default 'DISABLED',
  minimum_identity_assurance_level text not null default 'SELF_DECLARED',
  background_check_mode text not null default 'DISABLED',
  background_approval_reference text,
  network_identity_mode text not null default 'DISABLED',
  network_signal_mode text not null default 'DISABLED',
  network_hold_enabled boolean not null default false,
  network_approval_reference text,
  network_signal_rules jsonb not null default '[]'::jsonb,
  retention_days integer not null default 90,
  sensitive_retention_days integer not null default 30,
  policy_content_checksum text not null,
  approved_by_actor_id text,
  approved_at timestamptz,
  activated_by_actor_id text,
  activated_at timestamptz,
  retired_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint verified_access_policies_version_check
    check (version > 0),
  constraint verified_access_policies_schema_version_check
    check (schema_version = 2),
  constraint verified_access_policies_status_check
    check (status in ('DRAFT', 'ACTIVE', 'RETIRED')),
  constraint verified_access_policies_identity_mode_check
    check (identity_mode in ('DISABLED', 'OPTIONAL', 'REQUIRED')),
  constraint verified_access_policies_assurance_level_check
    check (minimum_identity_assurance_level in (
      'SELF_DECLARED',
      'CONTACT_VERIFIED',
      'DOCUMENT_CAPTURED',
      'DOCUMENT_VERIFIED',
      'LIVENESS_VERIFIED',
      'IDENTITY_VERIFIED',
      'MANUAL_VERIFIED'
    )),
  constraint verified_access_policies_background_mode_check
    check (background_check_mode in ('DISABLED', 'OPTIONAL', 'REQUIRED')),
  constraint verified_access_policies_network_identity_mode_check
    check (network_identity_mode in ('DISABLED', 'EVALUATE_ONLY')),
  constraint verified_access_policies_network_signal_mode_check
    check (network_signal_mode in ('DISABLED', 'EVALUATE_ONLY', 'APPLY_CONFIGURED_EFFECT')),
  constraint verified_access_policies_background_approval_check
    check (background_check_mode = 'DISABLED' or nullif(trim(coalesce(background_approval_reference, '')), '') is not null),
  constraint verified_access_policies_network_approval_check
    check (
      (network_identity_mode = 'DISABLED' and network_signal_mode = 'DISABLED' and network_hold_enabled = false)
      or nullif(trim(coalesce(network_approval_reference, '')), '') is not null
    ),
  constraint verified_access_policies_network_hold_check
    check (network_hold_enabled = false or network_signal_mode = 'APPLY_CONFIGURED_EFFECT'),
  constraint verified_access_policies_retention_check
    check (retention_days between 1 and 3650 and sensitive_retention_days between 1 and retention_days),
  constraint verified_access_policies_checksum_check
    check (char_length(trim(policy_content_checksum)) between 16 and 128),
  constraint verified_access_policies_forbidden_network_rules_check
    check (
      position('AUTO_DENY_NETWORK' in upper(network_signal_rules::text)) = 0
      and position('GLOBAL_DENIED' in upper(network_signal_rules::text)) = 0
      and position('PERMANENT_BLACKLIST' in upper(network_signal_rules::text)) = 0
    )
);

create unique index if not exists ux_verified_access_policies_id_condominium_id
on public.verified_access_policies(id, condominium_id);

create unique index if not exists ux_verified_access_policies_condominium_version
on public.verified_access_policies(condominium_id, version);

create unique index if not exists ux_verified_access_policies_one_active_per_condominium
on public.verified_access_policies(condominium_id)
where status = 'ACTIVE';

create table if not exists public.verified_access_requests (
  id uuid primary key default gen_random_uuid(),
  condominium_id uuid not null references public.condominiums(id) on delete cascade,
  unit_id uuid not null,
  requested_by_user_id uuid not null,
  request_type text not null,
  status text not null default 'DRAFT',
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  timezone text not null,
  participant_limit integer not null,
  policy_id uuid not null,
  policy_version integer not null,
  version integer not null default 1,
  operational_notes text,
  visit_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint verified_access_requests_unit_tenant_fk
    foreign key (unit_id, condominium_id)
    references public.units(id, condominium_id)
    on delete restrict,
  constraint verified_access_requests_requester_tenant_fk
    foreign key (requested_by_user_id, condominium_id)
    references public.user_profiles(id, condominium_id)
    on delete restrict,
  constraint verified_access_requests_policy_tenant_fk
    foreign key (policy_id, condominium_id)
    references public.verified_access_policies(id, condominium_id)
    on delete restrict,
  constraint verified_access_requests_type_check
    check (request_type in ('VISITOR', 'SERVICE_PROVIDER')),
  constraint verified_access_requests_status_check
    check (status in ('DRAFT', 'INVITATIONS_PENDING', 'IN_PROGRESS', 'PARTIALLY_ELIGIBLE', 'ELIGIBLE', 'COMPLETED', 'CANCELLED', 'EXPIRED')),
  constraint verified_access_requests_period_check
    check (starts_at < ends_at),
  constraint verified_access_requests_participant_limit_check
    check (participant_limit > 0 and participant_limit <= 100),
  constraint verified_access_requests_policy_version_check
    check (policy_version > 0),
  constraint verified_access_requests_version_check
    check (version > 0),
  constraint verified_access_requests_timezone_check
    check (char_length(trim(timezone)) between 1 and 64),
  constraint verified_access_requests_operational_notes_check
    check (operational_notes is null or char_length(operational_notes) <= 1000),
  constraint verified_access_requests_visit_reason_check
    check (visit_reason is null or char_length(visit_reason) <= 300)
);

create unique index if not exists ux_verified_access_requests_id_condominium_id
on public.verified_access_requests(id, condominium_id);

create index if not exists idx_verified_access_requests_condominium_status_window
on public.verified_access_requests(condominium_id, status, starts_at, ends_at);

create index if not exists idx_verified_access_requests_unit_window
on public.verified_access_requests(unit_id, starts_at, ends_at);

create table if not exists public.verified_access_service_request_details (
  request_id uuid primary key,
  condominium_id uuid not null references public.condominiums(id) on delete cascade,
  service_type_id uuid not null references public.verified_access_service_types(id) on delete restrict,
  other_description text,
  company_name text,
  company_document_ciphertext bytea,
  company_document_hmac text,
  company_document_hmac_key_version integer,
  company_document_encryption_key_version integer,
  work_description text,
  destination_area text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint verified_access_service_details_request_tenant_fk
    foreign key (request_id, condominium_id)
    references public.verified_access_requests(id, condominium_id)
    on delete cascade,
  constraint verified_access_service_details_company_document_key_check
    check (
      company_document_ciphertext is null
      or (
        company_document_hmac is not null
        and company_document_hmac_key_version is not null
        and company_document_encryption_key_version is not null
      )
    ),
  constraint verified_access_service_details_company_document_hmac_check
    check (company_document_hmac is null or char_length(trim(company_document_hmac)) between 16 and 256),
  constraint verified_access_service_details_company_document_key_positive_check
    check (
      (company_document_hmac_key_version is null or company_document_hmac_key_version > 0)
      and (company_document_encryption_key_version is null or company_document_encryption_key_version > 0)
    ),
  constraint verified_access_service_details_other_description_check
    check (
      not public.verified_access_service_type_requires_description(service_type_id)
      or nullif(trim(coalesce(other_description, '')), '') is not null
    ),
  constraint verified_access_service_details_text_size_check
    check (
      (other_description is null or char_length(other_description) <= 300)
      and (company_name is null or char_length(company_name) <= 200)
      and (work_description is null or char_length(work_description) <= 1000)
      and (destination_area is null or char_length(destination_area) <= 200)
    )
);

create index if not exists idx_verified_access_service_details_condominium_service
on public.verified_access_service_request_details(condominium_id, service_type_id);

create table if not exists public.verified_access_participant_slots (
  id uuid primary key default gen_random_uuid(),
  condominium_id uuid not null references public.condominiums(id) on delete cascade,
  request_id uuid not null,
  slot_number integer not null,
  status text not null default 'OPEN',
  claimed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint verified_access_slots_request_tenant_fk
    foreign key (request_id, condominium_id)
    references public.verified_access_requests(id, condominium_id)
    on delete cascade,
  constraint verified_access_slots_number_check
    check (slot_number > 0),
  constraint verified_access_slots_status_check
    check (status in ('OPEN', 'RESERVED', 'CLAIMED', 'CANCELLED', 'EXPIRED')),
  constraint verified_access_slots_claimed_at_check
    check ((status in ('CLAIMED', 'RESERVED') and claimed_at is not null) or (status not in ('CLAIMED', 'RESERVED')))
);

create unique index if not exists ux_verified_access_slots_id_condominium_id
on public.verified_access_participant_slots(id, condominium_id);

create unique index if not exists ux_verified_access_slots_request_number
on public.verified_access_participant_slots(request_id, slot_number);

create index if not exists idx_verified_access_slots_condominium_status
on public.verified_access_participant_slots(condominium_id, status);

create table if not exists public.verified_access_identity_profiles (
  id uuid primary key default gen_random_uuid(),
  condominium_id uuid not null references public.condominiums(id) on delete cascade,
  full_name_ciphertext bytea,
  full_name_hmac text,
  document_number_ciphertext bytea,
  document_number_hmac text,
  birth_date_ciphertext bytea,
  birth_date_hmac text,
  phone_ciphertext bytea,
  phone_hmac text,
  mother_name_ciphertext bytea,
  mother_name_hmac text,
  father_name_ciphertext bytea,
  father_name_hmac text,
  tenant_subject_hmac text,
  encryption_key_version integer,
  hmac_key_version integer,
  identity_assurance_level text not null default 'SELF_DECLARED',
  retention_expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint verified_access_identity_profiles_assurance_check
    check (identity_assurance_level in (
      'SELF_DECLARED',
      'CONTACT_VERIFIED',
      'DOCUMENT_CAPTURED',
      'DOCUMENT_VERIFIED',
      'LIVENESS_VERIFIED',
      'IDENTITY_VERIFIED',
      'MANUAL_VERIFIED'
    )),
  constraint verified_access_identity_profiles_key_versions_check
    check (
      (encryption_key_version is null or encryption_key_version > 0)
      and (hmac_key_version is null or hmac_key_version > 0)
    ),
  constraint verified_access_identity_profiles_ciphertext_key_check
    check (
      (
        full_name_ciphertext is null
        and document_number_ciphertext is null
        and birth_date_ciphertext is null
        and phone_ciphertext is null
        and mother_name_ciphertext is null
        and father_name_ciphertext is null
      )
      or encryption_key_version is not null
    ),
  constraint verified_access_identity_profiles_hmac_key_check
    check (
      (
        full_name_hmac is null
        and document_number_hmac is null
        and birth_date_hmac is null
        and phone_hmac is null
        and mother_name_hmac is null
        and father_name_hmac is null
        and tenant_subject_hmac is null
      )
      or hmac_key_version is not null
    )
);

create unique index if not exists ux_verified_access_identity_profiles_id_condominium_id
on public.verified_access_identity_profiles(id, condominium_id);

create unique index if not exists ux_verified_access_identity_profiles_tenant_subject_hmac
on public.verified_access_identity_profiles(condominium_id, tenant_subject_hmac, hmac_key_version)
where tenant_subject_hmac is not null;

create index if not exists idx_verified_access_identity_profiles_retention
on public.verified_access_identity_profiles(retention_expires_at)
where retention_expires_at is not null;

create table if not exists public.verified_access_participants (
  id uuid primary key default gen_random_uuid(),
  condominium_id uuid not null references public.condominiums(id) on delete cascade,
  request_id uuid not null,
  slot_id uuid not null unique,
  identity_profile_id uuid,
  registration_status text not null default 'NOT_STARTED',
  identity_status text not null default 'UNVERIFIED',
  background_status text not null default 'NOT_REQUIRED',
  network_status text not null default 'NOT_ENABLED',
  eligibility_status text not null default 'PENDING',
  local_decision text,
  local_decision_reason_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint verified_access_participants_request_tenant_fk
    foreign key (request_id, condominium_id)
    references public.verified_access_requests(id, condominium_id)
    on delete cascade,
  constraint verified_access_participants_slot_tenant_fk
    foreign key (slot_id, condominium_id)
    references public.verified_access_participant_slots(id, condominium_id)
    on delete restrict,
  constraint verified_access_participants_identity_profile_tenant_fk
    foreign key (identity_profile_id, condominium_id)
    references public.verified_access_identity_profiles(id, condominium_id)
    on delete restrict,
  constraint verified_access_participants_registration_status_check
    check (registration_status in ('NOT_STARTED', 'INVITED', 'IN_PROGRESS', 'SUBMITTED', 'CANCELLED', 'EXPIRED')),
  constraint verified_access_participants_identity_status_check
    check (identity_status in ('UNVERIFIED', 'SELF_DECLARED', 'CONTACT_VERIFIED', 'DOCUMENT_CAPTURED', 'DOCUMENT_VERIFIED', 'LIVENESS_VERIFIED', 'IDENTITY_VERIFIED', 'MANUAL_VERIFIED', 'INCONCLUSIVE', 'TECHNICAL_ERROR')),
  constraint verified_access_participants_background_status_check
    check (background_status in ('NOT_REQUIRED', 'NOT_STARTED', 'PENDING', 'NEGATIVE_CERTIFICATE', 'ADVERSE_INFORMATION_REVIEW', 'MANUAL_CONFIRMATION_REQUIRED', 'INCONCLUSIVE', 'PROVIDER_ERROR', 'EXPIRED')),
  constraint verified_access_participants_network_status_check
    check (network_status in ('NOT_ENABLED', 'NO_ACTIVE_NETWORK_SIGNAL', 'NETWORK_REVALIDATION_REQUIRED', 'NETWORK_MANUAL_REVIEW_REQUIRED', 'NETWORK_CREDENTIAL_HOLD', 'NETWORK_SIGNAL_EXPIRED', 'NETWORK_SIGNAL_REVOKED')),
  constraint verified_access_participants_eligibility_status_check
    check (eligibility_status in ('PENDING', 'ELIGIBLE', 'REVIEW_REQUIRED', 'CORRECTION_REQUIRED', 'DENIED_MANUAL', 'CANCELLED', 'EXPIRED')),
  constraint verified_access_participants_local_decision_check
    check (local_decision is null or local_decision in ('APPROVED', 'REVIEW_REQUIRED', 'CORRECTION_REQUIRED', 'DENIED_MANUAL', 'CANCELLED')),
  constraint verified_access_participants_local_decision_reason_check
    check (local_decision_reason_code is null or char_length(trim(local_decision_reason_code)) between 2 and 80)
);

create unique index if not exists ux_verified_access_participants_id_condominium_id
on public.verified_access_participants(id, condominium_id);

create index if not exists idx_verified_access_participants_request
on public.verified_access_participants(request_id, eligibility_status);

create index if not exists idx_verified_access_participants_identity_profile
on public.verified_access_participants(identity_profile_id)
where identity_profile_id is not null;

create table if not exists public.verified_access_eligibility_evaluations (
  id uuid primary key default gen_random_uuid(),
  condominium_id uuid not null references public.condominiums(id) on delete cascade,
  request_id uuid not null,
  participant_id uuid not null,
  policy_id uuid not null,
  policy_version integer not null,
  input_identity_status text not null,
  input_background_status text not null,
  input_network_status text not null default 'NOT_ENABLED',
  outcome text not null,
  reason_codes text[] not null default '{}'::text[],
  decision_source text not null,
  actor_user_id uuid,
  evaluated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint verified_access_evaluations_request_tenant_fk
    foreign key (request_id, condominium_id)
    references public.verified_access_requests(id, condominium_id)
    on delete cascade,
  constraint verified_access_evaluations_participant_tenant_fk
    foreign key (participant_id, condominium_id)
    references public.verified_access_participants(id, condominium_id)
    on delete cascade,
  constraint verified_access_evaluations_policy_tenant_fk
    foreign key (policy_id, condominium_id)
    references public.verified_access_policies(id, condominium_id)
    on delete restrict,
  constraint verified_access_evaluations_policy_version_check
    check (policy_version > 0),
  constraint verified_access_evaluations_outcome_check
    check (outcome in ('ELIGIBLE', 'REVIEW_REQUIRED', 'CORRECTION_REQUIRED', 'DENIED_MANUAL', 'CANCELLED', 'EXPIRED')),
  constraint verified_access_evaluations_decision_source_check
    check (decision_source in ('SYSTEM_RULES', 'HUMAN_REVIEW', 'TECHNICAL_RECONCILIATION')),
  constraint verified_access_evaluations_metadata_sanitized_check
    check (
      position('CPF' in upper(metadata::text)) = 0
      and position('DOCUMENTO' in upper(metadata::text)) = 0
      and position('TELEFONE' in upper(metadata::text)) = 0
      and position('BIOMETR' in upper(metadata::text)) = 0
      and position('CERTIDAO' in upper(metadata::text)) = 0
      and position('CERTIDÃO' in upper(metadata::text)) = 0
    )
);

create index if not exists idx_verified_access_evaluations_participant_created
on public.verified_access_eligibility_evaluations(participant_id, created_at desc);

create index if not exists idx_verified_access_evaluations_condominium_outcome
on public.verified_access_eligibility_evaluations(condominium_id, outcome, evaluated_at desc);

create table if not exists public.verified_access_outbox_events (
  id uuid primary key default gen_random_uuid(),
  condominium_id uuid not null references public.condominiums(id) on delete cascade,
  scope text not null default 'CONDOMINIUM',
  aggregate_type text not null,
  aggregate_id uuid not null,
  event_type text not null,
  event_version integer not null default 1,
  deduplication_key text not null,
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'PENDING',
  attempts integer not null default 0,
  locked_at timestamptz,
  locked_by text,
  next_attempt_at timestamptz not null default now(),
  last_error_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint verified_access_outbox_scope_check
    check (scope = 'CONDOMINIUM'),
  constraint verified_access_outbox_event_version_check
    check (event_version > 0),
  constraint verified_access_outbox_status_check
    check (status in ('PENDING', 'PROCESSING', 'PROCESSED', 'FAILED', 'DISCARDED')),
  constraint verified_access_outbox_attempts_check
    check (attempts >= 0),
  constraint verified_access_outbox_deduplication_key_check
    check (char_length(trim(deduplication_key)) between 8 and 200),
  constraint verified_access_outbox_payload_sanitized_check
    check (
      position('CPF' in upper(payload::text)) = 0
      and position('NOME' in upper(payload::text)) = 0
      and position('PHONE' in upper(payload::text)) = 0
      and position('TELEFONE' in upper(payload::text)) = 0
      and position('DOCUMENT' in upper(payload::text)) = 0
      and position('DOCUMENTO' in upper(payload::text)) = 0
      and position('TOKEN' in upper(payload::text)) = 0
      and position('CERTIDAO' in upper(payload::text)) = 0
      and position('CERTIDÃO' in upper(payload::text)) = 0
      and position('BIOMETR' in upper(payload::text)) = 0
    )
);

create unique index if not exists ux_verified_access_outbox_deduplication_key
on public.verified_access_outbox_events(deduplication_key);

create index if not exists idx_verified_access_outbox_pending
on public.verified_access_outbox_events(status, next_attempt_at, created_at)
where status in ('PENDING', 'FAILED');

create table if not exists public.verified_access_audit_events (
  id uuid primary key default gen_random_uuid(),
  condominium_id uuid not null references public.condominiums(id) on delete cascade,
  scope text not null default 'CONDOMINIUM',
  aggregate_type text not null,
  aggregate_id uuid not null,
  event_type text not null,
  actor_user_id uuid,
  actor_type text not null default 'SYSTEM',
  reason_code text,
  correlation_id text,
  metadata jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint verified_access_audit_scope_check
    check (scope = 'CONDOMINIUM'),
  constraint verified_access_audit_actor_type_check
    check (actor_type in ('SYSTEM', 'USER', 'SERVICE_ROLE', 'ADMIN')),
  constraint verified_access_audit_reason_code_check
    check (reason_code is null or char_length(trim(reason_code)) between 2 and 80),
  constraint verified_access_audit_correlation_id_check
    check (correlation_id is null or char_length(trim(correlation_id)) between 8 and 200),
  constraint verified_access_audit_metadata_sanitized_check
    check (
      position('CPF' in upper(metadata::text)) = 0
      and position('NOME' in upper(metadata::text)) = 0
      and position('PHONE' in upper(metadata::text)) = 0
      and position('TELEFONE' in upper(metadata::text)) = 0
      and position('DOCUMENT' in upper(metadata::text)) = 0
      and position('DOCUMENTO' in upper(metadata::text)) = 0
      and position('TOKEN' in upper(metadata::text)) = 0
      and position('CERTIDAO' in upper(metadata::text)) = 0
      and position('CERTIDÃO' in upper(metadata::text)) = 0
      and position('BIOMETR' in upper(metadata::text)) = 0
    )
);

create index if not exists idx_verified_access_audit_aggregate
on public.verified_access_audit_events(aggregate_type, aggregate_id, occurred_at desc);

create index if not exists idx_verified_access_audit_condominium_created
on public.verified_access_audit_events(condominium_id, created_at desc);

comment on table public.verified_access_service_types is
  'Acesso Verificado: catalogo global de tipos de servico. Nao contem PII.';
comment on table public.verified_access_condominium_service_types is
  'Acesso Verificado: configuracao local por condominio dos tipos de servico.';
comment on table public.verified_access_policies is
  'Acesso Verificado: politicas versionadas por condominio, com campos de rede inertes na Fase 1A.';
comment on table public.verified_access_requests is
  'Acesso Verificado: solicitacoes locais de visitante ou prestador, sempre escopadas por condominium_id.';
comment on table public.verified_access_service_request_details is
  'Acesso Verificado: detalhes de prestador; documento de empresa somente em ciphertext/HMAC.';
comment on table public.verified_access_participant_slots is
  'Acesso Verificado: vagas individuais numeradas por solicitacao.';
comment on table public.verified_access_identity_profiles is
  'Acesso Verificado: perfil local protegido. PII apenas em bytea ciphertext e HMAC local; sem descriptografia SQL.';
comment on table public.verified_access_participants is
  'Acesso Verificado: participante individual vinculado a uma unica vaga.';
comment on table public.verified_access_eligibility_evaluations is
  'Acesso Verificado: avaliacoes explicaveis sanitizadas; nao armazenar payload de fornecedor ou PII.';
comment on table public.verified_access_outbox_events is
  'Acesso Verificado: outbox especifica do dominio, payload sanitizado e sem worker nesta fase.';
comment on table public.verified_access_audit_events is
  'Acesso Verificado: auditoria append-only preparada por trigger na migration de seguranca.';

comment on column public.verified_access_identity_profiles.full_name_ciphertext is
  'PII criptografada pela aplicacao. Nao descriptografar em SQL.';
comment on column public.verified_access_identity_profiles.document_number_ciphertext is
  'Documento civil criptografado pela aplicacao. Nao armazenar documento em texto aberto.';
comment on column public.verified_access_identity_profiles.birth_date_ciphertext is
  'Data de nascimento criptografada pela aplicacao.';
comment on column public.verified_access_identity_profiles.phone_ciphertext is
  'Telefone criptografado pela aplicacao.';
comment on column public.verified_access_identity_profiles.mother_name_ciphertext is
  'Filiacao criptografada pela aplicacao.';
comment on column public.verified_access_identity_profiles.father_name_ciphertext is
  'Filiacao criptografada pela aplicacao.';
