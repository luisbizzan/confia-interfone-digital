create table public.verified_access_maintenance_findings (
  id uuid primary key default gen_random_uuid(),
  condominium_id uuid not null references public.condominiums(id) on delete restrict,
  aggregate_type text not null,
  aggregate_id uuid not null,
  related_id uuid,
  finding_code text not null,
  status text not null default 'OPEN',
  occurrence_count integer not null default 1,
  resolution_code text,
  correlation_id text,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  resolved_at timestamptz,
  constraint verified_access_maintenance_findings_aggregate_type_check
    check (aggregate_type in (
      'INVITATION',
      'PUBLIC_SESSION',
      'PARTICIPANT',
      'PARTICIPANT_SLOT',
      'PUBLIC_COMMAND',
      'OUTBOX_EVENT'
    )),
  constraint verified_access_maintenance_findings_code_check
    check (finding_code in (
      'INVITATION_COMPLETED_WITHOUT_PARTICIPANT',
      'PARTICIPANT_WITHOUT_SLOT',
      'SLOT_CLAIMED_WITHOUT_PARTICIPANT',
      'SESSION_COMPLETED_WITHOUT_INVITATION_COMPLETED',
      'INVITATION_ACTIVE_REQUEST_CANCELLED',
      'SESSION_ACTIVE_INVITATION_INVALID',
      'COMMAND_PROCESSING_STUCK',
      'OUTBOX_PENDING_OVERDUE'
    )),
  constraint verified_access_maintenance_findings_status_check
    check (status in ('OPEN', 'RESOLVED')),
  constraint verified_access_maintenance_findings_occurrence_check
    check (occurrence_count > 0),
  constraint verified_access_maintenance_findings_resolution_check
    check (
      (status = 'OPEN' and resolution_code is null and resolved_at is null)
      or (
        status = 'RESOLVED'
        and nullif(trim(resolution_code), '') is not null
        and resolved_at is not null
      )
    ),
  constraint verified_access_maintenance_findings_correlation_check
    check (
      correlation_id is null
      or (
        char_length(correlation_id) between 8 and 128
        and correlation_id = trim(correlation_id)
        and correlation_id !~ '[[:cntrl:]]'
      )
    ),
  constraint verified_access_maintenance_findings_period_check
    check (
      first_seen_at <= last_seen_at
      and (resolved_at is null or resolved_at >= first_seen_at)
    )
);

create unique index ux_verified_access_maintenance_findings_identity
on public.verified_access_maintenance_findings(
  condominium_id,
  finding_code,
  aggregate_id
);

create index idx_verified_access_maintenance_findings_open
on public.verified_access_maintenance_findings(last_seen_at, id)
where status = 'OPEN';

create index idx_verified_access_maintenance_findings_aggregate
on public.verified_access_maintenance_findings(aggregate_type, aggregate_id);

alter table public.verified_access_maintenance_findings enable row level security;

revoke all on table public.verified_access_maintenance_findings
from public, anon, authenticated, service_role;

create index idx_verified_access_invitations_terminal_retention
on public.verified_access_invitations(updated_at, id)
where status in ('COMPLETED', 'REVOKED', 'EXPIRED');

create index idx_verified_access_public_sessions_terminal_retention
on public.verified_access_public_sessions(updated_at, id)
where status in ('COMPLETED', 'REVOKED', 'EXPIRED');

create index idx_verified_access_public_commands_completed_retention
on public.verified_access_public_registration_commands(completed_at, id)
where status = 'COMPLETED';

create index idx_verified_access_public_commands_processing_age
on public.verified_access_public_registration_commands(created_at, id)
where status = 'PROCESSING';

create index idx_verified_access_outbox_processed_retention
on public.verified_access_outbox_events(updated_at, id)
where status = 'PROCESSED';

create index idx_verified_access_outbox_processing_lease
on public.verified_access_outbox_events(locked_at, id)
where status = 'PROCESSING';

comment on table public.verified_access_maintenance_findings is
  'Phase 3C sanitized operational findings. Contains identifiers and reason codes only; no PII or free-form payload.';
