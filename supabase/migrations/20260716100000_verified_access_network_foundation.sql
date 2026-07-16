insert into public.condominium_features (condominium_id, feature_key, enabled)
select id, feature_key, false
from public.condominiums
cross join (
  values
    ('VERIFIED_ACCESS_NETWORK_IDENTITY'),
    ('VERIFIED_ACCESS_NETWORK_SIGNALS'),
    ('VERIFIED_ACCESS_NETWORK_HOLD')
) as features(feature_key)
on conflict (condominium_id, feature_key) do update
  set enabled = public.condominium_features.enabled;

create table if not exists public.verified_access_network_subjects (
  id uuid primary key default gen_random_uuid(),
  status text not null default 'ACTIVE',
  identity_assurance_level text not null,
  first_verified_at timestamptz not null,
  last_verified_at timestamptz not null,
  revalidation_due_at timestamptz,
  retention_until timestamptz,
  merged_into_subject_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint verified_access_network_subjects_status_check
    check (status in ('ACTIVE', 'UNDER_REVIEW', 'DISPUTED', 'MERGED', 'RETIRED')),
  constraint verified_access_network_subjects_assurance_check
    check (identity_assurance_level in ('DOCUMENT_VERIFIED', 'IDENTITY_VERIFIED', 'MANUAL_VERIFIED')),
  constraint verified_access_network_subjects_verified_window_check
    check (last_verified_at >= first_verified_at),
  constraint verified_access_network_subjects_revalidation_check
    check (revalidation_due_at is null or revalidation_due_at >= first_verified_at),
  constraint verified_access_network_subjects_retention_check
    check (retention_until is null or retention_until >= first_verified_at),
  constraint verified_access_network_subjects_merge_status_check
    check (
      (status = 'MERGED' and merged_into_subject_id is not null)
      or (status <> 'MERGED' and merged_into_subject_id is null)
    ),
  constraint verified_access_network_subjects_merge_self_check
    check (merged_into_subject_id is null or merged_into_subject_id <> id),
  constraint verified_access_network_subjects_merge_fk
    foreign key (merged_into_subject_id)
    references public.verified_access_network_subjects(id)
    on delete restrict
);

create index if not exists idx_verified_access_network_subjects_status
on public.verified_access_network_subjects(status);

create index if not exists idx_verified_access_network_subjects_revalidation
on public.verified_access_network_subjects(revalidation_due_at)
where revalidation_due_at is not null;

create index if not exists idx_verified_access_network_subjects_retention
on public.verified_access_network_subjects(retention_until)
where retention_until is not null;

create table if not exists public.verified_access_network_subject_identifiers (
  id uuid primary key default gen_random_uuid(),
  network_subject_id uuid not null references public.verified_access_network_subjects(id) on delete cascade,
  identifier_type text not null,
  identifier_hmac text not null,
  hmac_key_version integer not null,
  canonicalization_version integer not null,
  status text not null default 'ACTIVE',
  is_primary boolean not null default false,
  verified_at timestamptz not null,
  expires_at timestamptz,
  revoked_at timestamptz,
  revoked_reason_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint verified_access_network_identifiers_type_check
    check (identifier_type in ('CPF', 'RNM', 'PASSPORT_WITH_ISSUER')),
  constraint verified_access_network_identifiers_hmac_size_check
    check (char_length(trim(identifier_hmac)) between 16 and 256),
  constraint verified_access_network_identifiers_key_versions_check
    check (hmac_key_version > 0 and canonicalization_version > 0),
  constraint verified_access_network_identifiers_status_check
    check (status in ('ACTIVE', 'REVOKED', 'EXPIRED')),
  constraint verified_access_network_identifiers_revoked_check
    check (
      (status = 'REVOKED' and revoked_at is not null and revoked_reason_code is not null)
      or status <> 'REVOKED'
    ),
  constraint verified_access_network_identifiers_expired_check
    check ((status = 'EXPIRED' and expires_at is not null) or status <> 'EXPIRED'),
  constraint verified_access_network_identifiers_expires_after_verified_check
    check (expires_at is null or expires_at > verified_at),
  constraint verified_access_network_identifiers_revoked_reason_check
    check (revoked_reason_code is null or revoked_reason_code ~ '^[A-Z0-9_]{2,80}$')
);

