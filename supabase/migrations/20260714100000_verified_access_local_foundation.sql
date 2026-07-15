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
  visitor_identity_mode text not null default 'DISABLED',
  service_identity_mode text not null default 'DISABLED',
  minimum_identity_assurance_level text not null default 'SELF_DECLARED',
  visitor_background_mode text not null default 'DISABLED',
  service_background_mode text not null default 'DISABLED',
  network_identity_mode text not null default 'DISABLED',
  network_signal_mode text not null default 'DISABLED',
  network_signal_min_severity text not null default 'LOW',
  network_signal_rules jsonb not null default '{}'::jsonb,
  network_hold_enabled boolean not null default false,
  timezone text not null default 'America/Sao_Paulo',
  invitation_ttl_minutes integer not null default 10080,
  public_session_ttl_minutes integer not null default 30,
  max_visitor_participants integer not null default 10,
  max_service_participants integer not null default 20,
  max_request_duration_minutes integer not null default 1440,
  min_notice_minutes integer not null default 0,
  max_notice_days integer not null default 90,
  allow_open_slots boolean not null default true,
  privacy_approval_reference text,
  background_approval_reference text,
  network_approval_reference text,
  retention_settings jsonb not null default '{"standard_days":90,"sensitive_days":30}'::jsonb,
  additional_settings jsonb not null default '{}'::jsonb,
  content_checksum text not null,
  created_by_actor_type text not null default 'SYSTEM',
  created_by_actor_id text,
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
    check (
      visitor_identity_mode in ('DISABLED', 'OPTIONAL', 'REQUIRED')
      and service_identity_mode in ('DISABLED', 'OPTIONAL', 'REQUIRED')
    ),
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
    check (
      visitor_background_mode in ('DISABLED', 'OPTIONAL', 'REQUIRED')
      and service_background_mode in ('DISABLED', 'OPTIONAL', 'REQUIRED')
    ),
  constraint verified_access_policies_network_identity_mode_check
    check (network_identity_mode in ('DISABLED', 'EVALUATE_ONLY')),
  constraint verified_access_policies_network_signal_mode_check
    check (network_signal_mode in ('DISABLED', 'EVALUATE_ONLY', 'APPLY_CONFIGURED_EFFECT')),
  constraint verified_access_policies_network_severity_check
    check (network_signal_min_severity in ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL')),
  constraint verified_access_policies_background_approval_check
    check (
      (visitor_background_mode = 'DISABLED' and service_background_mode = 'DISABLED')
      or nullif(trim(coalesce(background_approval_reference, '')), '') is not null
    ),
  constraint verified_access_policies_network_approval_check
    check (
      (
        network_identity_mode = 'DISABLED'
        and network_signal_mode = 'DISABLED'
        and network_hold_enabled = false
      )
      or nullif(trim(coalesce(network_approval_reference, '')), '') is not null
    ),
  constraint verified_access_policies_network_hold_check
    check (network_hold_enabled = false or network_signal_mode = 'APPLY_CONFIGURED_EFFECT'),
  constraint verified_access_policies_time_window_check
    check (
      invitation_ttl_minutes between 5 and 43200
      and public_session_ttl_minutes between 5 and 1440
      and max_visitor_participants between 1 and 100
      and max_service_participants between 1 and 100
      and max_request_duration_minutes between 15 and 525600
      and min_notice_minutes between 0 and 525600
      and max_notice_days between 1 and 3650
    ),
  constraint verified_access_policies_timezone_check
    check (char_length(trim(timezone)) between 1 and 64),
  constraint verified_access_policies_checksum_check
    check (char_length(trim(content_checksum)) between 16 and 128),
  constraint verified_access_policies_actor_type_check
    check (created_by_actor_type in ('SYSTEM', 'MIGRATION', 'BACKOFFICE_USER', 'SERVICE_ROLE')),
  constraint verified_access_policies_json_object_check
    check (
      jsonb_typeof(network_signal_rules) = 'object'
      and jsonb_typeof(retention_settings) = 'object'
      and jsonb_typeof(additional_settings) = 'object'
    ),
  constraint verified_access_policies_retention_settings_check
    check (
      (retention_settings ? 'standard_days')
      and (retention_settings ? 'sensitive_days')
      and (retention_settings->>'standard_days')::integer between 1 and 3650
      and (retention_settings->>'sensitive_days')::integer between 1 and (retention_settings->>'standard_days')::integer
    ),
  constraint verified_access_policies_forbidden_network_rules_check
    check (
      position('AUTO_DENY_NETWORK' in upper(network_signal_rules::text)) = 0
      and position('GLOBAL_DENIED' in upper(network_signal_rules::text)) = 0
      and position('PERMANENT_BLACKLIST' in upper(network_signal_rules::text)) = 0
    )
);

