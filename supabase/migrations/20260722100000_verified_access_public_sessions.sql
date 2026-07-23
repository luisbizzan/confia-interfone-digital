create table public.verified_access_public_sessions (
  id uuid primary key default gen_random_uuid(),
  condominium_id uuid not null references public.condominiums(id) on delete cascade,
  request_id uuid not null,
  invitation_id uuid not null,
  participant_slot_id uuid not null,
  session_token_hash text not null,
  token_version integer not null default 1,
  status text not null default 'ACTIVE',
  expires_at timestamptz not null,
  started_at timestamptz,
  last_seen_at timestamptz,
  revoked_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint verified_access_public_sessions_invitation_tenant_fk
    foreign key (invitation_id, request_id, condominium_id)
    references public.verified_access_invitations(id, request_id, condominium_id)
    on delete cascade,
  constraint verified_access_public_sessions_slot_tenant_fk
    foreign key (participant_slot_id, request_id, condominium_id)
    references public.verified_access_participant_slots(id, request_id, condominium_id)
    on delete restrict,
  constraint verified_access_public_sessions_token_hash_check
    check (session_token_hash ~ '^v1:[0-9a-f]{64}$'),
  constraint verified_access_public_sessions_token_version_check
    check (token_version > 0),
  constraint verified_access_public_sessions_status_check
    check (status in ('ACTIVE', 'REVOKED', 'EXPIRED', 'COMPLETED')),
  constraint verified_access_public_sessions_expiry_check
    check (expires_at > created_at and expires_at <= created_at + interval '30 minutes 5 seconds'),
  constraint verified_access_public_sessions_status_timestamps_check
    check (
      (status = 'ACTIVE' and revoked_at is null and completed_at is null)
      or (status = 'REVOKED' and revoked_at is not null and completed_at is null)
      or (status = 'EXPIRED' and revoked_at is null and completed_at is null)
      or (status = 'COMPLETED' and revoked_at is null and completed_at is not null)
    )
);

create unique index ux_verified_access_public_sessions_id_condominium
on public.verified_access_public_sessions(id, condominium_id);

create unique index ux_verified_access_public_sessions_hash
on public.verified_access_public_sessions(session_token_hash);

create unique index ux_verified_access_public_sessions_one_active
on public.verified_access_public_sessions(invitation_id)
where status = 'ACTIVE';

create index idx_verified_access_public_sessions_expiry
on public.verified_access_public_sessions(expires_at)
where status = 'ACTIVE';

alter table public.verified_access_public_sessions enable row level security;

revoke all on table public.verified_access_public_sessions
from public, anon, authenticated, service_role;

create table public.verified_access_public_registration_commands (
  id uuid primary key default gen_random_uuid(),
  condominium_id uuid not null references public.condominiums(id) on delete cascade,
  invitation_id uuid not null,
  session_id uuid,
  command_type text not null,
  idempotency_key text not null,
  input_fingerprint text not null,
  status text not null default 'PROCESSING',
  result_code text,
  result_payload jsonb,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  constraint verified_access_public_commands_invitation_tenant_fk
    foreign key (invitation_id, condominium_id)
    references public.verified_access_invitations(id, condominium_id)
    on delete cascade,
  constraint verified_access_public_commands_session_tenant_fk
    foreign key (session_id, condominium_id)
    references public.verified_access_public_sessions(id, condominium_id)
    on delete restrict,
  constraint verified_access_public_commands_type_check
    check (command_type in ('EXCHANGE', 'START', 'SUBMIT')),
  constraint verified_access_public_commands_key_check
    check (
      char_length(idempotency_key) between 16 and 128
      and idempotency_key = trim(idempotency_key)
      and idempotency_key !~ '[[:cntrl:]]'
    ),
  constraint verified_access_public_commands_fingerprint_check
    check (input_fingerprint ~ '^v1:[0-9a-f]{64}$'),
  constraint verified_access_public_commands_status_check
    check (status in ('PROCESSING', 'COMPLETED')),
  constraint verified_access_public_commands_result_payload_check
    check (
      result_payload is null
      or (
        jsonb_typeof(result_payload) = 'object'
        and result_payload - array[
          'sessionId', 'sessionStatus', 'requestType', 'startsAt', 'endsAt',
          'timezone', 'condominiumName', 'startedAt', 'registrationStatus',
          'invitationStatus', 'submittedAt', 'rateLimited',
          'retryAfterSeconds', 'resultCode'
        ]::text[] = '{}'::jsonb
      )
    ),
  constraint verified_access_public_commands_completion_check
    check (
      (status = 'PROCESSING' and completed_at is null)
      or (
        status = 'COMPLETED'
        and completed_at is not null
        and session_id is not null
        and nullif(trim(result_code), '') is not null
        and result_payload is not null
      )
    )
);

create unique index ux_verified_access_public_commands_idempotency
on public.verified_access_public_registration_commands(
  invitation_id,
  command_type,
  idempotency_key
);

create index idx_verified_access_public_commands_session
on public.verified_access_public_registration_commands(session_id)
where session_id is not null;

alter table public.verified_access_public_registration_commands enable row level security;

revoke all on table public.verified_access_public_registration_commands
from public, anon, authenticated, service_role;

create table public.verified_access_public_rate_limits (
  id uuid primary key default gen_random_uuid(),
  condominium_id uuid references public.condominiums(id) on delete cascade,
  scope text not null,
  subject_fingerprint text not null,
  window_started_at timestamptz not null,
  attempt_count integer not null default 1,
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint verified_access_public_rate_limits_scope_check
    check (scope in (
      'EXCHANGE_IP', 'EXCHANGE_INVITATION', 'SESSION_GET',
      'SESSION_START', 'SESSION_SUBMIT', 'DOCUMENT_DUPLICATE'
    )),
  constraint verified_access_public_rate_limits_fingerprint_check
    check (subject_fingerprint ~ '^v1:[0-9a-f]{64}$'),
  constraint verified_access_public_rate_limits_count_check
    check (attempt_count > 0),
  constraint verified_access_public_rate_limits_expiry_check
    check (expires_at > window_started_at)
);

create unique index ux_verified_access_public_rate_limits_window
on public.verified_access_public_rate_limits(
  scope,
  subject_fingerprint,
  window_started_at
) nulls not distinct;

create index idx_verified_access_public_rate_limits_expiry
on public.verified_access_public_rate_limits(expires_at);

alter table public.verified_access_public_rate_limits enable row level security;

revoke all on table public.verified_access_public_rate_limits
from public, anon, authenticated, service_role;

comment on table public.verified_access_public_sessions is
  'Phase 3B public sessions. Stores only opaque session hashes and no PII.';
comment on table public.verified_access_public_registration_commands is
  'Phase 3B idempotency records. Results and fingerprints contain no plaintext PII or tokens.';
comment on table public.verified_access_public_rate_limits is
  'Phase 3B local rate limits using short-lived keyed fingerprints, never raw IP or PII.';
