create table public.verified_access_invitations (
  id uuid primary key default gen_random_uuid(),
  condominium_id uuid not null references public.condominiums(id) on delete cascade,
  request_id uuid not null,
  participant_slot_id uuid not null,
  token_hash text not null,
  token_version integer not null default 1,
  status text not null default 'PENDING',
  expires_at timestamptz not null,
  issued_at timestamptz not null default now(),
  revoked_at timestamptz,
  consumed_at timestamptz,
  last_sent_at timestamptz,
  send_count integer not null default 0,
  created_by_user_id uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint verified_access_invitations_request_tenant_fk
    foreign key (request_id, condominium_id)
    references public.verified_access_requests(id, condominium_id)
    on delete cascade,
  constraint verified_access_invitations_slot_request_tenant_fk
    foreign key (participant_slot_id, request_id, condominium_id)
    references public.verified_access_participant_slots(id, request_id, condominium_id)
    on delete restrict,
  constraint verified_access_invitations_creator_tenant_fk
    foreign key (created_by_user_id, condominium_id)
    references public.user_profiles(id, condominium_id)
    on delete restrict,
  constraint verified_access_invitations_token_hash_check
    check (token_hash ~ '^v1:[0-9a-f]{64}$'),
  constraint verified_access_invitations_token_version_check
    check (token_version > 0),
  constraint verified_access_invitations_status_check
    check (status in ('PENDING', 'SENT', 'OPENED', 'COMPLETED', 'REVOKED', 'EXPIRED')),
  constraint verified_access_invitations_period_check
    check (issued_at < expires_at),
  constraint verified_access_invitations_send_count_check
    check (send_count >= 0),
  constraint verified_access_invitations_status_timestamps_check
    check (
      (status in ('PENDING', 'SENT') and revoked_at is null and consumed_at is null)
      or (status = 'OPENED' and revoked_at is null)
      or (status = 'COMPLETED' and revoked_at is null and consumed_at is not null)
      or (status = 'REVOKED' and revoked_at is not null and consumed_at is null)
      or (status = 'EXPIRED' and revoked_at is null and consumed_at is null)
    )
);

create unique index ux_verified_access_invitations_id_condominium
on public.verified_access_invitations(id, condominium_id);

create unique index ux_verified_access_invitations_id_request_condominium
on public.verified_access_invitations(id, request_id, condominium_id);

create unique index ux_verified_access_invitations_token_hash
on public.verified_access_invitations(token_hash);

create unique index ux_verified_access_invitations_active_slot
on public.verified_access_invitations(participant_slot_id)
where status in ('PENDING', 'SENT');

create index idx_verified_access_invitations_request_status
on public.verified_access_invitations(request_id, status);

create index idx_verified_access_invitations_expiration
on public.verified_access_invitations(expires_at)
where status in ('PENDING', 'SENT');

alter table public.verified_access_invitations enable row level security;

revoke all on table public.verified_access_invitations
from public, anon, authenticated, service_role;

create table public.verified_access_invitation_commands (
  id uuid primary key default gen_random_uuid(),
  condominium_id uuid not null references public.condominiums(id) on delete cascade,
  actor_user_id uuid not null,
  command_type text not null,
  idempotency_key text not null,
  input_fingerprint text not null,
  invitation_id uuid,
  participant_slot_id uuid not null,
  status text not null default 'PROCESSING',
  result_code text,
  result_payload jsonb,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  constraint verified_access_invitation_commands_actor_tenant_fk
    foreign key (actor_user_id, condominium_id)
    references public.user_profiles(id, condominium_id)
    on delete restrict,
  constraint verified_access_invitation_commands_invitation_tenant_fk
    foreign key (invitation_id, condominium_id)
    references public.verified_access_invitations(id, condominium_id)
    on delete restrict,
  constraint verified_access_invitation_commands_slot_tenant_fk
    foreign key (participant_slot_id, condominium_id)
    references public.verified_access_participant_slots(id, condominium_id)
    on delete restrict,
  constraint verified_access_invitation_commands_type_check
    check (command_type in ('ISSUE', 'RESEND', 'REVOKE')),
  constraint verified_access_invitation_commands_status_check
    check (status in ('PROCESSING', 'COMPLETED')),
  constraint verified_access_invitation_commands_key_check
    check (
      char_length(idempotency_key) between 16 and 128
      and idempotency_key = trim(idempotency_key)
      and idempotency_key !~ '[[:cntrl:]]'
    ),
  constraint verified_access_invitation_commands_fingerprint_check
    check (input_fingerprint ~ '^v1:[0-9a-f]{64}$'),
  constraint verified_access_invitation_commands_payload_check
    check (
      result_payload is null
      or (
        jsonb_typeof(result_payload) = 'object'
        and result_payload - array[
          'invitationId', 'requestId', 'participantSlotId',
          'invitationStatus', 'tokenVersion', 'expiresAt'
        ]::text[] = '{}'::jsonb
      )
    ),
  constraint verified_access_invitation_commands_completion_check
    check (
      (status = 'PROCESSING' and completed_at is null)
      or (
        status = 'COMPLETED'
        and completed_at is not null
        and invitation_id is not null
        and nullif(trim(result_code), '') is not null
        and result_payload is not null
      )
    )
);

create unique index ux_verified_access_invitation_commands_id_condominium
on public.verified_access_invitation_commands(id, condominium_id);

create unique index ux_verified_access_invitation_commands_idempotency
on public.verified_access_invitation_commands(
  condominium_id,
  actor_user_id,
  command_type,
  idempotency_key
);

create index idx_verified_access_invitation_commands_invitation
on public.verified_access_invitation_commands(invitation_id)
where invitation_id is not null;

alter table public.verified_access_invitation_commands enable row level security;

revoke all on table public.verified_access_invitation_commands
from public, anon, authenticated, service_role;

comment on table public.verified_access_invitations is
  'Phase 3A local invitations. Stores only versioned token hashes and no PII.';
comment on table public.verified_access_invitation_commands is
  'Phase 3A resident invitation idempotency. Default-deny and token-free.';