create unique index if not exists ux_verified_access_policies_id_condominium_id
on public.verified_access_policies(id, condominium_id);

create unique index if not exists ux_verified_access_policies_id_condominium_version
on public.verified_access_policies(id, condominium_id, version);

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
  expires_at timestamptz,
  cancelled_at timestamptz,
  timezone text not null,
  participant_limit integer not null,
  policy_id uuid not null,
  policy_version integer not null,
  eligibility_expires_at timestamptz,
  eligibility_reason_code text,
  version integer not null default 1,
  created_by_actor_type text not null default 'USER',
  created_by_actor_id text,
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
  constraint verified_access_requests_policy_version_fk
    foreign key (policy_id, condominium_id, policy_version)
    references public.verified_access_policies(id, condominium_id, version)
    on delete restrict,
  constraint verified_access_requests_type_check
    check (request_type in ('VISITOR', 'SERVICE_PROVIDER')),
  constraint verified_access_requests_status_check
    check (status in ('DRAFT', 'INVITATIONS_PENDING', 'IN_PROGRESS', 'PARTIALLY_ELIGIBLE', 'ELIGIBLE', 'COMPLETED', 'CANCELLED', 'EXPIRED')),
  constraint verified_access_requests_period_check
    check (starts_at < ends_at),
  constraint verified_access_requests_expiry_check
    check (expires_at is null or expires_at >= starts_at),
  constraint verified_access_requests_cancelled_at_check
    check ((status = 'CANCELLED' and cancelled_at is not null) or status <> 'CANCELLED'),
  constraint verified_access_requests_participant_limit_check
    check (participant_limit > 0 and participant_limit <= 100),
  constraint verified_access_requests_policy_version_check
    check (policy_version > 0),
  constraint verified_access_requests_version_check
    check (version > 0),
  constraint verified_access_requests_timezone_check
    check (char_length(trim(timezone)) between 1 and 64),
  constraint verified_access_requests_actor_type_check
    check (created_by_actor_type in ('USER', 'BACKOFFICE_USER', 'SYSTEM', 'SERVICE_ROLE')),
  constraint verified_access_requests_eligibility_reason_check
    check (eligibility_reason_code is null or char_length(trim(eligibility_reason_code)) between 2 and 80),
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
    check (
      (status = 'OPEN' and claimed_at is null)
      or (status in ('RESERVED', 'CLAIMED') and claimed_at is not null)
      or status in ('CANCELLED', 'EXPIRED')
    )
);

create unique index if not exists ux_verified_access_slots_id_condominium_id
on public.verified_access_participant_slots(id, condominium_id);

create unique index if not exists ux_verified_access_slots_id_request_condominium
on public.verified_access_participant_slots(id, request_id, condominium_id);

create unique index if not exists ux_verified_access_slots_request_number
on public.verified_access_participant_slots(request_id, slot_number);

create index if not exists idx_verified_access_slots_condominium_status
on public.verified_access_participant_slots(condominium_id, status);

