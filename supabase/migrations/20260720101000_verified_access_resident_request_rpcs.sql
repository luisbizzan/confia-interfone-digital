create or replace function public.verified_access_phase2_context()
returns table (actor_user_id uuid, condominium_id uuid)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor_user_id uuid := auth.uid();
  v_condominium_id uuid;
begin
  if v_actor_user_id is null then
    raise exception 'AUTHENTICATION_REQUIRED' using errcode = '28000';
  end if;

  v_condominium_id := public.current_user_condominium_id();
  if v_condominium_id is null then
    raise exception 'AUTHENTICATION_REQUIRED' using errcode = '28000';
  end if;

  return query select v_actor_user_id, v_condominium_id;
end;
$$;

create or replace function public.verified_access_phase2_assert_feature(
  p_condominium_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.condominium_feature_enabled(p_condominium_id, 'VERIFIED_ACCESS') then
    raise exception 'FEATURE_DISABLED' using errcode = 'P0001';
  end if;
end;
$$;

create or replace function public.verified_access_phase2_assert_resident_unit(
  p_actor_user_id uuid,
  p_condominium_id uuid,
  p_unit_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not exists (
    select 1
    from public.unit_members um
    join public.units u
      on u.id = um.unit_id
     and u.condominium_id = um.condominium_id
    where um.user_id = p_actor_user_id
      and um.member_type = 'RESIDENT'
      and um.unit_id = p_unit_id
      and um.condominium_id = p_condominium_id
  ) then
    raise exception 'UNIT_NOT_AUTHORIZED' using errcode = 'P0001';
  end if;
end;
$$;

create or replace function public.verified_access_phase2_normalize_text(
  p_value text,
  p_max_length integer
)
returns text
language plpgsql
immutable
security invoker
set search_path = public, pg_temp
as $$
declare
  v_value text;
begin
  if p_value is null then
    return null;
  end if;

  if p_value ~ '[[:cntrl:]]' then
    raise exception 'REQUEST_PAYLOAD_INVALID' using errcode = '22023';
  end if;

  v_value := nullif(trim(regexp_replace(replace(p_value, chr(13) || chr(10), chr(10)), E'[\t ]+', ' ', 'g')), '');
  if v_value is not null and char_length(v_value) > p_max_length then
    raise exception 'REQUEST_PAYLOAD_INVALID' using errcode = '22023';
  end if;

  return v_value;
end;
$$;

create or replace function public.verified_access_phase2_fingerprint(
  p_payload jsonb
)
returns text
language sql
immutable
security invoker
set search_path = public, pg_temp
as $$
  select 'v1:' || encode(
    extensions.digest(convert_to(p_payload::text, 'UTF8'), 'sha256'),
    'hex'
  )
$$;

create or replace function public.verified_access_list_resident_service_types(
  p_unit_id uuid
)
returns table (
  id uuid,
  code text,
  display_name text,
  requires_description boolean
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor_user_id uuid;
  v_condominium_id uuid;
begin
  select c.actor_user_id, c.condominium_id
    into v_actor_user_id, v_condominium_id
  from public.verified_access_phase2_context() c;

  perform public.verified_access_phase2_assert_feature(v_condominium_id);
  perform public.verified_access_phase2_assert_resident_unit(v_actor_user_id, v_condominium_id, p_unit_id);

  if not exists (
    select 1 from public.verified_access_policies p
    where p.condominium_id = v_condominium_id and p.status = 'ACTIVE'
  ) then
    raise exception 'POLICY_NOT_AVAILABLE' using errcode = 'P0001';
  end if;

  return query
  select
    st.id,
    st.code,
    coalesce(cst.display_name_override, st.default_name) as display_name,
    st.requires_description
  from public.verified_access_service_types st
  join public.verified_access_condominium_service_types cst
    on cst.service_type_id = st.id
   and cst.condominium_id = v_condominium_id
   and cst.is_enabled is true
  where st.is_active is true
  order by st.sort_order, st.code;
end;
$$;

create or replace function public.verified_access_create_resident_request(
  p_unit_id uuid,
  p_request_type text,
  p_service_type_code text,
  p_service_description text,
  p_access_starts_at timestamptz,
  p_access_ends_at timestamptz,
  p_purpose text,
  p_operational_note text,
  p_participant_slots integer,
  p_client_request_id text,
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
  v_policy public.verified_access_policies%rowtype;
  v_request_type text := upper(trim(coalesce(p_request_type, '')));
  v_service_type_code text := nullif(upper(trim(coalesce(p_service_type_code, ''))), '');
  v_service_description text := public.verified_access_phase2_normalize_text(p_service_description, 300);
  v_purpose text := public.verified_access_phase2_normalize_text(p_purpose, 300);
  v_operational_note text := public.verified_access_phase2_normalize_text(p_operational_note, 1000);
  v_service_type_id uuid;
  v_requires_description boolean;
  v_max_participants integer;
  v_fingerprint text;
  v_command public.verified_access_request_commands%rowtype;
  v_request_id uuid;
  v_result jsonb;
begin
  select c.actor_user_id, c.condominium_id
    into v_actor_user_id, v_condominium_id
  from public.verified_access_phase2_context() c;

  perform public.verified_access_phase2_assert_feature(v_condominium_id);
  perform public.verified_access_phase2_assert_resident_unit(v_actor_user_id, v_condominium_id, p_unit_id);

  select p.* into v_policy
  from public.verified_access_policies p
  where p.condominium_id = v_condominium_id and p.status = 'ACTIVE'
  for share;

  if not found then
    raise exception 'POLICY_NOT_AVAILABLE' using errcode = 'P0001';
  end if;

  if v_request_type not in ('VISITOR', 'SERVICE_PROVIDER') then
    raise exception 'REQUEST_PAYLOAD_INVALID' using errcode = '22023';
  end if;

  if p_client_request_id is null
     or p_client_request_id <> trim(p_client_request_id)
     or char_length(p_client_request_id) not between 16 and 128
     or p_client_request_id ~ '[[:cntrl:]]'
     or p_correlation_id is null
     or char_length(trim(p_correlation_id)) not between 8 and 128
     or p_correlation_id ~ '[[:cntrl:]]' then
    raise exception 'REQUEST_PAYLOAD_INVALID' using errcode = '22023';
  end if;

  if p_access_starts_at is null or p_access_ends_at is null
     or p_access_starts_at >= p_access_ends_at
     or p_access_starts_at < now() + make_interval(mins => v_policy.min_notice_minutes)
     or p_access_starts_at > now() + make_interval(days => v_policy.max_notice_days)
     or p_access_ends_at - p_access_starts_at > make_interval(mins => v_policy.max_request_duration_minutes) then
    raise exception 'ACCESS_WINDOW_INVALID' using errcode = 'P0001';
  end if;

  v_max_participants := case v_request_type
    when 'VISITOR' then v_policy.max_visitor_participants
    else v_policy.max_service_participants
  end;

  if p_participant_slots is null or p_participant_slots < 1 or p_participant_slots > v_max_participants then
    raise exception 'PARTICIPANT_LIMIT_INVALID' using errcode = 'P0001';
  end if;

  if v_request_type = 'VISITOR' then
    if v_service_type_code is not null or v_service_description is not null then
      raise exception 'SERVICE_TYPE_NOT_AVAILABLE' using errcode = 'P0001';
    end if;
  else
    if v_service_type_code is null then
      raise exception 'SERVICE_TYPE_NOT_AVAILABLE' using errcode = 'P0001';
    end if;

    select st.id, st.requires_description
      into v_service_type_id, v_requires_description
    from public.verified_access_service_types st
    join public.verified_access_condominium_service_types cst
      on cst.service_type_id = st.id
     and cst.condominium_id = v_condominium_id
     and cst.is_enabled is true
    where st.code = v_service_type_code
      and st.is_active is true;

    if v_service_type_id is null
       or (v_requires_description and v_service_description is null)
       or (not v_requires_description and v_service_description is not null) then
      raise exception 'SERVICE_TYPE_NOT_AVAILABLE' using errcode = 'P0001';
    end if;
  end if;

  v_fingerprint := public.verified_access_phase2_fingerprint(jsonb_build_object(
    'accessEndsAt', to_char(p_access_ends_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'accessStartsAt', to_char(p_access_starts_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'operationalNote', v_operational_note,
    'participantSlots', p_participant_slots,
    'purpose', v_purpose,
    'requestType', v_request_type,
    'serviceDescription', v_service_description,
    'serviceTypeCode', v_service_type_code,
    'unitId', p_unit_id
  ));

  insert into public.verified_access_request_commands (
    condominium_id, actor_user_id, command_type, idempotency_key,
    input_fingerprint, status
  ) values (
    v_condominium_id, v_actor_user_id, 'CREATE_REQUEST', p_client_request_id,
    v_fingerprint, 'PROCESSING'
  )
  on conflict (condominium_id, actor_user_id, command_type, idempotency_key) do nothing
  returning * into v_command;

  if v_command.id is null then
    select c.* into v_command
    from public.verified_access_request_commands c
    where c.condominium_id = v_condominium_id
      and c.actor_user_id = v_actor_user_id
      and c.command_type = 'CREATE_REQUEST'
      and c.idempotency_key = p_client_request_id
    for update;

    if v_command.input_fingerprint <> v_fingerprint then
      raise exception 'IDEMPOTENCY_CONFLICT' using errcode = 'P0001';
    end if;
    if v_command.status = 'PROCESSING' then
      raise exception 'COMMAND_IN_PROGRESS' using errcode = 'P0001';
    end if;
    return v_command.result_payload;
  end if;

  insert into public.verified_access_requests (
    condominium_id, unit_id, requested_by_user_id, request_type, status,
    starts_at, ends_at, timezone, participant_limit, policy_id, policy_version,
    created_by_actor_type, created_by_actor_id, operational_notes, visit_reason
  ) values (
    v_condominium_id, p_unit_id, v_actor_user_id, v_request_type, 'DRAFT',
    p_access_starts_at, p_access_ends_at, v_policy.timezone, p_participant_slots,
    v_policy.id, v_policy.version, 'USER', v_actor_user_id::text,
    v_operational_note, v_purpose
  ) returning id into v_request_id;

  if v_request_type = 'SERVICE_PROVIDER' then
    insert into public.verified_access_service_request_details (
      request_id, condominium_id, service_type_id, other_description
    ) values (
      v_request_id, v_condominium_id, v_service_type_id, v_service_description
    );
  end if;

  insert into public.verified_access_participant_slots (
    condominium_id, request_id, slot_number, status
  )
  select v_condominium_id, v_request_id, slot_number, 'OPEN'
  from generate_series(1, p_participant_slots) slot_number;

  insert into public.verified_access_audit_events (
    condominium_id, aggregate_type, aggregate_id, event_type, actor_user_id,
    actor_type, reason_code, correlation_id, metadata
  ) values (
    v_condominium_id, 'REQUEST', v_request_id,
    'VERIFIED_ACCESS_REQUEST_CREATED', v_actor_user_id, 'USER',
    'REQUEST_CREATED', p_correlation_id,
    jsonb_build_object(
      'request_type', v_request_type,
      'participant_limit', p_participant_slots,
      'policy_version', v_policy.version,
      'command_id', v_command.id
    )
  );

  insert into public.verified_access_outbox_events (
    condominium_id, aggregate_type, aggregate_id, event_type,
    deduplication_key, payload
  ) values (
    v_condominium_id, 'REQUEST', v_request_id,
    'VERIFIED_ACCESS_REQUEST_CREATED',
    'verified-access:command:' || v_command.id || ':request-created:v1',
    jsonb_build_object(
      'request_id', v_request_id,
      'condominium_id', v_condominium_id,
      'unit_id', p_unit_id,
      'request_type', v_request_type,
      'participant_limit', p_participant_slots,
      'access_starts_at', p_access_starts_at,
      'access_ends_at', p_access_ends_at,
      'event_code', 'VERIFIED_ACCESS_REQUEST_CREATED'
    )
  );

  v_result := jsonb_build_object(
    'requestId', v_request_id,
    'requestStatus', 'DRAFT',
    'participantLimit', p_participant_slots
  );

  update public.verified_access_request_commands
  set request_id = v_request_id,
      status = 'COMPLETED',
      result_code = 'REQUEST_CREATED',
      result_payload = v_result,
      completed_at = now()
  where id = v_command.id;

  return v_result;
end;
$$;

create or replace function public.verified_access_list_resident_requests(
  p_status text default null,
  p_request_type text default null,
  p_from timestamptz default null,
  p_to timestamptz default null,
  p_cursor_created_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 20
)
returns table (
  id uuid,
  request_type text,
  status text,
  unit_id uuid,
  starts_at timestamptz,
  ends_at timestamptz,
  timezone text,
  participant_limit integer,
  slot_counts jsonb,
  service jsonb,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor_user_id uuid;
  v_condominium_id uuid;
  v_status text := nullif(upper(trim(coalesce(p_status, ''))), '');
  v_request_type text := nullif(upper(trim(coalesce(p_request_type, ''))), '');
begin
  select c.actor_user_id, c.condominium_id
    into v_actor_user_id, v_condominium_id
  from public.verified_access_phase2_context() c;
  perform public.verified_access_phase2_assert_feature(v_condominium_id);

  if p_limit is null or p_limit < 1 or p_limit > 50
     or ((p_cursor_created_at is null) <> (p_cursor_id is null))
     or (p_from is not null and p_to is not null and p_from > p_to)
     or (v_request_type is not null and v_request_type not in ('VISITOR', 'SERVICE_PROVIDER'))
     or (v_status is not null and v_status not in (
       'DRAFT', 'INVITATIONS_PENDING', 'IN_PROGRESS', 'PARTIALLY_ELIGIBLE',
       'ELIGIBLE', 'COMPLETED', 'CANCELLED', 'EXPIRED'
     )) then
    raise exception 'REQUEST_PAYLOAD_INVALID' using errcode = '22023';
  end if;

  return query
  select
    r.id,
    r.request_type,
    r.status,
    r.unit_id,
    r.starts_at,
    r.ends_at,
    r.timezone,
    r.participant_limit,
    jsonb_build_object(
      'open', count(*) filter (where s.status = 'OPEN'),
      'reserved', count(*) filter (where s.status = 'RESERVED'),
      'claimed', count(*) filter (where s.status = 'CLAIMED'),
      'cancelled', count(*) filter (where s.status = 'CANCELLED'),
      'expired', count(*) filter (where s.status = 'EXPIRED')
    ) as slot_counts,
    case when d.request_id is null then null else jsonb_build_object(
      'typeCode', st.code,
      'displayName', coalesce(cst.display_name_override, st.default_name)
    ) end as service,
    r.created_at
  from public.verified_access_requests r
  join public.verified_access_participant_slots s
    on s.request_id = r.id and s.condominium_id = r.condominium_id
  left join public.verified_access_service_request_details d
    on d.request_id = r.id and d.condominium_id = r.condominium_id
  left join public.verified_access_service_types st on st.id = d.service_type_id
  left join public.verified_access_condominium_service_types cst
    on cst.condominium_id = r.condominium_id and cst.service_type_id = d.service_type_id
  where r.condominium_id = v_condominium_id
    and r.requested_by_user_id = v_actor_user_id
    and (v_status is null or r.status = v_status)
    and (v_request_type is null or r.request_type = v_request_type)
    and (p_from is null or r.starts_at >= p_from)
    and (p_to is null or r.starts_at <= p_to)
    and (p_cursor_created_at is null or (r.created_at, r.id) < (p_cursor_created_at, p_cursor_id))
  group by r.id, d.request_id, st.code, st.default_name, cst.display_name_override
  order by r.created_at desc, r.id desc
  limit p_limit;
end;
$$;

create or replace function public.verified_access_get_resident_request(
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor_user_id uuid;
  v_condominium_id uuid;
  v_result jsonb;
begin
  select c.actor_user_id, c.condominium_id
    into v_actor_user_id, v_condominium_id
  from public.verified_access_phase2_context() c;
  perform public.verified_access_phase2_assert_feature(v_condominium_id);

  select jsonb_build_object(
    'id', r.id,
    'requestType', r.request_type,
    'status', r.status,
    'unitId', r.unit_id,
    'accessStartsAt', r.starts_at,
    'accessEndsAt', r.ends_at,
    'timezone', r.timezone,
    'participantLimit', r.participant_limit,
    'service', case when d.request_id is null then null else jsonb_build_object(
      'typeCode', st.code,
      'displayName', coalesce(cst.display_name_override, st.default_name),
      'description', d.other_description
    ) end,
    'slots', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', s.id,
        'slotNumber', s.slot_number,
        'status', s.status
      ) order by s.slot_number)
      from public.verified_access_participant_slots s
      where s.request_id = r.id and s.condominium_id = r.condominium_id
    ), '[]'::jsonb),
    'createdAt', r.created_at
  ) into v_result
  from public.verified_access_requests r
  left join public.verified_access_service_request_details d
    on d.request_id = r.id and d.condominium_id = r.condominium_id
  left join public.verified_access_service_types st on st.id = d.service_type_id
  left join public.verified_access_condominium_service_types cst
    on cst.condominium_id = r.condominium_id and cst.service_type_id = d.service_type_id
  where r.id = p_request_id
    and r.condominium_id = v_condominium_id
    and r.requested_by_user_id = v_actor_user_id;

  if v_result is null then
    raise exception 'REQUEST_NOT_FOUND' using errcode = 'P0001';
  end if;
  return v_result;
end;
$$;

create or replace function public.verified_access_cancel_resident_request(
  p_request_id uuid,
  p_idempotency_key text,
  p_reason_code text default 'RESIDENT_CANCELLED',
  p_correlation_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor_user_id uuid;
  v_condominium_id uuid;
  v_policy_id uuid;
  v_reason_code text := upper(trim(coalesce(p_reason_code, '')));
  v_fingerprint text;
  v_command public.verified_access_request_commands%rowtype;
  v_request public.verified_access_requests%rowtype;
  v_result jsonb;
begin
  select c.actor_user_id, c.condominium_id
    into v_actor_user_id, v_condominium_id
  from public.verified_access_phase2_context() c;
  perform public.verified_access_phase2_assert_feature(v_condominium_id);

  select p.id into v_policy_id
  from public.verified_access_policies p
  where p.condominium_id = v_condominium_id and p.status = 'ACTIVE'
  for share;
  if v_policy_id is null then
    raise exception 'POLICY_NOT_AVAILABLE' using errcode = 'P0001';
  end if;

  if v_reason_code <> 'RESIDENT_CANCELLED' then
    raise exception 'REQUEST_PAYLOAD_INVALID' using errcode = '22023';
  end if;

  if p_idempotency_key is null
     or p_idempotency_key <> trim(p_idempotency_key)
     or char_length(p_idempotency_key) not between 16 and 128
     or p_idempotency_key ~ '[[:cntrl:]]'
     or p_correlation_id is null
     or char_length(trim(p_correlation_id)) not between 8 and 128
     or p_correlation_id ~ '[[:cntrl:]]' then
    raise exception 'REQUEST_PAYLOAD_INVALID' using errcode = '22023';
  end if;

  v_fingerprint := public.verified_access_phase2_fingerprint(jsonb_build_object(
    'reasonCode', v_reason_code,
    'requestId', p_request_id
  ));

  insert into public.verified_access_request_commands (
    condominium_id, actor_user_id, command_type, idempotency_key,
    input_fingerprint, status
  ) values (
    v_condominium_id, v_actor_user_id, 'CANCEL_REQUEST', p_idempotency_key,
    v_fingerprint, 'PROCESSING'
  )
  on conflict (condominium_id, actor_user_id, command_type, idempotency_key) do nothing
  returning * into v_command;

  if v_command.id is null then
    select c.* into v_command
    from public.verified_access_request_commands c
    where c.condominium_id = v_condominium_id
      and c.actor_user_id = v_actor_user_id
      and c.command_type = 'CANCEL_REQUEST'
      and c.idempotency_key = p_idempotency_key
    for update;
    if v_command.input_fingerprint <> v_fingerprint then
      raise exception 'IDEMPOTENCY_CONFLICT' using errcode = 'P0001';
    end if;
    if v_command.status = 'PROCESSING' then
      raise exception 'COMMAND_IN_PROGRESS' using errcode = 'P0001';
    end if;
    return v_command.result_payload;
  end if;

  select r.* into v_request
  from public.verified_access_requests r
  where r.id = p_request_id
    and r.condominium_id = v_condominium_id
    and r.requested_by_user_id = v_actor_user_id
  for update;

  if v_request.id is null then
    raise exception 'REQUEST_NOT_FOUND' using errcode = 'P0001';
  end if;
  if v_request.status <> 'DRAFT' or exists (
    select 1 from public.verified_access_participant_slots s
    where s.request_id = v_request.id
      and s.condominium_id = v_condominium_id
      and s.status <> 'OPEN'
  ) then
    raise exception 'REQUEST_STATE_CONFLICT' using errcode = 'P0001';
  end if;

  update public.verified_access_requests
  set status = 'CANCELLED', cancelled_at = now(), updated_at = now(), version = version + 1
  where id = v_request.id;

  update public.verified_access_participant_slots
  set status = 'CANCELLED', updated_at = now()
  where request_id = v_request.id and condominium_id = v_condominium_id and status = 'OPEN';

  insert into public.verified_access_audit_events (
    condominium_id, aggregate_type, aggregate_id, event_type, actor_user_id,
    actor_type, reason_code, correlation_id, metadata
  ) values (
    v_condominium_id, 'REQUEST', v_request.id,
    'VERIFIED_ACCESS_REQUEST_CANCELLED', v_actor_user_id, 'USER',
    v_reason_code, p_correlation_id,
    jsonb_build_object('command_id', v_command.id)
  );

  insert into public.verified_access_outbox_events (
    condominium_id, aggregate_type, aggregate_id, event_type,
    deduplication_key, payload
  ) values (
    v_condominium_id, 'REQUEST', v_request.id,
    'VERIFIED_ACCESS_REQUEST_CANCELLED',
    'verified-access:command:' || v_command.id || ':request-cancelled:v1',
    jsonb_build_object(
      'request_id', v_request.id,
      'condominium_id', v_condominium_id,
      'unit_id', v_request.unit_id,
      'request_type', v_request.request_type,
      'participant_limit', v_request.participant_limit,
      'access_starts_at', v_request.starts_at,
      'access_ends_at', v_request.ends_at,
      'event_code', 'VERIFIED_ACCESS_REQUEST_CANCELLED'
    )
  );

  v_result := jsonb_build_object('requestId', v_request.id, 'requestStatus', 'CANCELLED');
  update public.verified_access_request_commands
  set request_id = v_request.id,
      status = 'COMPLETED',
      result_code = 'REQUEST_CANCELLED',
      result_payload = v_result,
      completed_at = now()
  where id = v_command.id;

  return v_result;
end;
$$;

revoke execute on function public.verified_access_phase2_context() from public, anon, authenticated, service_role;
revoke execute on function public.verified_access_phase2_assert_feature(uuid) from public, anon, authenticated, service_role;
revoke execute on function public.verified_access_phase2_assert_resident_unit(uuid, uuid, uuid) from public, anon, authenticated, service_role;
revoke execute on function public.verified_access_phase2_normalize_text(text, integer) from public, anon, authenticated, service_role;
revoke execute on function public.verified_access_phase2_fingerprint(jsonb) from public, anon, authenticated, service_role;

revoke execute on function public.verified_access_list_resident_service_types(uuid) from public, anon, authenticated, service_role;
revoke execute on function public.verified_access_create_resident_request(uuid, text, text, text, timestamptz, timestamptz, text, text, integer, text, text) from public, anon, authenticated, service_role;
revoke execute on function public.verified_access_list_resident_requests(text, text, timestamptz, timestamptz, timestamptz, uuid, integer) from public, anon, authenticated, service_role;
revoke execute on function public.verified_access_get_resident_request(uuid) from public, anon, authenticated, service_role;
revoke execute on function public.verified_access_cancel_resident_request(uuid, text, text, text) from public, anon, authenticated, service_role;

do $$
begin
  if not exists (
    select 1 from pg_roles where rolname = 'verified_access_phase2_resident_executor'
  ) then
    create role verified_access_phase2_resident_executor nologin noinherit;
  end if;
end;
$$;

alter role verified_access_phase2_resident_executor nologin noinherit;

grant execute on function public.verified_access_list_resident_service_types(uuid)
  to verified_access_phase2_resident_executor;
grant execute on function public.verified_access_create_resident_request(uuid, text, text, text, timestamptz, timestamptz, text, text, integer, text, text)
  to verified_access_phase2_resident_executor;
grant execute on function public.verified_access_list_resident_requests(text, text, timestamptz, timestamptz, timestamptz, uuid, integer)
  to verified_access_phase2_resident_executor;
grant execute on function public.verified_access_get_resident_request(uuid)
  to verified_access_phase2_resident_executor;
grant execute on function public.verified_access_cancel_resident_request(uuid, text, text, text)
  to verified_access_phase2_resident_executor;

grant verified_access_phase2_resident_executor to authenticated;

comment on function public.verified_access_create_resident_request(uuid, text, text, text, timestamptz, timestamptz, text, text, integer, text, text) is
  'Phase 2 authenticated resident request creation. Tenant and actor are derived server-side.';
comment on function public.verified_access_cancel_resident_request(uuid, text, text, text) is
  'Phase 2 authenticated resident cancellation. Draft-only and transactionally idempotent.';
