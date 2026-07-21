create or replace function public.verified_access_phase3a_assert_token_hash(
  p_token_hash text
)
returns void
language plpgsql
immutable
security invoker
set search_path = public, pg_temp
as $$
begin
  if p_token_hash is null or p_token_hash !~ '^v1:[0-9a-f]{64}$' then
    raise exception 'INVITATION_TOKEN_HASH_INVALID' using errcode = '22023';
  end if;
end;
$$;

create or replace function public.verified_access_phase3a_validate_command_input(
  p_idempotency_key text,
  p_correlation_id text
)
returns void
language plpgsql
immutable
security invoker
set search_path = public, pg_temp
as $$
begin
  if p_idempotency_key is null
     or p_idempotency_key <> trim(p_idempotency_key)
     or char_length(p_idempotency_key) not between 16 and 128
     or p_idempotency_key ~ '[[:cntrl:]]'
     or p_correlation_id is null
     or char_length(trim(p_correlation_id)) not between 8 and 128
     or p_correlation_id ~ '[[:cntrl:]]' then
    raise exception 'INVITATION_PAYLOAD_INVALID' using errcode = '22023';
  end if;
end;
$$;

create or replace function public.verified_access_phase3a_expire_slot_invitations(
  p_condominium_id uuid,
  p_participant_slot_id uuid,
  p_actor_user_id uuid,
  p_correlation_id text
)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_invitation public.verified_access_invitations%rowtype;
  v_count integer := 0;
begin
  for v_invitation in
    update public.verified_access_invitations
       set status = 'EXPIRED', updated_at = now()
     where condominium_id = p_condominium_id
       and participant_slot_id = p_participant_slot_id
       and status in ('PENDING', 'SENT')
       and expires_at <= now()
    returning *
  loop
    v_count := v_count + 1;

    insert into public.verified_access_audit_events (
      condominium_id, aggregate_type, aggregate_id, event_type,
      actor_user_id, actor_type, reason_code, correlation_id, metadata
    ) values (
      p_condominium_id, 'INVITATION', v_invitation.id,
      'VERIFIED_ACCESS_INVITATION_EXPIRED', p_actor_user_id, 'USER',
      'INVITATION_EXPIRED', p_correlation_id,
      jsonb_build_object(
        'request_id', v_invitation.request_id,
        'participant_slot_id', v_invitation.participant_slot_id
      )
    );

    insert into public.verified_access_outbox_events (
      condominium_id, aggregate_type, aggregate_id, event_type,
      deduplication_key, payload
    ) values (
      p_condominium_id, 'INVITATION', v_invitation.id,
      'VERIFIED_ACCESS_INVITATION_EXPIRED',
      'verified-access:invitation:' || v_invitation.id || ':expired:v' || v_invitation.token_version,
      jsonb_build_object(
        'condominium_id', p_condominium_id,
        'request_id', v_invitation.request_id,
        'participant_slot_id', v_invitation.participant_slot_id,
        'invitation_id', v_invitation.id,
        'status', 'EXPIRED',
        'expires_at', v_invitation.expires_at,
        'event_code', 'VERIFIED_ACCESS_INVITATION_EXPIRED'
      )
    );
  end loop;

  return v_count;
end;
$$;