create table if not exists public.verified_access_identity_profiles (
  id uuid primary key default gen_random_uuid(),
  condominium_id uuid not null references public.condominiums(id) on delete cascade,
  cpf_ciphertext bytea,
  cpf_tenant_hmac text,
  document_type text,
  document_number_ciphertext bytea,
  document_number_tenant_hmac text,
  document_issuer_country_ciphertext bytea,
  phone_ciphertext bytea,
  phone_tenant_hmac text,
  full_name_ciphertext bytea,
  birth_date_ciphertext bytea,
  mother_name_ciphertext bytea,
  father_name_ciphertext bytea,
  encryption_key_version integer,
  hmac_key_version integer,
  identity_assurance_level text not null default 'SELF_DECLARED',
  retention_expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint verified_access_identity_profiles_document_type_check
    check (document_type is null or document_type in ('CPF', 'RNM', 'PASSPORT')),
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
        cpf_ciphertext is null
        and document_number_ciphertext is null
        and document_issuer_country_ciphertext is null
        and phone_ciphertext is null
        and full_name_ciphertext is null
        and birth_date_ciphertext is null
        and mother_name_ciphertext is null
        and father_name_ciphertext is null
      )
      or encryption_key_version is not null
    ),
  constraint verified_access_identity_profiles_hmac_key_check
    check (
      (
        cpf_tenant_hmac is null
        and document_number_tenant_hmac is null
        and phone_tenant_hmac is null
      )
      or hmac_key_version is not null
    ),
  constraint verified_access_identity_profiles_hmac_size_check
    check (
      (cpf_tenant_hmac is null or char_length(trim(cpf_tenant_hmac)) between 16 and 256)
      and (document_number_tenant_hmac is null or char_length(trim(document_number_tenant_hmac)) between 16 and 256)
      and (phone_tenant_hmac is null or char_length(trim(phone_tenant_hmac)) between 16 and 256)
    )
);

create unique index if not exists ux_verified_access_identity_profiles_id_condominium_id
on public.verified_access_identity_profiles(id, condominium_id);

create unique index if not exists ux_verified_access_identity_profiles_cpf_tenant_hmac
on public.verified_access_identity_profiles(condominium_id, cpf_tenant_hmac, hmac_key_version)
where cpf_tenant_hmac is not null;

create unique index if not exists ux_verified_access_identity_profiles_document_tenant_hmac
on public.verified_access_identity_profiles(condominium_id, document_type, document_number_tenant_hmac, hmac_key_version)
where document_number_tenant_hmac is not null;

create unique index if not exists ux_verified_access_identity_profiles_phone_tenant_hmac
on public.verified_access_identity_profiles(condominium_id, phone_tenant_hmac, hmac_key_version)
where phone_tenant_hmac is not null;

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
  constraint verified_access_participants_slot_request_tenant_fk
    foreign key (slot_id, request_id, condominium_id)
    references public.verified_access_participant_slots(id, request_id, condominium_id)
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