create unique index if not exists ux_verified_access_network_identifiers_active_hmac
on public.verified_access_network_subject_identifiers(
  identifier_type,
  identifier_hmac,
  hmac_key_version,
  canonicalization_version
)
where status = 'ACTIVE';

create unique index if not exists ux_verified_access_network_identifiers_primary_active
on public.verified_access_network_subject_identifiers(network_subject_id, identifier_type)
where status = 'ACTIVE' and is_primary;

create index if not exists idx_verified_access_network_identifiers_subject
on public.verified_access_network_subject_identifiers(network_subject_id, status);

create table if not exists public.verified_access_network_subject_links (
  id uuid primary key default gen_random_uuid(),
  network_subject_id uuid not null references public.verified_access_network_subjects(id) on delete cascade,
  condominium_id uuid not null references public.condominiums(id) on delete cascade,
  identity_profile_id uuid not null,
  link_status text not null default 'ACTIVE',
  link_reason text not null,
  identity_assurance_level text not null,
  linked_at timestamptz not null default now(),
  unlinked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint verified_access_network_links_profile_tenant_fk
    foreign key (identity_profile_id, condominium_id)
    references public.verified_access_identity_profiles(id, condominium_id)
    on delete restrict,
  constraint verified_access_network_links_assurance_check
    check (identity_assurance_level in ('DOCUMENT_VERIFIED', 'IDENTITY_VERIFIED', 'MANUAL_VERIFIED')),
  constraint verified_access_network_links_status_check
    check (link_status in ('ACTIVE', 'DISPUTED', 'UNLINKED')),
  constraint verified_access_network_links_reason_check
    check (link_reason in ('IDENTITY_VERIFIED', 'MANUAL_VERIFIED', 'IDENTIFIER_ROTATION', 'SUBJECT_MERGE', 'CORRECTION')),
  constraint verified_access_network_links_unlinked_check
    check (
      (link_status in ('ACTIVE', 'DISPUTED') and unlinked_at is null)
      or (link_status = 'UNLINKED' and unlinked_at is not null)
    )
);

create unique index if not exists ux_verified_access_network_links_active_profile
on public.verified_access_network_subject_links(identity_profile_id, condominium_id)
where link_status = 'ACTIVE';

create index if not exists idx_verified_access_network_links_subject
on public.verified_access_network_subject_links(network_subject_id, link_status);

create index if not exists idx_verified_access_network_links_condominium
on public.verified_access_network_subject_links(condominium_id, link_status);