create or replace function public.verified_access_issue_resident_invitation(
  p_participant_slot_id uuid,
  p_token_hash text,
  p_idempotency_key text,
  p_correlation_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor_user_id uuid;
  v_condominium_id uuid;
  v_request public.verified_access_requests%rowtype;
  v_slot public.verified_access_participant_slots%rowtype;
  v_fingerprint text;
  v_command public.verified_access_invitation_commands%rowtype;
  v_invitation public.verified_access_invitations%rowtype;
  v_result jsonb;
  v_expires_at timestamptz;
begin
  select c.actor_user_id, c.condominium_id
    into v_actor_user_id, v_condominium_id
  from public.verified_access_phase2_context() c;

  perform public.verified_access_phase2_assert_feature(v_condominium_id);
  perform public.verified_access_phase3a_assert_token_hash(p_token_hash);
  perform public.verified_access_phase3a_validate_command_input(p_idempotency_key, p_correlation_id);

  select r.* into v_request
  from public.verified_access_requests r
  join public.verified_access_participant_slots s
    on s.request_id = r.id and s.condominium_id = r.condominium_id
  where s.id = p_participant_slot_id
    and r.condominium_id = v_condominium_id
    and r.requested_by_user_id = v_actor_user_id
  for update of r, s;

  select s.* into v_slot
  from public.verified_access_participant_slots s
  where s.id = p_participant_slot_id
    and s.request_id = v_request.id
    and s.condominium_id = v_condominium_id;

  if v_request.id is null then
    raise exception 'INVITATION_TARGET_NOT_FOUND' using errcode = 'P0001';
  end if;

  perform public.verified_access_phase2_assert_resident_unit(
    v_actor_user_id, v_condominium_id, v_request.unit_id
  );

  if v_request.status not in ('DRAFT', 'INVITATIONS_PENDING')
     or v_request.ends_at <= now()
     or v_slot.status <> 'OPEN' then
    raise exception 'INVITATION_STATE_CONFLICT' using errcode = 'P0001';
  end if;

  if not exists (
    select 1 from public.verified_access_policies p
    where p.condominium_id = v_condominium_id and p.status = 'ACTIVE'
  ) then
    raise exception 'POLICY_NOT_AVAILABLE' using errcode = 'P0001';
  end if;

  v_fingerprint := public.verified_access_phase2_fingerprint(
    jsonb_build_object('participantSlotId', p_participant_slot_id)
  );

  insert into public.verified_access_invitation_commands (
    condominium_id, actor_user_id, command_type, idempotency_key,
    input_fingerprint, participant_slot_id, status
  ) values (
    v_condominium_id, v_actor_user_id, 'ISSUE', p_idempotency_key,
    v_fingerprint, p_participant_slot_id, 'PROCESSING'
  )
  on conflict (condominium_id, actor_user_id, command_type, idempotency_key) do nothing
  returning * into v_command;

  if v_command.id is null then
    select c.* into v_command
    from public.verified_access_invitation_commands c
    where c.condominium_id = v_condominium_id
      and c.actor_user_id = v_actor_user_id
      and c.command_type = 'ISSUE'
      and c.idempotency_key = p_idempotency_key
    for update;

    if v_command.input_fingerprint <> v_fingerprint then
      raise exception 'IDEMPOTENCY_CONFLICT' using errcode = 'P0001';
    end if;
    if v_command.status = 'PROCESSING' then
      raise exception 'COMMAND_IN_PROGRESS' using errcode = 'P0001';
    end if;
    return v_command.result_payload || jsonb_build_object('dispatchRequired', false);
  end if;

  perform public.verified_access_phase3a_expire_slot_invitations(
    v_condominium_id, p_participant_slot_id, v_actor_user_id, p_correlation_id
  );

  if exists (
    select 1 from public.verified_access_invitations i
    where i.participant_slot_id = p_participant_slot_id
      and i.status in ('PENDING', 'SENT')
  ) then
    raise exception 'INVITATION_ALREADY_ACTIVE' using errcode = 'P0001';
  end if;

  v_expires_at := least(v_request.ends_at, now() + interval '24 hours');
  if v_expires_at <= now() then
    raise exception 'INVITATION_STATE_CONFLICT' using errcode = 'P0001';
  end if;

  insert into public.verified_access_invitations (
    condominium_id, request_id, participant_slot_id, token_hash,
    token_version, status, expires_at, issued_at, last_sent_at, send_count,
    created_by_user_id
  ) values (
    v_condominium_id, v_request.id, p_participant_slot_id, p_token_hash,
    1, 'PENDING', v_expires_at, now(), now(), 1, v_actor_user_id
  ) returning * into v_invitation;

  if v_request.status = 'DRAFT' then
    update public.verified_access_requests
       set status = 'INVITATIONS_PENDING', updated_at = now(), version = version + 1
     where id = v_request.id;
  end if;

  insert into public.verified_access_audit_events (
    condominium_id, aggregate_type, aggregate_id, event_type,
    actor_user_id, actor_type, reason_code, correlation_id, metadata
  ) values (
    v_condominium_id, 'INVITATION', v_invitation.id,
    'VERIFIED_ACCESS_INVITATION_ISSUED', v_actor_user_id, 'USER',
    'INVITATION_ISSUED', p_correlation_id,
    jsonb_build_object(
      'request_id', v_request.id,
      'participant_slot_id', p_participant_slot_id,
      'send_count', 1
    )
  );

  insert into public.verified_access_outbox_events (
    condominium_id, aggregate_type, aggregate_id, event_type,
    deduplication_key, payload
  ) values (
    v_condominium_id, 'INVITATION', v_invitation.id,
    'VERIFIED_ACCESS_INVITATION_ISSUED',
    'verified-access:command:' || v_command.id || ':invitation-issued:v1',
    jsonb_build_object(
      'condominium_id', v_condominium_id,
      'request_id', v_request.id,
      'participant_slot_id', p_participant_slot_id,
      'invitation_id', v_invitation.id,
      'status', 'PENDING',
      'expires_at', v_expires_at,
      'send_count', 1,
      'event_code', 'VERIFIED_ACCESS_INVITATION_ISSUED'
    )
  );

  v_result := jsonb_build_object(
    'invitationId', v_invitation.id,
    'requestId', v_request.id,
    'participantSlotId', p_participant_slot_id,
    'invitationStatus', 'PENDING',
    'tokenVersion', 1,
    'expiresAt', v_expires_at
  );

  update public.verified_access_invitation_commands
     set invitation_id = v_invitation.id,
         status = 'COMPLETED',
         result_code = 'INVITATION_ISSUED',
         result_payload = v_result,
         completed_at = now()
   where id = v_command.id;

  return v_result || jsonb_build_object(
    'dispatchRequired', true,
    'commandId', v_command.id,
    'condominiumId', v_condominium_id
  );
end;
$$;

create or replace function public.verified_access_resend_resident_invitation(
  p_invitation_id uuid,
  p_token_hash text,
  p_idempotency_key text,
  p_correlation_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor_user_id uuid;
  v_condominium_id uuid;
  v_request public.verified_access_requests%rowtype;
  v_invitation public.verified_access_invitations%rowtype;
  v_fingerprint text;
  v_command public.verified_access_invitation_commands%rowtype;
  v_result jsonb;
  v_expires_at timestamptz;
begin
  select c.actor_user_id, c.condominium_id
    into v_actor_user_id, v_condominium_id
  from public.verified_access_phase2_context() c;

  perform public.verified_access_phase2_assert_feature(v_condominium_id);
  perform public.verified_access_phase3a_assert_token_hash(p_token_hash);
  perform public.verified_access_phase3a_validate_command_input(p_idempotency_key, p_correlation_id);

  select r.* into v_request
  from public.verified_access_invitations i
  join public.verified_access_requests r
    on r.id = i.request_id and r.condominium_id = i.condominium_id
  where i.id = p_invitation_id
    and i.condominium_id = v_condominium_id
    and r.requested_by_user_id = v_actor_user_id
  for update of r, i;

  select i.* into v_invitation
  from public.verified_access_invitations i
  where i.id = p_invitation_id
    and i.request_id = v_request.id
    and i.condominium_id = v_condominium_id;

  if v_invitation.id is null then
    raise exception 'INVITATION_NOT_FOUND' using errcode = 'P0001';
  end if;

  perform public.verified_access_phase2_assert_resident_unit(
    v_actor_user_id, v_condominium_id, v_request.unit_id
  );

  if not exists (
    select 1 from public.verified_access_policies p
    where p.condominium_id = v_condominium_id and p.status = 'ACTIVE'
  ) then
    raise exception 'POLICY_NOT_AVAILABLE' using errcode = 'P0001';
  end if;

  perform public.verified_access_phase3a_expire_slot_invitations(
    v_condominium_id, v_invitation.participant_slot_id,
    v_actor_user_id, p_correlation_id
  );

  select * into v_invitation
  from public.verified_access_invitations
  where id = p_invitation_id
  for update;

  if v_invitation.status = 'EXPIRED' then
    return jsonb_build_object(
      'invitationId', v_invitation.id,
      'requestId', v_request.id,
      'participantSlotId', v_invitation.participant_slot_id,
      'invitationStatus', 'EXPIRED',
      'tokenVersion', v_invitation.token_version,
      'expiresAt', v_invitation.expires_at,
      'dispatchRequired', false
    );
  end if;

  if v_invitation.status not in ('PENDING', 'SENT')
     or v_request.status not in ('DRAFT', 'INVITATIONS_PENDING')
     or v_request.ends_at <= now() then
    raise exception 'INVITATION_STATE_CONFLICT' using errcode = 'P0001';
  end if;

  v_fingerprint := public.verified_access_phase2_fingerprint(
    jsonb_build_object('invitationId', p_invitation_id)
  );

  insert into public.verified_access_invitation_commands (
    condominium_id, actor_user_id, command_type, idempotency_key,
    input_fingerprint, invitation_id, participant_slot_id, status
  ) values (
    v_condominium_id, v_actor_user_id, 'RESEND', p_idempotency_key,
    v_fingerprint, p_invitation_id, v_invitation.participant_slot_id, 'PROCESSING'
  )
  on conflict (condominium_id, actor_user_id, command_type, idempotency_key) do nothing
  returning * into v_command;

  if v_command.id is null then
    select c.* into v_command
    from public.verified_access_invitation_commands c
    where c.condominium_id = v_condominium_id
      and c.actor_user_id = v_actor_user_id
      and c.command_type = 'RESEND'
      and c.idempotency_key = p_idempotency_key
    for update;
    if v_command.input_fingerprint <> v_fingerprint then
      raise exception 'IDEMPOTENCY_CONFLICT' using errcode = 'P0001';
    end if;
    if v_command.status = 'PROCESSING' then
      raise exception 'COMMAND_IN_PROGRESS' using errcode = 'P0001';
    end if;
    return v_command.result_payload || jsonb_build_object('dispatchRequired', false);
  end if;

  v_expires_at := least(v_request.ends_at, now() + interval '24 hours');

  update public.verified_access_invitations
     set token_hash = p_token_hash,
         token_version = token_version + 1,
         status = 'PENDING',
         expires_at = v_expires_at,
         issued_at = now(),
         last_sent_at = now(),
         send_count = send_count + 1,
         updated_at = now()
   where id = p_invitation_id
  returning * into v_invitation;

  insert into public.verified_access_audit_events (
    condominium_id, aggregate_type, aggregate_id, event_type,
    actor_user_id, actor_type, reason_code, correlation_id, metadata
  ) values (
    v_condominium_id, 'INVITATION', v_invitation.id,
    'VERIFIED_ACCESS_INVITATION_RESENT', v_actor_user_id, 'USER',
    'INVITATION_RESENT', p_correlation_id,
    jsonb_build_object(
      'request_id', v_request.id,
      'participant_slot_id', v_invitation.participant_slot_id,
      'send_count', v_invitation.send_count
    )
  );

  insert into public.verified_access_outbox_events (
    condominium_id, aggregate_type, aggregate_id, event_type,
    deduplication_key, payload
  ) values (
    v_condominium_id, 'INVITATION', v_invitation.id,
    'VERIFIED_ACCESS_INVITATION_RESENT',
    'verified-access:command:' || v_command.id || ':invitation-resent:v1',
    jsonb_build_object(
      'condominium_id', v_condominium_id,
      'request_id', v_request.id,
      'participant_slot_id', v_invitation.participant_slot_id,
      'invitation_id', v_invitation.id,
      'status', 'PENDING',
      'expires_at', v_expires_at,
      'send_count', v_invitation.send_count,
      'event_code', 'VERIFIED_ACCESS_INVITATION_RESENT'
    )
  );

  v_result := jsonb_build_object(
    'invitationId', v_invitation.id,
    'requestId', v_request.id,
    'participantSlotId', v_invitation.participant_slot_id,
    'invitationStatus', 'PENDING',
    'tokenVersion', v_invitation.token_version,
    'expiresAt', v_expires_at
  );

  update public.verified_access_invitation_commands
     set status = 'COMPLETED',
         result_code = 'INVITATION_RESENT',
         result_payload = v_result,
         completed_at = now()
   where id = v_command.id;

  return v_result || jsonb_build_object(
    'dispatchRequired', true,
    'commandId', v_command.id,
    'condominiumId', v_condominium_id
  );
end;
$$;

create or replace function public.verified_access_revoke_resident_invitation(
  p_invitation_id uuid,
  p_idempotency_key text,
  p_reason_code text,
  p_correlation_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor_user_id uuid;
  v_condominium_id uuid;
  v_request public.verified_access_requests%rowtype;
  v_invitation public.verified_access_invitations%rowtype;
  v_reason_code text := upper(trim(coalesce(p_reason_code, '')));
  v_fingerprint text;
  v_command public.verified_access_invitation_commands%rowtype;
  v_result jsonb;
begin
  select c.actor_user_id, c.condominium_id
    into v_actor_user_id, v_condominium_id
  from public.verified_access_phase2_context() c;
  perform public.verified_access_phase2_assert_feature(v_condominium_id);
  perform public.verified_access_phase3a_validate_command_input(p_idempotency_key, p_correlation_id);

  if v_reason_code <> 'RESIDENT_REVOKED' then
    raise exception 'INVITATION_PAYLOAD_INVALID' using errcode = '22023';
  end if;

  select r.* into v_request
  from public.verified_access_invitations i
  join public.verified_access_requests r
    on r.id = i.request_id and r.condominium_id = i.condominium_id
  where i.id = p_invitation_id
    and i.condominium_id = v_condominium_id
    and r.requested_by_user_id = v_actor_user_id
  for update of r, i;

  select i.* into v_invitation
  from public.verified_access_invitations i
  where i.id = p_invitation_id
    and i.request_id = v_request.id
    and i.condominium_id = v_condominium_id;

  if v_invitation.id is null then
    raise exception 'INVITATION_NOT_FOUND' using errcode = 'P0001';
  end if;

  perform public.verified_access_phase2_assert_resident_unit(
    v_actor_user_id, v_condominium_id, v_request.unit_id
  );

  v_fingerprint := public.verified_access_phase2_fingerprint(
    jsonb_build_object('invitationId', p_invitation_id, 'reasonCode', v_reason_code)
  );

  insert into public.verified_access_invitation_commands (
    condominium_id, actor_user_id, command_type, idempotency_key,
    input_fingerprint, invitation_id, participant_slot_id, status
  ) values (
    v_condominium_id, v_actor_user_id, 'REVOKE', p_idempotency_key,
    v_fingerprint, p_invitation_id, v_invitation.participant_slot_id, 'PROCESSING'
  )
  on conflict (condominium_id, actor_user_id, command_type, idempotency_key) do nothing
  returning * into v_command;

  if v_command.id is null then
    select c.* into v_command
    from public.verified_access_invitation_commands c
    where c.condominium_id = v_condominium_id
      and c.actor_user_id = v_actor_user_id
      and c.command_type = 'REVOKE'
      and c.idempotency_key = p_idempotency_key
    for update;
    if v_command.input_fingerprint <> v_fingerprint then
      raise exception 'IDEMPOTENCY_CONFLICT' using errcode = 'P0001';
    end if;
    if v_command.status = 'PROCESSING' then
      raise exception 'COMMAND_IN_PROGRESS' using errcode = 'P0001';
    end if;
    return v_command.result_payload || jsonb_build_object('dispatchRequired', false);
  end if;

  perform public.verified_access_phase3a_expire_slot_invitations(
    v_condominium_id, v_invitation.participant_slot_id,
    v_actor_user_id, p_correlation_id
  );

  select * into v_invitation
  from public.verified_access_invitations
  where id = p_invitation_id
  for update;

  if v_invitation.status = 'EXPIRED' then
    v_result := jsonb_build_object(
      'invitationId', v_invitation.id,
      'requestId', v_request.id,
      'participantSlotId', v_invitation.participant_slot_id,
      'invitationStatus', 'EXPIRED',
      'tokenVersion', v_invitation.token_version,
      'expiresAt', v_invitation.expires_at
    );
    update public.verified_access_invitation_commands
       set status = 'COMPLETED', result_code = 'INVITATION_EXPIRED',
           result_payload = v_result, completed_at = now()
     where id = v_command.id;
    return v_result || jsonb_build_object('dispatchRequired', false);
  end if;

  if v_invitation.status not in ('PENDING', 'SENT') then
    raise exception 'INVITATION_STATE_CONFLICT' using errcode = 'P0001';
  end if;

  update public.verified_access_invitations
     set status = 'REVOKED', revoked_at = now(), updated_at = now()
   where id = p_invitation_id
  returning * into v_invitation;

  insert into public.verified_access_audit_events (
    condominium_id, aggregate_type, aggregate_id, event_type,
    actor_user_id, actor_type, reason_code, correlation_id, metadata
  ) values (
    v_condominium_id, 'INVITATION', v_invitation.id,
    'VERIFIED_ACCESS_INVITATION_REVOKED', v_actor_user_id, 'USER',
    v_reason_code, p_correlation_id,
    jsonb_build_object(
      'request_id', v_request.id,
      'participant_slot_id', v_invitation.participant_slot_id,
      'send_count', v_invitation.send_count
    )
  );

  insert into public.verified_access_outbox_events (
    condominium_id, aggregate_type, aggregate_id, event_type,
    deduplication_key, payload
  ) values (
    v_condominium_id, 'INVITATION', v_invitation.id,
    'VERIFIED_ACCESS_INVITATION_REVOKED',
    'verified-access:command:' || v_command.id || ':invitation-revoked:v1',
    jsonb_build_object(
      'condominium_id', v_condominium_id,
      'request_id', v_request.id,
      'participant_slot_id', v_invitation.participant_slot_id,
      'invitation_id', v_invitation.id,
      'status', 'REVOKED',
      'revoked_at', v_invitation.revoked_at,
      'send_count', v_invitation.send_count,
      'event_code', 'VERIFIED_ACCESS_INVITATION_REVOKED'
    )
  );

  v_result := jsonb_build_object(
    'invitationId', v_invitation.id,
    'requestId', v_request.id,
    'participantSlotId', v_invitation.participant_slot_id,
    'invitationStatus', 'REVOKED',
    'tokenVersion', v_invitation.token_version,
    'expiresAt', v_invitation.expires_at
  );

  update public.verified_access_invitation_commands
     set status = 'COMPLETED',
         result_code = 'INVITATION_REVOKED',
         result_payload = v_result,
         completed_at = now()
   where id = v_command.id;

  return v_result || jsonb_build_object('dispatchRequired', false);
end;
$$;

create or replace function public.verified_access_list_resident_invitation_status(
  p_request_id uuid
)
returns table (
  invitation_id uuid,
  request_id uuid,
  participant_slot_id uuid,
  slot_number integer,
  invitation_status text,
  token_version integer,
  expires_at timestamptz,
  send_count integer,
  last_sent_at timestamptz
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor_user_id uuid;
  v_condominium_id uuid;
  v_unit_id uuid;
begin
  select c.actor_user_id, c.condominium_id
    into v_actor_user_id, v_condominium_id
  from public.verified_access_phase2_context() c;
  perform public.verified_access_phase2_assert_feature(v_condominium_id);

  select r.unit_id into v_unit_id
  from public.verified_access_requests r
  where r.id = p_request_id
    and r.condominium_id = v_condominium_id
    and r.requested_by_user_id = v_actor_user_id;

  if v_unit_id is null then
    raise exception 'REQUEST_NOT_FOUND' using errcode = 'P0001';
  end if;

  perform public.verified_access_phase2_assert_resident_unit(
    v_actor_user_id, v_condominium_id, v_unit_id
  );

  return query
  select
    i.id,
    i.request_id,
    i.participant_slot_id,
    s.slot_number,
    case
      when i.status in ('PENDING', 'SENT') and i.expires_at <= now() then 'EXPIRED'
      else i.status
    end,
    i.token_version,
    i.expires_at,
    i.send_count,
    i.last_sent_at
  from public.verified_access_invitations i
  join public.verified_access_participant_slots s
    on s.id = i.participant_slot_id
   and s.request_id = i.request_id
   and s.condominium_id = i.condominium_id
  where i.request_id = p_request_id
    and i.condominium_id = v_condominium_id
  order by s.slot_number, i.created_at desc;
end;
$$;

revoke execute on function public.verified_access_phase3a_assert_token_hash(text)
from public, anon, authenticated, service_role;
revoke execute on function public.verified_access_phase3a_validate_command_input(text, text)
from public, anon, authenticated, service_role;
revoke execute on function public.verified_access_phase3a_expire_slot_invitations(uuid, uuid, uuid, text)
from public, anon, authenticated, service_role;

revoke execute on function public.verified_access_issue_resident_invitation(uuid, text, text, text)
from public, anon, authenticated, service_role;
revoke execute on function public.verified_access_resend_resident_invitation(uuid, text, text, text)
from public, anon, authenticated, service_role;
revoke execute on function public.verified_access_revoke_resident_invitation(uuid, text, text, text)
from public, anon, authenticated, service_role;
revoke execute on function public.verified_access_list_resident_invitation_status(uuid)
from public, anon, authenticated, service_role;

do $$
begin
  if not exists (
    select 1 from pg_roles where rolname = 'verified_access_phase3a_resident_executor'
  ) then
    create role verified_access_phase3a_resident_executor nologin noinherit;
  end if;
end;
$$;

alter role verified_access_phase3a_resident_executor nologin noinherit;

grant execute on function public.verified_access_issue_resident_invitation(uuid, text, text, text)
to verified_access_phase3a_resident_executor;
grant execute on function public.verified_access_resend_resident_invitation(uuid, text, text, text)
to verified_access_phase3a_resident_executor;
grant execute on function public.verified_access_revoke_resident_invitation(uuid, text, text, text)
to verified_access_phase3a_resident_executor;
grant execute on function public.verified_access_list_resident_invitation_status(uuid)
to verified_access_phase3a_resident_executor;

grant verified_access_phase3a_resident_executor to authenticated;

comment on function public.verified_access_issue_resident_invitation(uuid, text, text, text) is
  'Phase 3A authenticated local invitation issue. Token hash only; no participant or PII.';