create unique index if not exists ux_verified_access_participants_id_request_condominium
on public.verified_access_participants(id, request_id, condominium_id);

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
  input_snapshot_sanitized jsonb not null default '{}'::jsonb,
  outcome text not null,
  reason_codes text[] not null default '{}'::text[],
  eligibility_expires_at timestamptz,
  eligibility_reason_code text,
  decision_source text not null,
  actor_type text not null default 'SYSTEM',
  actor_id text,
  trigger_event_type text,
  evaluated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint verified_access_evaluations_request_tenant_fk
    foreign key (request_id, condominium_id)
    references public.verified_access_requests(id, condominium_id)
    on delete cascade,
  constraint verified_access_evaluations_participant_request_tenant_fk
    foreign key (participant_id, request_id, condominium_id)
    references public.verified_access_participants(id, request_id, condominium_id)
    on delete cascade,
  constraint verified_access_evaluations_policy_version_fk
    foreign key (policy_id, condominium_id, policy_version)
    references public.verified_access_policies(id, condominium_id, version)
    on delete restrict,
  constraint verified_access_evaluations_policy_version_check
    check (policy_version > 0),
  constraint verified_access_evaluations_outcome_check
    check (outcome in ('ELIGIBLE', 'REVIEW_REQUIRED', 'CORRECTION_REQUIRED', 'DENIED_MANUAL', 'CANCELLED', 'EXPIRED')),
  constraint verified_access_evaluations_decision_source_check
    check (decision_source in ('SYSTEM_RULES', 'HUMAN_REVIEW', 'TECHNICAL_RECONCILIATION')),
  constraint verified_access_evaluations_actor_type_check
    check (actor_type in ('SYSTEM', 'PROVIDER', 'CRON', 'BACKOFFICE_USER', 'SERVICE_ROLE')),
  constraint verified_access_evaluations_reason_check
    check (eligibility_reason_code is null or char_length(trim(eligibility_reason_code)) between 2 and 80),
  constraint verified_access_evaluations_json_object_check
    check (jsonb_typeof(input_snapshot_sanitized) = 'object' and jsonb_typeof(metadata) = 'object'),
  constraint verified_access_evaluations_metadata_sanitized_check
    check (
      position('CPF' in upper(metadata::text)) = 0
      and position('DOCUMENT' in upper(metadata::text)) = 0
      and position('DOC_NUMBER' in upper(metadata::text)) = 0
      and position('DOCUMENTO' in upper(metadata::text)) = 0
      and position('TELEFONE' in upper(metadata::text)) = 0
      and position('PHONE' in upper(metadata::text)) = 0
      and position('TOKEN' in upper(metadata::text)) = 0
      and position('BIOMETR' in upper(metadata::text)) = 0
      and position('CERTIDAO' in upper(metadata::text)) = 0
      and position('CERTID' in upper(metadata::text)) = 0
      and position('PERSON_NAME' in upper(metadata::text)) = 0
      and position('NOME' in upper(metadata::text)) = 0
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
  constraint verified_access_outbox_payload_object_check
    check (jsonb_typeof(payload) = 'object'),
  constraint verified_access_outbox_payload_sanitized_check
    check (
      position('CPF' in upper(payload::text)) = 0
      and position('DOCUMENT' in upper(payload::text)) = 0
      and position('DOC_NUMBER' in upper(payload::text)) = 0
      and position('DOCUMENTO' in upper(payload::text)) = 0
      and position('NOME' in upper(payload::text)) = 0
      and position('PERSON_NAME' in upper(payload::text)) = 0
      and position('PHONE' in upper(payload::text)) = 0
      and position('TELEFONE' in upper(payload::text)) = 0
      and position('TOKEN' in upper(payload::text)) = 0
      and position('CERTIDAO' in upper(payload::text)) = 0
      and position('CERTID' in upper(payload::text)) = 0
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
  constraint verified_access_audit_metadata_object_check
    check (jsonb_typeof(metadata) = 'object'),
  constraint verified_access_audit_metadata_sanitized_check
    check (
      position('CPF' in upper(metadata::text)) = 0
      and position('DOCUMENT' in upper(metadata::text)) = 0
      and position('DOC_NUMBER' in upper(metadata::text)) = 0
      and position('DOCUMENTO' in upper(metadata::text)) = 0
      and position('NOME' in upper(metadata::text)) = 0
      and position('PERSON_NAME' in upper(metadata::text)) = 0
      and position('PHONE' in upper(metadata::text)) = 0
      and position('TELEFONE' in upper(metadata::text)) = 0
      and position('TOKEN' in upper(metadata::text)) = 0
      and position('CERTIDAO' in upper(metadata::text)) = 0
      and position('CERTID' in upper(metadata::text)) = 0
      and position('BIOMETR' in upper(metadata::text)) = 0
    )
);

create index if not exists idx_verified_access_audit_aggregate
on public.verified_access_audit_events(aggregate_type, aggregate_id, occurred_at desc);

create index if not exists idx_verified_access_audit_condominium_created
on public.verified_access_audit_events(condominium_id, created_at desc);

create or replace function public.verified_access_validate_service_request_details()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_request_type text;
  v_requires_description boolean;
begin
  select var.request_type
    into v_request_type
  from public.verified_access_requests var
  where var.id = new.request_id
    and var.condominium_id = new.condominium_id;

  if v_request_type is null then
    raise exception 'verified_access_service_request_details request not found for condominium';
  end if;

  if v_request_type <> 'SERVICE_PROVIDER' then
    raise exception 'service request details require SERVICE_PROVIDER request';
  end if;

  select vast.requires_description
    into v_requires_description
  from public.verified_access_service_types vast
  where vast.id = new.service_type_id;

  if v_requires_description is null then
    raise exception 'verified_access service type not found';
  end if;

  if v_requires_description and nullif(trim(coalesce(new.other_description, '')), '') is null then
    raise exception 'other_description is required for this service type';
  end if;

  return new;
end;
$$;

create trigger verified_access_service_details_validate
before insert or update on public.verified_access_service_request_details
for each row
execute function public.verified_access_validate_service_request_details();

create or replace function public.verified_access_validate_slot_capacity()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_participant_limit integer;
begin
  select var.participant_limit
    into v_participant_limit
  from public.verified_access_requests var
  where var.id = new.request_id
    and var.condominium_id = new.condominium_id;

  if v_participant_limit is null then
    raise exception 'verified_access slot request not found for condominium';
  end if;

  if new.slot_number > v_participant_limit then
    raise exception 'slot_number exceeds request participant_limit';
  end if;

  return new;
end;
$$;

create trigger verified_access_slots_validate_capacity
before insert or update on public.verified_access_participant_slots
for each row
execute function public.verified_access_validate_slot_capacity();

create or replace function public.verified_access_prevent_outbox_business_mutation()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
begin
  if new.id is distinct from old.id
    or new.condominium_id is distinct from old.condominium_id
    or new.scope is distinct from old.scope
    or new.aggregate_type is distinct from old.aggregate_type
    or new.aggregate_id is distinct from old.aggregate_id
    or new.event_type is distinct from old.event_type
    or new.event_version is distinct from old.event_version
    or new.deduplication_key is distinct from old.deduplication_key
    or new.payload is distinct from old.payload
    or new.created_at is distinct from old.created_at
  then
    raise exception 'verified_access_outbox_events business payload is immutable';
  end if;

  return new;
end;
$$;

create trigger verified_access_outbox_prevent_business_update
before update on public.verified_access_outbox_events
for each row
execute function public.verified_access_prevent_outbox_business_mutation();

create or replace function public.verified_access_prevent_audit_mutation()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
begin
  raise exception 'verified_access_audit_events is append-only';
end;
$$;

create trigger verified_access_audit_events_prevent_update
before update on public.verified_access_audit_events
for each row
execute function public.verified_access_prevent_audit_mutation();

create trigger verified_access_audit_events_prevent_delete
before delete on public.verified_access_audit_events
for each row
execute function public.verified_access_prevent_audit_mutation();

create trigger verified_access_audit_events_prevent_truncate
before truncate on public.verified_access_audit_events
for each statement
execute function public.verified_access_prevent_audit_mutation();

comment on table public.verified_access_service_types is
  'Acesso Verificado: catalogo global de tipos de servico. Nao contem PII.';
comment on table public.verified_access_condominium_service_types is
  'Acesso Verificado: configuracao local por condominio dos tipos de servico.';
comment on table public.verified_access_policies is
  'Acesso Verificado: politicas versionadas por condominio, com configuracao separada para visitante e prestador; campos de rede inertes na Fase 1A.';
comment on table public.verified_access_requests is
  'Acesso Verificado: solicitacoes locais de visitante ou prestador, sempre escopadas por condominium_id.';
comment on table public.verified_access_service_request_details is
  'Acesso Verificado: detalhes somente para solicitacao SERVICE_PROVIDER; documento de empresa somente em ciphertext/HMAC.';
comment on table public.verified_access_participant_slots is
  'Acesso Verificado: vagas individuais numeradas por solicitacao, limitadas por participant_limit.';
comment on table public.verified_access_identity_profiles is
  'Acesso Verificado: perfil local protegido. PII apenas em bytea ciphertext e HMAC local; sem descriptografia SQL.';
comment on table public.verified_access_participants is
  'Acesso Verificado: participante individual vinculado a uma unica vaga da mesma solicitacao.';
comment on table public.verified_access_eligibility_evaluations is
  'Acesso Verificado: avaliacoes explicaveis sanitizadas; nao armazenar payload de fornecedor ou PII.';
comment on table public.verified_access_outbox_events is
  'Acesso Verificado: outbox especifica do dominio, payload sanitizado, parcialmente imutavel e sem worker nesta fase.';
comment on table public.verified_access_audit_events is
  'Acesso Verificado: auditoria append-only com update/delete/truncate bloqueados.';

comment on column public.verified_access_policies.network_signal_rules is
  'Configuracao inerte nesta fase. Regras proibidas como AUTO_DENY_NETWORK sao rejeitadas.';
comment on column public.verified_access_policies.retention_settings is
  'Objeto JSON sanitizado com dias de retencao padrao e sensivel; nao armazena PII.';
comment on column public.verified_access_identity_profiles.cpf_ciphertext is
  'CPF criptografado pela aplicacao. Nao descriptografar em SQL.';
comment on column public.verified_access_identity_profiles.cpf_tenant_hmac is
  'HMAC local por condominio para deduplicacao local de CPF; nao e HMAC de rede.';
comment on column public.verified_access_identity_profiles.document_number_ciphertext is
  'Documento civil criptografado pela aplicacao. Nao armazenar documento em texto aberto.';
comment on column public.verified_access_identity_profiles.document_number_tenant_hmac is
  'HMAC local por condominio para identificador documental; nao e HMAC de rede.';
comment on column public.verified_access_identity_profiles.phone_ciphertext is
  'Telefone criptografado pela aplicacao.';
comment on column public.verified_access_identity_profiles.phone_tenant_hmac is
  'HMAC local por condominio para telefone; usar apenas quando houver finalidade local documentada.';
comment on column public.verified_access_identity_profiles.full_name_ciphertext is
  'Nome criptografado pela aplicacao. Sem HMAC por minimizacao.';
comment on column public.verified_access_identity_profiles.birth_date_ciphertext is
  'Data de nascimento criptografada pela aplicacao. Sem HMAC por minimizacao.';
comment on column public.verified_access_identity_profiles.mother_name_ciphertext is
  'Filiacao criptografada pela aplicacao. Sem HMAC por minimizacao.';
comment on column public.verified_access_identity_profiles.father_name_ciphertext is
  'Filiacao criptografada pela aplicacao. Sem HMAC por minimizacao.';
comment on column public.verified_access_service_request_details.company_name is
  'Campo livre operacional; nao deve receber documentos, antecedentes, biometria ou PII desnecessaria.';
comment on column public.verified_access_service_request_details.other_description is
  'Descricao operacional de servico OTHER; nao deve receber documentos, antecedentes ou biometria.';
comment on column public.verified_access_service_request_details.work_description is
  'Descricao operacional do trabalho; nao incluir documentos, antecedentes ou biometria.';
comment on column public.verified_access_service_request_details.destination_area is
  'Area de destino operacional; nao incluir documentos, antecedentes ou biometria.';
comment on column public.verified_access_requests.operational_notes is
  'Observacao operacional limitada; nao incluir documentos, antecedentes, biometria ou secrets.';
comment on column public.verified_access_requests.visit_reason is
  'Motivo resumido da visita; nao incluir documentos, antecedentes ou biometria.';