create table if not exists public.verified_access_network_security_cases (
  id uuid primary key default gen_random_uuid(),
  network_subject_id uuid not null references public.verified_access_network_subjects(id) on delete restrict,
  source_type text not null,
  source_condominium_id uuid references public.condominiums(id) on delete restrict,
  source_participant_id uuid,
  category text not null,
  severity text not null,
  status text not null default 'REPORTED',
  evidence_assurance_level text not null,
  summary_code text not null,
  reported_by_actor_type text not null,
  reported_by_actor_id text not null,
  reported_at timestamptz not null default now(),
  triaged_by_actor_id text,
  triaged_at timestamptz,
  review_due_at timestamptz,
  substantiated_at timestamptz,
  dismissed_at timestamptz,
  closed_at timestamptz,
  expired_at timestamptz,
  evidence_reference_hash text,
  metadata_sanitized jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint verified_access_network_cases_source_participant_fk
    foreign key (source_participant_id, source_condominium_id)
    references public.verified_access_participants(id, condominium_id)
    on delete restrict,
  constraint verified_access_network_cases_source_type_check
    check (source_type in ('CONDOMINIUM_REPORT', 'PLATFORM_SECURITY', 'IDENTITY_PROVIDER', 'BACKGROUND_PROVIDER', 'PRIVACY_CORRECTION')),
  constraint verified_access_network_cases_source_check
    check (
      (source_type = 'CONDOMINIUM_REPORT' and source_condominium_id is not null and source_participant_id is not null)
      or (source_type <> 'CONDOMINIUM_REPORT' and source_condominium_id is null and source_participant_id is null)
    ),
  constraint verified_access_network_cases_status_check
    check (status in ('REPORTED', 'TRIAGE', 'UNDER_REVIEW', 'SUBSTANTIATED', 'DISMISSED', 'CLOSED', 'EXPIRED')),
  constraint verified_access_network_cases_category_check
    check (category in (
      'IDENTITY_IMPERSONATION_SUSPECTED',
      'DOCUMENT_FRAUD_SUSPECTED',
      'CREDENTIAL_COMPROMISE_SUSPECTED',
      'ACCOUNT_TAKEOVER_SUSPECTED',
      'REPEATED_IDENTITY_MANIPULATION_SUSPECTED',
      'PLATFORM_SECURITY_INCIDENT',
      'OFFICIAL_SOURCE_REVALIDATION_REQUIRED'
    )),
  constraint verified_access_network_cases_severity_check
    check (severity in ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL')),
  constraint verified_access_network_cases_evidence_assurance_check
    check (evidence_assurance_level in ('DOCUMENT_VERIFIED', 'IDENTITY_VERIFIED', 'MANUAL_VERIFIED', 'PROVIDER_ASSERTED', 'PLATFORM_EVIDENCE')),
  constraint verified_access_network_cases_summary_code_check
    check (summary_code ~ '^[A-Z0-9_]{2,80}$'),
  constraint verified_access_network_cases_actor_type_check
    check (reported_by_actor_type in ('CONDOMINIUM_OPERATOR', 'PLATFORM_OPERATOR', 'IDENTITY_PROVIDER', 'BACKGROUND_PROVIDER', 'PRIVACY_OFFICER')),
  constraint verified_access_network_cases_actor_id_check
    check (
      char_length(trim(reported_by_actor_id)) between 2 and 128
      and (triaged_by_actor_id is null or char_length(trim(triaged_by_actor_id)) between 2 and 128)
    ),
  constraint verified_access_network_cases_evidence_hash_check
    check (evidence_reference_hash is null or char_length(trim(evidence_reference_hash)) between 16 and 256),
  constraint verified_access_network_cases_metadata_object_check
    check (jsonb_typeof(metadata_sanitized) = 'object'),
  constraint verified_access_network_cases_metadata_sanitized_check
    check (metadata_sanitized::text !~* '(cpf|documento|document|phone|telefone|email|nome|name|biometr|face|token|secret)'),
  constraint verified_access_network_cases_status_dates_check
    check (
      (status = 'REPORTED' and triaged_at is null and substantiated_at is null and dismissed_at is null and closed_at is null and expired_at is null)
      or (status = 'TRIAGE' and triaged_at is not null and substantiated_at is null and dismissed_at is null and closed_at is null and expired_at is null)
      or (status = 'UNDER_REVIEW' and triaged_at is not null and substantiated_at is null and dismissed_at is null and closed_at is null and expired_at is null)
      or (status = 'SUBSTANTIATED' and triaged_at is not null and substantiated_at is not null and dismissed_at is null and closed_at is null and expired_at is null)
      or (status = 'DISMISSED' and dismissed_at is not null and substantiated_at is null and closed_at is null and expired_at is null)
      or (status = 'CLOSED' and closed_at is not null and expired_at is null)
      or (status = 'EXPIRED' and expired_at is not null and substantiated_at is null and dismissed_at is null)
    )
);

create unique index if not exists ux_verified_access_network_cases_id_subject
on public.verified_access_network_security_cases(id, network_subject_id);

create index if not exists idx_verified_access_network_cases_subject_status
on public.verified_access_network_security_cases(network_subject_id, status);

create index if not exists idx_verified_access_network_cases_source_condominium
on public.verified_access_network_security_cases(source_condominium_id, status)
where source_condominium_id is not null;

create index if not exists idx_verified_access_network_cases_severity
on public.verified_access_network_security_cases(severity, status);

create table if not exists public.verified_access_network_signals (
  id uuid primary key default gen_random_uuid(),
  network_subject_id uuid not null references public.verified_access_network_subjects(id) on delete restrict,
  source_case_id uuid not null,
  category text not null,
  severity text not null,
  effect text not null,
  status text not null default 'DRAFT',
  policy_version integer not null,
  reason_code text not null,
  valid_from timestamptz not null,
  expires_at timestamptz not null,
  review_due_at timestamptz not null,
  proposed_by_actor_type text not null,
  proposed_by_actor_id text not null,
  proposed_at timestamptz not null default now(),
  activated_by_actor_id text,
  activated_at timestamptz,
  suspended_at timestamptz,
  revoked_at timestamptz,
  revocation_reason_code text,
  rejected_at timestamptz,
  rejection_reason_code text,
  expired_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint verified_access_network_signals_case_subject_fk
    foreign key (source_case_id, network_subject_id)
    references public.verified_access_network_security_cases(id, network_subject_id)
    on delete restrict,
  constraint verified_access_network_signals_category_check
    check (category in (
      'IDENTITY_IMPERSONATION_CONFIRMED',
      'DOCUMENT_FRAUD_CONFIRMED',
      'CREDENTIAL_COMPROMISED',
      'ACCOUNT_TAKEOVER_CONFIRMED',
      'REPEATED_IDENTITY_MANIPULATION_CONFIRMED',
      'PLATFORM_SECURITY_SUSPENSION',
      'OFFICIAL_SOURCE_REVALIDATION_REQUIRED'
    )),
  constraint verified_access_network_signals_effect_check
    check (effect in ('INFORM_AUTHORIZED_REVIEWER', 'REVALIDATE_IDENTITY', 'REQUERY_OFFICIAL_SOURCE', 'REQUIRE_MANUAL_REVIEW', 'HOLD_CREDENTIAL')),
  constraint verified_access_network_signals_status_check
    check (status in ('DRAFT', 'UNDER_REVIEW', 'ACTIVE', 'SUSPENDED', 'REVOKED', 'EXPIRED', 'REJECTED')),
  constraint verified_access_network_signals_severity_check
    check (severity in ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL')),
  constraint verified_access_network_signals_reason_check
    check (reason_code ~ '^[A-Z0-9_]{2,80}$'),
  constraint verified_access_network_signals_policy_version_check
    check (policy_version > 0),
  constraint verified_access_network_signals_window_check
    check (expires_at > valid_from and review_due_at > valid_from and review_due_at <= expires_at),
  constraint verified_access_network_signals_status_dates_check
    check (
      (status in ('DRAFT', 'UNDER_REVIEW') and activated_at is null and suspended_at is null and revoked_at is null and rejected_at is null and expired_at is null)
      or (status = 'ACTIVE' and activated_at is not null and suspended_at is null and revoked_at is null and rejected_at is null and expired_at is null)
      or (status = 'SUSPENDED' and activated_at is not null and suspended_at is not null and revoked_at is null and rejected_at is null and expired_at is null)
      or (status = 'REVOKED' and revoked_at is not null and revocation_reason_code is not null)
      or (status = 'EXPIRED' and expired_at is not null and revoked_at is null and rejected_at is null)
      or (status = 'REJECTED' and rejected_at is not null and rejection_reason_code is not null and activated_at is null)
    ),
  constraint verified_access_network_signals_reason_codes_check
    check (
      (revocation_reason_code is null or revocation_reason_code ~ '^[A-Z0-9_]{2,80}$')
      and (rejection_reason_code is null or rejection_reason_code ~ '^[A-Z0-9_]{2,80}$')
    ),
  constraint verified_access_network_signals_actor_type_check
    check (proposed_by_actor_type in ('SYSTEM', 'PLATFORM_OPERATOR', 'SECURITY_REVIEWER', 'PRIVACY_OFFICER')),
  constraint verified_access_network_signals_actor_id_check
    check (
      char_length(trim(proposed_by_actor_id)) between 2 and 128
      and (activated_by_actor_id is null or char_length(trim(activated_by_actor_id)) between 2 and 128)
    )
);

create index if not exists idx_verified_access_network_signals_subject_status
on public.verified_access_network_signals(network_subject_id, status, expires_at);

create index if not exists idx_verified_access_network_signals_active_actionable
on public.verified_access_network_signals(network_subject_id, effect, severity, expires_at)
where status = 'ACTIVE';

create index if not exists idx_verified_access_network_signals_review_due
on public.verified_access_network_signals(review_due_at);

create unique index if not exists ux_verified_access_network_signals_id_subject
on public.verified_access_network_signals(id, network_subject_id);

create table if not exists public.verified_access_network_signal_reviews (
  id uuid primary key default gen_random_uuid(),
  signal_id uuid not null references public.verified_access_network_signals(id) on delete cascade,
  reviewer_actor_id text not null,
  reviewer_role text not null,
  decision text not null,
  reason_code text not null,
  reviewed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint verified_access_network_reviews_role_check
    check (reviewer_role in ('NETWORK_REVIEWER', 'PRIVACY_REVIEWER', 'SECURITY_REVIEWER')),
  constraint verified_access_network_reviews_decision_check
    check (decision in ('APPROVE', 'REJECT', 'REQUEST_CHANGES')),
  constraint verified_access_network_reviews_reason_check
    check (reason_code ~ '^[A-Z0-9_]{2,80}$'),
  constraint verified_access_network_reviews_actor_check
    check (char_length(trim(reviewer_actor_id)) between 2 and 128)
);

create unique index if not exists ux_verified_access_network_reviews_signal_actor
on public.verified_access_network_signal_reviews(signal_id, reviewer_actor_id);

create index if not exists idx_verified_access_network_reviews_signal
on public.verified_access_network_signal_reviews(signal_id, reviewed_at);

create table if not exists public.verified_access_network_appeals (
  id uuid primary key default gen_random_uuid(),
  network_subject_id uuid not null references public.verified_access_network_subjects(id) on delete restrict,
  signal_id uuid,
  status text not null default 'OPEN',
  request_reference_hash text not null,
  opened_at timestamptz not null default now(),
  review_due_at timestamptz not null,
  resolution_code text,
  resolved_by_actor_id text,
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint verified_access_network_appeals_status_check
    check (status in ('OPEN', 'UNDER_REVIEW', 'UPHELD', 'AMENDED', 'REVOKED', 'CLOSED')),
  constraint verified_access_network_appeals_reference_hash_check
    check (char_length(trim(request_reference_hash)) between 16 and 256),
  constraint verified_access_network_appeals_due_check
    check (review_due_at > opened_at),
  constraint verified_access_network_appeals_resolution_check
    check (
      (status in ('UPHELD', 'AMENDED', 'REVOKED', 'CLOSED') and resolved_at is not null and resolution_code is not null and resolved_by_actor_id is not null)
      or (status in ('OPEN', 'UNDER_REVIEW') and resolved_at is null and resolution_code is null and resolved_by_actor_id is null)
    ),
  constraint verified_access_network_appeals_resolution_code_check
    check (
      (resolution_code is null or resolution_code ~ '^[A-Z0-9_]{2,80}$')
      and (resolved_by_actor_id is null or char_length(trim(resolved_by_actor_id)) between 2 and 128)
    ),
  constraint verified_access_network_appeals_signal_subject_fk
    foreign key (signal_id, network_subject_id)
    references public.verified_access_network_signals(id, network_subject_id)
    on delete restrict
);

create index if not exists idx_verified_access_network_appeals_subject_status
on public.verified_access_network_appeals(network_subject_id, status);

create index if not exists idx_verified_access_network_appeals_signal
on public.verified_access_network_appeals(signal_id)
where signal_id is not null;

create index if not exists idx_verified_access_network_appeals_review_due
on public.verified_access_network_appeals(review_due_at, status);

create or replace function public.verified_access_network_validate_case_source_subject()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_identity_profile_id uuid;
  v_participant_found boolean := false;
begin
  if new.source_type <> 'CONDOMINIUM_REPORT' then
    if new.source_condominium_id is not null or new.source_participant_id is not null then
      raise exception 'non-condominium network case sources must not include local tenant participant data'
        using errcode = '23514';
    end if;

    return new;
  end if;

  if new.source_condominium_id is null or new.source_participant_id is null then
    raise exception 'condominium network reports require source condominium and participant'
      using errcode = '23514';
  end if;

  select p.identity_profile_id, true
    into v_identity_profile_id, v_participant_found
  from public.verified_access_participants p
  where p.id = new.source_participant_id
    and p.condominium_id = new.source_condominium_id;

  if not coalesce(v_participant_found, false) then
    raise exception 'condominium report source participant must belong to the source condominium'
      using errcode = '23503';
  end if;

  if v_identity_profile_id is null then
    raise exception 'condominium report source participant must have an identity profile'
      using errcode = 'P0001';
  end if;

  if not exists (
    select 1
    from public.verified_access_network_subject_links l
    where l.network_subject_id = new.network_subject_id
      and l.condominium_id = new.source_condominium_id
      and l.identity_profile_id = v_identity_profile_id
      and l.link_status in ('ACTIVE', 'DISPUTED')
  ) then
    raise exception 'condominium report source participant must be linked to the same network subject'
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

drop trigger if exists verified_access_network_cases_validate_source_subject
on public.verified_access_network_security_cases;

create trigger verified_access_network_cases_validate_source_subject
before insert or update of network_subject_id, source_type, source_condominium_id, source_participant_id
on public.verified_access_network_security_cases
for each row
execute function public.verified_access_network_validate_case_source_subject();

create or replace function public.verified_access_network_validate_signal_source_case()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_case_status text;
begin
  select status
    into v_case_status
  from public.verified_access_network_security_cases
  where id = new.source_case_id
    and network_subject_id = new.network_subject_id;

  if v_case_status is null then
    raise exception 'network signal source case must belong to the same network subject'
      using errcode = '23503';
  end if;

  if v_case_status <> 'SUBSTANTIATED' then
    raise exception 'network signal source case must be SUBSTANTIATED'
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

drop trigger if exists verified_access_network_signals_validate_source_case
on public.verified_access_network_signals;

create trigger verified_access_network_signals_validate_source_case
before insert or update of source_case_id, network_subject_id
on public.verified_access_network_signals
for each row
execute function public.verified_access_network_validate_signal_source_case();

comment on table public.verified_access_network_subjects is
  'Central pseudonymous Verified Access network subject registry for Phase 1B. No tenant PII is stored here.';
comment on table public.verified_access_network_subject_identifiers is
  'Central HMAC-only identifiers for network subject matching. Phone, email, name, face and biometric identifiers are intentionally unsupported.';
comment on table public.verified_access_network_subject_links is
  'Links central network subjects to local tenant identity profiles without copying tenant civil PII.';
comment on table public.verified_access_network_security_cases is
  'Central sanitized security cases. Reported, triage and under-review cases do not produce tenant effects in Phase 1B.';
comment on table public.verified_access_network_signals is
  'Central network signals restricted to authorized reviewer information, revalidation, official-source requery, manual review or credential hold effects.';
comment on table public.verified_access_network_signal_reviews is
  'Human review decisions for network signals.';
comment on table public.verified_access_network_appeals is
  'Appeal tracking using hashed request references and no central civil PII.';
