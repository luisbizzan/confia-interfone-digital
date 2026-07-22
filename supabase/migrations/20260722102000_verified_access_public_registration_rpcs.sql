create or replace function public.verified_access_phase3b_assert_hash(
  p_value text,
  p_error_code text
)
returns void
language plpgsql
immutable
security invoker
set search_path = public, pg_temp
as $$
begin
  if p_value is null or p_value !~ '^v1:[0-9a-f]{64}$' then
    raise exception '%', p_error_code using errcode = '22023';
  end if;
end;
$$;

create or replace function public.verified_access_phase3b_assert_command_input(
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
    raise exception 'PUBLIC_REGISTRATION_PAYLOAD_INVALID' using errcode = '22023';
  end if;
end;
$$;

create or replace function public.verified_access_phase3b_rate_limit(
  p_scope text,
  p_subject_fingerprint text,
  p_limit integer,
  p_window interval,
  p_condominium_id uuid default null
)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_window_started_at timestamptz;
  v_count integer;
begin
  perform public.verified_access_phase3b_assert_hash(
    p_subject_fingerprint,
    'PUBLIC_RATE_FINGERPRINT_INVALID'
  );

  if p_scope not in (
    'EXCHANGE_IP', 'EXCHANGE_INVITATION', 'SESSION_GET',
    'SESSION_START', 'SESSION_SUBMIT', 'DOCUMENT_DUPLICATE'
  ) or p_limit <= 0 or p_window <= interval '0 seconds' then
    raise exception 'PUBLIC_RATE_LIMIT_CONFIGURATION_INVALID' using errcode = '22023';
  end if;

  v_window_started_at := date_bin(p_window, now(), timestamptz '2000-01-01 00:00:00+00');

  insert into public.verified_access_public_rate_limits (
    condominium_id, scope, subject_fingerprint, window_started_at,
    attempt_count, expires_at
  ) values (
    p_condominium_id, p_scope, p_subject_fingerprint, v_window_started_at,
    1, v_window_started_at + p_window + interval '5 minutes'
  )
  on conflict (scope, subject_fingerprint, window_started_at)
  do update set
    attempt_count = public.verified_access_public_rate_limits.attempt_count + 1,
    updated_at = now()
  returning attempt_count into v_count;

  return v_count;
end;
$$;

create or replace function public.verified_access_phase3b_validate_session_transition()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
begin
  if old.status is distinct from new.status
     and not (old.status = 'ACTIVE' and new.status in ('REVOKED', 'EXPIRED', 'COMPLETED')) then
    raise exception 'PUBLIC_SESSION_STATUS_TRANSITION_INVALID' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

create trigger verified_access_public_sessions_validate_transition
before update of status on public.verified_access_public_sessions
for each row execute function public.verified_access_phase3b_validate_session_transition();

create or replace function public.verified_access_phase3b_invalidate_sessions_for_invitation()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_session_id uuid;
begin
  if old.token_hash is not distinct from new.token_hash
     and not (old.status is distinct from new.status and new.status in ('REVOKED', 'EXPIRED', 'COMPLETED')) then
    return new;
  end if;

  for v_session_id in
    update public.verified_access_public_sessions
       set status = 'REVOKED', revoked_at = now(), updated_at = now()
     where invitation_id = new.id and status = 'ACTIVE'
    returning id
  loop
    perform public.verified_access_write_audit_event(
      new.condominium_id, 'SYSTEM', null, 'PUBLIC_SESSION', v_session_id,
      'VERIFIED_ACCESS_PUBLIC_SESSION_REVOKED', 'INVITATION_INVALIDATED',
      'phase3b-invitation-invalidation',
      jsonb_build_object('invitation_id', new.id, 'request_id', new.request_id)
    );
    perform public.verified_access_enqueue_outbox_event(
      new.condominium_id, 'PUBLIC_SESSION', v_session_id,
      'VERIFIED_ACCESS_PUBLIC_SESSION_REVOKED',
      'verified-access:public-session:' || v_session_id || ':revoked',
      jsonb_build_object(
        'condominium_id', new.condominium_id,
        'invitation_id', new.id,
        'request_id', new.request_id,
        'session_id', v_session_id,
        'status', 'REVOKED',
        'event_code', 'VERIFIED_ACCESS_PUBLIC_SESSION_REVOKED'
      )
    );
  end loop;
  return new;
end;
$$;

create trigger verified_access_invitations_invalidate_public_sessions
after update of token_hash, status on public.verified_access_invitations
for each row execute function public.verified_access_phase3b_invalidate_sessions_for_invitation();

drop index public.ux_verified_access_invitations_active_slot;
create unique index ux_verified_access_invitations_active_slot
on public.verified_access_invitations(participant_slot_id)
where status in ('PENDING', 'SENT', 'OPENED');

create or replace function public.verified_access_public_exchange_invitation(
  p_invitation_token_hash text,
  p_session_token_hash text,
  p_idempotency_key text,
  p_input_fingerprint text,
  p_ip_fingerprint text,
  p_invitation_fingerprint text,
  p_correlation_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_invitation public.verified_access_invitations%rowtype;
  v_request public.verified_access_requests%rowtype;
  v_command public.verified_access_public_registration_commands%rowtype;
  v_session public.verified_access_public_sessions%rowtype;
  v_condominium_name text;
  v_result jsonb;
  v_revoked_session_id uuid;
begin
  perform public.verified_access_phase3b_assert_hash(p_invitation_token_hash, 'PUBLIC_ACCESS_UNAVAILABLE');
  perform public.verified_access_phase3b_assert_hash(p_session_token_hash, 'PUBLIC_SESSION_TOKEN_INVALID');
  perform public.verified_access_phase3b_assert_hash(p_input_fingerprint, 'PUBLIC_INPUT_FINGERPRINT_INVALID');
  perform public.verified_access_phase3b_assert_hash(p_ip_fingerprint, 'PUBLIC_RATE_FINGERPRINT_INVALID');
  perform public.verified_access_phase3b_assert_hash(p_invitation_fingerprint, 'PUBLIC_RATE_FINGERPRINT_INVALID');
  perform public.verified_access_phase3b_assert_command_input(p_idempotency_key, p_correlation_id);

  if public.verified_access_phase3b_rate_limit('EXCHANGE_IP', p_ip_fingerprint, 10, interval '10 minutes') > 10
     or public.verified_access_phase3b_rate_limit('EXCHANGE_INVITATION', p_invitation_fingerprint, 5, interval '15 minutes') > 5 then
    return jsonb_build_object('rateLimited', true, 'retryAfterSeconds', 900, 'resultCode', 'RATE_LIMITED');
  end if;

  select i.* into v_invitation
  from public.verified_access_invitations i
  where i.token_hash = p_invitation_token_hash
  for update;

  if v_invitation.id is null
     or v_invitation.status not in ('PENDING', 'SENT', 'OPENED')
     or v_invitation.expires_at <= now() then
    return jsonb_build_object('resultCode', 'PUBLIC_ACCESS_UNAVAILABLE');
  end if;

  select r.* into v_request
  from public.verified_access_requests r
  where r.id = v_invitation.request_id
    and r.condominium_id = v_invitation.condominium_id
  for update;

  if v_request.id is null
     or v_request.status not in ('INVITATIONS_PENDING', 'IN_PROGRESS')
     or v_request.ends_at <= now()
     or not exists (
       select 1 from public.verified_access_participant_slots s
       where s.id = v_invitation.participant_slot_id
         and s.request_id = v_request.id
         and s.condominium_id = v_request.condominium_id
         and s.status = 'OPEN'
     ) then
    return jsonb_build_object('resultCode', 'PUBLIC_ACCESS_UNAVAILABLE');
  end if;

  perform public.verified_access_phase2_assert_feature(v_invitation.condominium_id);

  select c.* into v_command
  from public.verified_access_public_registration_commands c
  where c.invitation_id = v_invitation.id
    and c.command_type = 'EXCHANGE'
    and c.idempotency_key = p_idempotency_key
  for update;

  if v_command.id is not null then
    if v_command.input_fingerprint <> p_input_fingerprint then
      raise exception 'IDEMPOTENCY_CONFLICT' using errcode = 'P0001';
    end if;
    if v_command.status = 'PROCESSING' then
      raise exception 'COMMAND_IN_PROGRESS' using errcode = 'P0001';
    end if;
    return v_command.result_payload;
  end if;

  insert into public.verified_access_public_registration_commands (
    condominium_id, invitation_id, command_type, idempotency_key,
    input_fingerprint, status
  ) values (
    v_invitation.condominium_id, v_invitation.id, 'EXCHANGE',
    p_idempotency_key, p_input_fingerprint, 'PROCESSING'
  ) returning * into v_command;

  for v_revoked_session_id in
    update public.verified_access_public_sessions
       set status = 'REVOKED', revoked_at = now(), updated_at = now()
     where invitation_id = v_invitation.id and status = 'ACTIVE'
    returning id
  loop
    perform public.verified_access_write_audit_event(
      v_invitation.condominium_id, 'PUBLIC', null, 'PUBLIC_SESSION',
      v_revoked_session_id, 'VERIFIED_ACCESS_PUBLIC_SESSION_REVOKED',
      'SESSION_ROTATED', p_correlation_id,
      jsonb_build_object('invitation_id', v_invitation.id, 'request_id', v_request.id)
    );
    perform public.verified_access_enqueue_outbox_event(
      v_invitation.condominium_id, 'PUBLIC_SESSION', v_revoked_session_id,
      'VERIFIED_ACCESS_PUBLIC_SESSION_REVOKED',
      'verified-access:public-session:' || v_revoked_session_id || ':rotated',
      jsonb_build_object(
        'condominium_id', v_invitation.condominium_id,
        'request_id', v_request.id,
        'invitation_id', v_invitation.id,
        'session_id', v_revoked_session_id,
        'status', 'REVOKED',
        'event_code', 'VERIFIED_ACCESS_PUBLIC_SESSION_REVOKED'
      )
    );
  end loop;

  insert into public.verified_access_public_sessions (
    condominium_id, request_id, invitation_id, participant_slot_id,
    session_token_hash, token_version, status, expires_at, last_seen_at
  ) values (
    v_invitation.condominium_id, v_request.id, v_invitation.id,
    v_invitation.participant_slot_id, p_session_token_hash, 1, 'ACTIVE',
    least(now() + interval '30 minutes', v_invitation.expires_at), now()
  ) returning * into v_session;

  update public.verified_access_invitations
     set status = 'OPENED', updated_at = now()
   where id = v_invitation.id and status in ('PENDING', 'SENT');

  select c.name into v_condominium_name
  from public.condominiums c where c.id = v_invitation.condominium_id;

  perform public.verified_access_write_audit_event(
    v_invitation.condominium_id, 'PUBLIC', null, 'PUBLIC_SESSION', v_session.id,
    'VERIFIED_ACCESS_PUBLIC_SESSION_CREATED', 'INVITATION_EXCHANGED',
    p_correlation_id,
    jsonb_build_object('invitation_id', v_invitation.id, 'request_id', v_request.id)
  );
  perform public.verified_access_enqueue_outbox_event(
    v_invitation.condominium_id, 'PUBLIC_SESSION', v_session.id,
    'VERIFIED_ACCESS_PUBLIC_SESSION_CREATED',
    'verified-access:command:' || v_command.id || ':session-created',
    jsonb_build_object(
      'condominium_id', v_invitation.condominium_id,
      'request_id', v_request.id,
      'invitation_id', v_invitation.id,
      'session_id', v_session.id,
      'status', 'ACTIVE',
      'expires_at', v_session.expires_at,
      'event_code', 'VERIFIED_ACCESS_PUBLIC_SESSION_CREATED'
    )
  );

  v_result := jsonb_build_object(
    'sessionId', v_session.id,
    'sessionStatus', 'ACTIVE',
    'requestType', v_request.request_type,
    'startsAt', v_request.starts_at,
    'endsAt', v_request.ends_at,
    'timezone', v_request.timezone,
    'condominiumName', v_condominium_name
  );

  update public.verified_access_public_registration_commands
     set session_id = v_session.id, status = 'COMPLETED',
         result_code = 'PUBLIC_SESSION_CREATED', result_payload = v_result,
         completed_at = now()
   where id = v_command.id;

  return v_result;
end;
$$;

create or replace function public.verified_access_public_get_registration(
  p_session_token_hash text,
  p_rate_fingerprint text,
  p_correlation_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_session public.verified_access_public_sessions%rowtype;
  v_request public.verified_access_requests%rowtype;
  v_invitation public.verified_access_invitations%rowtype;
  v_condominium_name text;
begin
  perform public.verified_access_phase3b_assert_hash(p_session_token_hash, 'PUBLIC_ACCESS_UNAVAILABLE');
  perform public.verified_access_phase3b_assert_hash(p_rate_fingerprint, 'PUBLIC_RATE_FINGERPRINT_INVALID');
  if p_correlation_id is null or char_length(trim(p_correlation_id)) not between 8 and 128 then
    raise exception 'PUBLIC_REGISTRATION_PAYLOAD_INVALID' using errcode = '22023';
  end if;
  if public.verified_access_phase3b_rate_limit('SESSION_GET', p_rate_fingerprint, 60, interval '5 minutes') > 60 then
    return jsonb_build_object('rateLimited', true, 'retryAfterSeconds', 300, 'resultCode', 'RATE_LIMITED');
  end if;

  select s.* into v_session
  from public.verified_access_public_sessions s
  where s.session_token_hash = p_session_token_hash
  for update;

  if v_session.id is null then return jsonb_build_object('resultCode', 'PUBLIC_ACCESS_UNAVAILABLE'); end if;
  if v_session.status = 'ACTIVE' and v_session.expires_at <= now() then
    update public.verified_access_public_sessions
       set status = 'EXPIRED', updated_at = now()
     where id = v_session.id;
    return jsonb_build_object('resultCode', 'PUBLIC_ACCESS_UNAVAILABLE');
  end if;
  if v_session.status <> 'ACTIVE' then return jsonb_build_object('resultCode', 'PUBLIC_ACCESS_UNAVAILABLE'); end if;

  select i.* into v_invitation from public.verified_access_invitations i where i.id = v_session.invitation_id;
  select r.* into v_request from public.verified_access_requests r where r.id = v_session.request_id;
  if v_invitation.expires_at <= now() then
    update public.verified_access_public_sessions set status='EXPIRED', updated_at=now() where id=v_session.id;
    update public.verified_access_invitations set status='EXPIRED', updated_at=now() where id=v_invitation.id and status='OPENED';
    return jsonb_build_object('resultCode', 'PUBLIC_ACCESS_UNAVAILABLE');
  end if;
  if v_invitation.status in ('REVOKED', 'EXPIRED', 'COMPLETED')
     or v_request.status not in ('INVITATIONS_PENDING', 'IN_PROGRESS') then
    update public.verified_access_public_sessions set status='REVOKED', revoked_at=now(), updated_at=now() where id=v_session.id;
    return jsonb_build_object('resultCode', 'PUBLIC_ACCESS_UNAVAILABLE');
  end if;

  update public.verified_access_public_sessions set last_seen_at=now(), updated_at=now() where id=v_session.id;
  select c.name into v_condominium_name from public.condominiums c where c.id=v_session.condominium_id;
  return jsonb_build_object(
    'sessionId', v_session.id, 'sessionStatus', 'ACTIVE',
    'requestType', v_request.request_type, 'startsAt', v_request.starts_at,
    'endsAt', v_request.ends_at, 'timezone', v_request.timezone,
    'condominiumName', v_condominium_name,
    'tenantScope', v_session.condominium_id
  );
end;
$$;

create or replace function public.verified_access_public_start_registration(
  p_session_token_hash text,
  p_idempotency_key text,
  p_input_fingerprint text,
  p_rate_fingerprint text,
  p_correlation_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_session public.verified_access_public_sessions%rowtype;
  v_command public.verified_access_public_registration_commands%rowtype;
  v_result jsonb;
begin
  perform public.verified_access_phase3b_assert_hash(p_session_token_hash, 'PUBLIC_ACCESS_UNAVAILABLE');
  perform public.verified_access_phase3b_assert_hash(p_input_fingerprint, 'PUBLIC_INPUT_FINGERPRINT_INVALID');
  perform public.verified_access_phase3b_assert_hash(p_rate_fingerprint, 'PUBLIC_RATE_FINGERPRINT_INVALID');
  perform public.verified_access_phase3b_assert_command_input(p_idempotency_key, p_correlation_id);
  if public.verified_access_phase3b_rate_limit('SESSION_START', p_rate_fingerprint, 5, interval '10 minutes') > 5 then
    return jsonb_build_object('rateLimited', true, 'retryAfterSeconds', 600, 'resultCode', 'RATE_LIMITED');
  end if;
  select s.* into v_session from public.verified_access_public_sessions s
  where s.session_token_hash=p_session_token_hash for update;
  if v_session.id is null or v_session.status <> 'ACTIVE' or v_session.expires_at <= now() then
    return jsonb_build_object('resultCode', 'PUBLIC_ACCESS_UNAVAILABLE');
  end if;
  select c.* into v_command from public.verified_access_public_registration_commands c
  where c.invitation_id=v_session.invitation_id and c.command_type='START'
    and c.idempotency_key=p_idempotency_key for update;
  if v_command.id is not null then
    if v_command.input_fingerprint <> p_input_fingerprint then raise exception 'IDEMPOTENCY_CONFLICT' using errcode='P0001'; end if;
    if v_command.status='PROCESSING' then raise exception 'COMMAND_IN_PROGRESS' using errcode='P0001'; end if;
    return v_command.result_payload;
  end if;
  insert into public.verified_access_public_registration_commands(
    condominium_id, invitation_id, session_id, command_type, idempotency_key, input_fingerprint
  ) values (
    v_session.condominium_id, v_session.invitation_id, v_session.id, 'START', p_idempotency_key, p_input_fingerprint
  ) returning * into v_command;
  update public.verified_access_public_sessions
     set started_at=coalesce(started_at,now()), last_seen_at=now(), updated_at=now()
   where id=v_session.id returning * into v_session;
  perform public.verified_access_write_audit_event(
    v_session.condominium_id,'PUBLIC',null,'PUBLIC_SESSION',v_session.id,
    'VERIFIED_ACCESS_REGISTRATION_STARTED','PUBLIC_REGISTRATION_STARTED',p_correlation_id,
    jsonb_build_object('invitation_id',v_session.invitation_id,'request_id',v_session.request_id)
  );
  perform public.verified_access_enqueue_outbox_event(
    v_session.condominium_id,'PUBLIC_SESSION',v_session.id,
    'VERIFIED_ACCESS_REGISTRATION_STARTED',
    'verified-access:command:'||v_command.id||':registration-started',
    jsonb_build_object(
      'condominium_id',v_session.condominium_id,'request_id',v_session.request_id,
      'invitation_id',v_session.invitation_id,'session_id',v_session.id,
      'status','ACTIVE','started_at',v_session.started_at,
      'event_code','VERIFIED_ACCESS_REGISTRATION_STARTED'
    )
  );
  v_result:=jsonb_build_object('sessionId',v_session.id,'sessionStatus','ACTIVE','startedAt',v_session.started_at);
  update public.verified_access_public_registration_commands set status='COMPLETED',result_code='REGISTRATION_STARTED',result_payload=v_result,completed_at=now() where id=v_command.id;
  return v_result;
end;
$$;

create or replace function public.verified_access_public_submit_registration(
  p_session_token_hash text,
  p_idempotency_key text,
  p_input_fingerprint text,
  p_rate_fingerprint text,
  p_document_rate_fingerprint text,
  p_full_name_ciphertext bytea,
  p_birth_date_ciphertext bytea,
  p_document_type text,
  p_cpf_ciphertext bytea,
  p_cpf_tenant_hmac text,
  p_document_number_ciphertext bytea,
  p_document_number_tenant_hmac text,
  p_document_issuer_country_ciphertext bytea,
  p_phone_ciphertext bytea,
  p_phone_tenant_hmac text,
  p_is_minor boolean,
  p_guardian_name_ciphertext bytea,
  p_guardian_relationship_ciphertext bytea,
  p_privacy_notice_version text,
  p_terms_version text,
  p_encryption_key_version integer,
  p_hmac_key_version integer,
  p_correlation_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_session public.verified_access_public_sessions%rowtype;
  v_invitation public.verified_access_invitations%rowtype;
  v_request public.verified_access_requests%rowtype;
  v_command public.verified_access_public_registration_commands%rowtype;
  v_profile_id uuid;
  v_participant_id uuid;
  v_submitted_at timestamptz := now();
  v_result jsonb;
begin
  perform public.verified_access_phase3b_assert_hash(p_session_token_hash,'PUBLIC_ACCESS_UNAVAILABLE');
  perform public.verified_access_phase3b_assert_hash(p_input_fingerprint,'PUBLIC_INPUT_FINGERPRINT_INVALID');
  perform public.verified_access_phase3b_assert_hash(p_rate_fingerprint,'PUBLIC_RATE_FINGERPRINT_INVALID');
  perform public.verified_access_phase3b_assert_hash(p_document_rate_fingerprint,'PUBLIC_RATE_FINGERPRINT_INVALID');
  perform public.verified_access_phase3b_assert_command_input(p_idempotency_key,p_correlation_id);
  if public.verified_access_phase3b_rate_limit('SESSION_SUBMIT',p_rate_fingerprint,5,interval '30 minutes') > 5 then
    return jsonb_build_object('rateLimited',true,'retryAfterSeconds',1800,'resultCode','RATE_LIMITED');
  end if;

  select s.* into v_session from public.verified_access_public_sessions s
  where s.session_token_hash=p_session_token_hash for update;
  if v_session.id is null then return jsonb_build_object('resultCode','PUBLIC_ACCESS_UNAVAILABLE'); end if;

  select c.* into v_command from public.verified_access_public_registration_commands c
  where c.invitation_id=v_session.invitation_id and c.command_type='SUBMIT'
    and c.idempotency_key=p_idempotency_key for update;
  if v_command.id is not null then
    if v_command.input_fingerprint<>p_input_fingerprint then raise exception 'IDEMPOTENCY_CONFLICT' using errcode='P0001'; end if;
    if v_command.status='PROCESSING' then raise exception 'COMMAND_IN_PROGRESS' using errcode='P0001'; end if;
    return v_command.result_payload;
  end if;

  if v_session.status<>'ACTIVE' or v_session.expires_at<=now() then return jsonb_build_object('resultCode','PUBLIC_ACCESS_UNAVAILABLE'); end if;
  select i.* into v_invitation from public.verified_access_invitations i where i.id=v_session.invitation_id for update;
  select r.* into v_request from public.verified_access_requests r where r.id=v_session.request_id for update;
  if v_invitation.status <> 'OPENED' or v_invitation.expires_at<=now()
     or v_request.status not in ('INVITATIONS_PENDING','IN_PROGRESS')
     or not exists(select 1 from public.verified_access_participant_slots s where s.id=v_session.participant_slot_id and s.request_id=v_request.id and s.condominium_id=v_session.condominium_id and s.status='OPEN') then
    return jsonb_build_object('resultCode','PUBLIC_ACCESS_UNAVAILABLE');
  end if;

  if p_full_name_ciphertext is null or octet_length(p_full_name_ciphertext) not between 16 and 4096
     or p_birth_date_ciphertext is null or octet_length(p_birth_date_ciphertext) not between 16 and 512
     or p_is_minor is null
     or coalesce(p_encryption_key_version <= 0, true)
     or coalesce(p_hmac_key_version <= 0, true)
     or coalesce(p_privacy_notice_version !~ '^[A-Za-z0-9._:-]{3,64}$', true)
     or coalesce(p_terms_version !~ '^[A-Za-z0-9._:-]{3,64}$', true)
     or ((p_phone_ciphertext is null) <> (p_phone_tenant_hmac is null))
     or (p_phone_ciphertext is not null and octet_length(p_phone_ciphertext) not between 16 and 1024)
     or (p_phone_tenant_hmac is not null and p_phone_tenant_hmac !~ '^v1:[0-9a-f]{64}$')
     or (p_is_minor and (
       p_guardian_name_ciphertext is null
       or octet_length(p_guardian_name_ciphertext) not between 16 and 4096
       or p_guardian_relationship_ciphertext is null
       or octet_length(p_guardian_relationship_ciphertext) not between 16 and 1024
     ))
     or (not p_is_minor and (p_guardian_name_ciphertext is not null or p_guardian_relationship_ciphertext is not null)) then
    raise exception 'PUBLIC_REGISTRATION_PAYLOAD_INVALID' using errcode='22023';
  end if;

  if p_document_type = 'CPF' then
    if p_cpf_ciphertext is null
       or octet_length(p_cpf_ciphertext) not between 16 and 1024
       or coalesce(p_cpf_tenant_hmac !~ '^v1:[0-9a-f]{64}$', true)
       or p_document_number_ciphertext is not null
       or p_document_number_tenant_hmac is not null
       or p_document_issuer_country_ciphertext is not null then
      raise exception 'PUBLIC_REGISTRATION_PAYLOAD_INVALID' using errcode='22023';
    end if;
  elsif p_document_type = 'RNM' then
    if p_cpf_ciphertext is not null
       or p_cpf_tenant_hmac is not null
       or p_document_number_ciphertext is null
       or octet_length(p_document_number_ciphertext) not between 16 and 1024
       or coalesce(p_document_number_tenant_hmac !~ '^v1:[0-9a-f]{64}$', true)
       or p_document_issuer_country_ciphertext is not null then
      raise exception 'PUBLIC_REGISTRATION_PAYLOAD_INVALID' using errcode='22023';
    end if;
  elsif p_document_type = 'PASSPORT' then
    if p_cpf_ciphertext is not null
       or p_cpf_tenant_hmac is not null
       or p_document_number_ciphertext is null
       or octet_length(p_document_number_ciphertext) not between 16 and 1024
       or coalesce(p_document_number_tenant_hmac !~ '^v1:[0-9a-f]{64}$', true)
       or p_document_issuer_country_ciphertext is null
       or octet_length(p_document_issuer_country_ciphertext) not between 16 and 512 then
      raise exception 'PUBLIC_REGISTRATION_PAYLOAD_INVALID' using errcode='22023';
    end if;
  elsif not (
    p_is_minor
    and p_document_type is null
    and p_cpf_ciphertext is null
    and p_cpf_tenant_hmac is null
    and p_document_number_ciphertext is null
    and p_document_number_tenant_hmac is null
    and p_document_issuer_country_ciphertext is null
  ) then
    raise exception 'PUBLIC_REGISTRATION_PAYLOAD_INVALID' using errcode='22023';
  end if;

  if public.verified_access_phase3b_rate_limit('DOCUMENT_DUPLICATE',p_document_rate_fingerprint,5,interval '24 hours',v_session.condominium_id)>5 then
    return jsonb_build_object('rateLimited',true,'retryAfterSeconds',86400,'resultCode','RATE_LIMITED');
  end if;

  insert into public.verified_access_public_registration_commands(
    condominium_id,invitation_id,session_id,command_type,idempotency_key,input_fingerprint
  ) values (
    v_session.condominium_id,v_session.invitation_id,v_session.id,'SUBMIT',p_idempotency_key,p_input_fingerprint
  ) returning * into v_command;

  begin
    insert into public.verified_access_identity_profiles(
      condominium_id,cpf_ciphertext,cpf_tenant_hmac,document_type,
      document_number_ciphertext,document_number_tenant_hmac,
      document_issuer_country_ciphertext,phone_ciphertext,phone_tenant_hmac,
      full_name_ciphertext,birth_date_ciphertext,encryption_key_version,
      hmac_key_version,identity_assurance_level,is_minor,
      guardian_name_ciphertext,guardian_relationship_ciphertext,
      privacy_notice_version,terms_version,acknowledged_at,submitted_at
    ) values (
      v_session.condominium_id,p_cpf_ciphertext,p_cpf_tenant_hmac,p_document_type,
      p_document_number_ciphertext,p_document_number_tenant_hmac,
      p_document_issuer_country_ciphertext,p_phone_ciphertext,p_phone_tenant_hmac,
      p_full_name_ciphertext,p_birth_date_ciphertext,p_encryption_key_version,
      p_hmac_key_version,'SELF_DECLARED',p_is_minor,
      p_guardian_name_ciphertext,p_guardian_relationship_ciphertext,
      p_privacy_notice_version,p_terms_version,v_submitted_at,v_submitted_at
    ) returning id into v_profile_id;
  exception when unique_violation then
    v_result:=jsonb_build_object('resultCode','REGISTRATION_UNAVAILABLE');
    update public.verified_access_public_registration_commands set status='COMPLETED',result_code='REGISTRATION_UNAVAILABLE',result_payload=v_result,completed_at=now() where id=v_command.id;
    return v_result;
  end;

  insert into public.verified_access_participants(
    condominium_id,request_id,slot_id,identity_profile_id,registration_status,
    identity_status,background_status,network_status,eligibility_status
  ) values (
    v_session.condominium_id,v_session.request_id,v_session.participant_slot_id,
    v_profile_id,'SUBMITTED','SELF_DECLARED','NOT_REQUIRED','NOT_ENABLED','PENDING'
  ) returning id into v_participant_id;

  update public.verified_access_participant_slots
     set status='CLAIMED',claimed_at=v_submitted_at,updated_at=v_submitted_at
   where id=v_session.participant_slot_id and status='OPEN';
  if not found then raise exception 'PUBLIC_ACCESS_UNAVAILABLE' using errcode='P0001'; end if;

  update public.verified_access_public_sessions
     set status='COMPLETED',completed_at=v_submitted_at,last_seen_at=v_submitted_at,updated_at=v_submitted_at
   where id=v_session.id;
  update public.verified_access_invitations
     set status='COMPLETED',consumed_at=v_submitted_at,updated_at=v_submitted_at
   where id=v_invitation.id;

  perform public.verified_access_write_audit_event(v_session.condominium_id,'PUBLIC',null,'PUBLIC_SESSION',v_session.id,'VERIFIED_ACCESS_REGISTRATION_SUBMITTED','REGISTRATION_SUBMITTED',p_correlation_id,jsonb_build_object('request_id',v_session.request_id,'invitation_id',v_session.invitation_id,'participant_id',v_participant_id));
  perform public.verified_access_write_audit_event(v_session.condominium_id,'PUBLIC',null,'PARTICIPANT',v_participant_id,'VERIFIED_ACCESS_PARTICIPANT_CREATED','PUBLIC_REGISTRATION',p_correlation_id,jsonb_build_object('request_id',v_session.request_id,'invitation_id',v_session.invitation_id,'session_id',v_session.id));
  perform public.verified_access_write_audit_event(v_session.condominium_id,'PUBLIC',null,'INVITATION',v_invitation.id,'VERIFIED_ACCESS_INVITATION_COMPLETED','REGISTRATION_SUBMITTED',p_correlation_id,jsonb_build_object('request_id',v_session.request_id,'participant_id',v_participant_id,'session_id',v_session.id));

  perform public.verified_access_enqueue_outbox_event(v_session.condominium_id,'PUBLIC_SESSION',v_session.id,'VERIFIED_ACCESS_REGISTRATION_SUBMITTED','verified-access:command:'||v_command.id||':registration-submitted',jsonb_build_object('condominium_id',v_session.condominium_id,'request_id',v_session.request_id,'invitation_id',v_invitation.id,'session_id',v_session.id,'participant_id',v_participant_id,'status','COMPLETED','submitted_at',v_submitted_at,'event_code','VERIFIED_ACCESS_REGISTRATION_SUBMITTED'));
  perform public.verified_access_enqueue_outbox_event(v_session.condominium_id,'PARTICIPANT',v_participant_id,'VERIFIED_ACCESS_PARTICIPANT_CREATED','verified-access:command:'||v_command.id||':participant-created',jsonb_build_object('condominium_id',v_session.condominium_id,'request_id',v_session.request_id,'invitation_id',v_invitation.id,'session_id',v_session.id,'participant_id',v_participant_id,'status','SUBMITTED','event_code','VERIFIED_ACCESS_PARTICIPANT_CREATED'));
  perform public.verified_access_enqueue_outbox_event(v_session.condominium_id,'INVITATION',v_invitation.id,'VERIFIED_ACCESS_INVITATION_COMPLETED','verified-access:command:'||v_command.id||':invitation-completed',jsonb_build_object('condominium_id',v_session.condominium_id,'request_id',v_session.request_id,'invitation_id',v_invitation.id,'session_id',v_session.id,'participant_id',v_participant_id,'status','COMPLETED','event_code','VERIFIED_ACCESS_INVITATION_COMPLETED'));

  v_result:=jsonb_build_object('sessionId',v_session.id,'sessionStatus','COMPLETED','registrationStatus','SUBMITTED','invitationStatus','COMPLETED','submittedAt',v_submitted_at);
  update public.verified_access_public_registration_commands set status='COMPLETED',result_code='REGISTRATION_SUBMITTED',result_payload=v_result,completed_at=now() where id=v_command.id;
  return v_result;
end;
$$;

create or replace function public.verified_access_public_registration_status(
  p_session_token_hash text,
  p_rate_fingerprint text,
  p_correlation_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_session public.verified_access_public_sessions%rowtype;
begin
  perform public.verified_access_phase3b_assert_hash(p_session_token_hash,'PUBLIC_ACCESS_UNAVAILABLE');
  perform public.verified_access_phase3b_assert_hash(p_rate_fingerprint,'PUBLIC_RATE_FINGERPRINT_INVALID');
  if p_correlation_id is null or char_length(trim(p_correlation_id)) not between 8 and 128 then raise exception 'PUBLIC_REGISTRATION_PAYLOAD_INVALID' using errcode='22023'; end if;
  if public.verified_access_phase3b_rate_limit('SESSION_GET',p_rate_fingerprint,60,interval '5 minutes')>60 then return jsonb_build_object('rateLimited',true,'retryAfterSeconds',300,'resultCode','RATE_LIMITED'); end if;
  select s.* into v_session from public.verified_access_public_sessions s where s.session_token_hash=p_session_token_hash for update;
  if v_session.id is null or v_session.status in ('REVOKED','EXPIRED') then return jsonb_build_object('resultCode','PUBLIC_ACCESS_UNAVAILABLE'); end if;
  if v_session.status='ACTIVE' and v_session.expires_at<=now() then update public.verified_access_public_sessions set status='EXPIRED',updated_at=now() where id=v_session.id; return jsonb_build_object('resultCode','PUBLIC_ACCESS_UNAVAILABLE'); end if;
  return jsonb_build_object('sessionStatus',v_session.status,'registrationStatus',case when v_session.status='COMPLETED' then 'SUBMITTED' else 'IN_PROGRESS' end,'submittedAt',v_session.completed_at);
end;
$$;

alter function public.verified_access_resend_resident_invitation(uuid, text, text, text)
  rename to verified_access_resend_resident_invitation_phase3a;
alter function public.verified_access_revoke_resident_invitation(uuid, text, text, text)
  rename to verified_access_revoke_resident_invitation_phase3a;

revoke all on function public.verified_access_resend_resident_invitation_phase3a(uuid, text, text, text)
  from public, anon, authenticated, service_role;
revoke all on function public.verified_access_revoke_resident_invitation_phase3a(uuid, text, text, text)
  from public, anon, authenticated, service_role;
revoke execute on function public.verified_access_resend_resident_invitation_phase3a(uuid, text, text, text)
  from verified_access_phase3a_resident_executor;
revoke execute on function public.verified_access_revoke_resident_invitation_phase3a(uuid, text, text, text)
  from verified_access_phase3a_resident_executor;

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
declare v_result jsonb;
begin
  update public.verified_access_invitations
     set status = 'SENT', updated_at = now()
   where id = p_invitation_id and status = 'OPENED';
  select public.verified_access_resend_resident_invitation_phase3a(
    p_invitation_id, p_token_hash, p_idempotency_key, p_correlation_id
  ) into v_result;
  return v_result;
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
declare v_result jsonb;
begin
  update public.verified_access_invitations
     set status = 'SENT', updated_at = now()
   where id = p_invitation_id and status = 'OPENED';
  select public.verified_access_revoke_resident_invitation_phase3a(
    p_invitation_id, p_idempotency_key, p_reason_code, p_correlation_id
  ) into v_result;
  return v_result;
end;
$$;

revoke all on function public.verified_access_resend_resident_invitation(uuid, text, text, text)
  from public, anon, authenticated, service_role;
revoke all on function public.verified_access_revoke_resident_invitation(uuid, text, text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.verified_access_resend_resident_invitation(uuid, text, text, text)
  to verified_access_phase3a_resident_executor;
grant execute on function public.verified_access_revoke_resident_invitation(uuid, text, text, text)
  to verified_access_phase3a_resident_executor;

do $$
begin
  if not exists(select 1 from pg_roles where rolname='verified_access_phase3b_public_executor') then
    create role verified_access_phase3b_public_executor nologin;
  end if;
end $$;

revoke all on function public.verified_access_public_exchange_invitation(text,text,text,text,text,text,text) from public, anon, authenticated, service_role;
revoke all on function public.verified_access_public_get_registration(text,text,text) from public, anon, authenticated, service_role;
revoke all on function public.verified_access_public_start_registration(text,text,text,text,text) from public, anon, authenticated, service_role;
revoke all on function public.verified_access_public_submit_registration(text,text,text,text,text,bytea,bytea,text,bytea,text,bytea,text,bytea,bytea,text,boolean,bytea,bytea,text,text,integer,integer,text) from public, anon, authenticated, service_role;
revoke all on function public.verified_access_public_registration_status(text,text,text) from public, anon, authenticated, service_role;

grant execute on function public.verified_access_public_exchange_invitation(text,text,text,text,text,text,text) to verified_access_phase3b_public_executor;
grant execute on function public.verified_access_public_get_registration(text,text,text) to verified_access_phase3b_public_executor;
grant execute on function public.verified_access_public_start_registration(text,text,text,text,text) to verified_access_phase3b_public_executor;
grant execute on function public.verified_access_public_submit_registration(text,text,text,text,text,bytea,bytea,text,bytea,text,bytea,text,bytea,bytea,text,boolean,bytea,bytea,text,text,integer,integer,text) to verified_access_phase3b_public_executor;
grant execute on function public.verified_access_public_registration_status(text,text,text) to verified_access_phase3b_public_executor;
grant verified_access_phase3b_public_executor to service_role;

revoke execute on function public.verified_access_phase3b_assert_hash(text,text) from public,anon,authenticated,service_role;
revoke execute on function public.verified_access_phase3b_assert_command_input(text,text) from public,anon,authenticated,service_role;
revoke execute on function public.verified_access_phase3b_rate_limit(text,text,integer,interval,uuid) from public,anon,authenticated,service_role;
revoke execute on function public.verified_access_phase3b_validate_session_transition() from public,anon,authenticated,service_role;
revoke execute on function public.verified_access_phase3b_invalidate_sessions_for_invitation() from public,anon,authenticated,service_role;

comment on function public.verified_access_public_submit_registration(text,text,text,text,text,bytea,bytea,text,bytea,text,bytea,text,bytea,bytea,text,boolean,bytea,bytea,text,text,integer,integer,text) is
  'Phase 3B atomic public registration. Accepts only application-encrypted values and keyed fingerprints.';
