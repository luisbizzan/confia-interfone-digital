create table public.verified_access_request_commands (
  id uuid primary key default gen_random_uuid(),
  condominium_id uuid not null references public.condominiums(id) on delete cascade,
  actor_user_id uuid not null,
  command_type text not null,
  idempotency_key text not null,
  input_fingerprint text not null,
  request_id uuid,
  status text not null default 'PROCESSING',
  result_code text,
  result_payload jsonb,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  constraint verified_access_request_commands_actor_tenant_fk
    foreign key (actor_user_id, condominium_id)
    references public.user_profiles(id, condominium_id)
    on delete restrict,
  constraint verified_access_request_commands_request_tenant_fk
    foreign key (request_id, condominium_id)
    references public.verified_access_requests(id, condominium_id)
    on delete restrict,
  constraint verified_access_request_commands_type_check
    check (command_type in ('CREATE_REQUEST', 'CANCEL_REQUEST')),
  constraint verified_access_request_commands_status_check
    check (status in ('PROCESSING', 'COMPLETED')),
  constraint verified_access_request_commands_key_check
    check (
      char_length(idempotency_key) between 16 and 128
      and idempotency_key = trim(idempotency_key)
      and idempotency_key !~ '[[:cntrl:]]'
    ),
  constraint verified_access_request_commands_fingerprint_check
    check (input_fingerprint ~ '^v1:[0-9a-f]{64}$'),
  constraint verified_access_request_commands_payload_check
    check (result_payload is null or jsonb_typeof(result_payload) = 'object'),
  constraint verified_access_request_commands_completion_check
    check (
      (status = 'PROCESSING' and completed_at is null)
      or (
        status = 'COMPLETED'
        and completed_at is not null
        and request_id is not null
        and nullif(trim(result_code), '') is not null
      )
    ),
  constraint verified_access_request_commands_result_code_check
    check (result_code is null or char_length(trim(result_code)) between 2 and 80),
  constraint verified_access_request_commands_payload_sanitized_check
    check (
      result_payload is null
      or (
        position('CPF' in upper(result_payload::text)) = 0
        and position('DOCUMENT' in upper(result_payload::text)) = 0
        and position('DOC_NUMBER' in upper(result_payload::text)) = 0
        and position('DOCUMENTO' in upper(result_payload::text)) = 0
        and position('PHONE' in upper(result_payload::text)) = 0
        and position('TELEFONE' in upper(result_payload::text)) = 0
        and position('PERSON_NAME' in upper(result_payload::text)) = 0
        and position('NOME' in upper(result_payload::text)) = 0
        and position('BIOMETR' in upper(result_payload::text)) = 0
        and position('PURPOSE' in upper(result_payload::text)) = 0
        and position('OPERATIONAL' in upper(result_payload::text)) = 0
        and position('SERVICE_DESCRIPTION' in upper(result_payload::text)) = 0
      )
    )
);

create unique index ux_verified_access_request_commands_id_condominium
on public.verified_access_request_commands(id, condominium_id);

create unique index ux_verified_access_request_commands_idempotency
on public.verified_access_request_commands(
  condominium_id,
  actor_user_id,
  command_type,
  idempotency_key
);

create index idx_verified_access_request_commands_request
on public.verified_access_request_commands(request_id)
where request_id is not null;

alter table public.verified_access_request_commands enable row level security;

revoke all on table public.verified_access_request_commands
from public, anon, authenticated, service_role;

comment on table public.verified_access_request_commands is
  'Phase 2 resident request command idempotency. Default-deny and accessed only by exact resident RPCs.';
