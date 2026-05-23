create or replace function public.start_portaria_call(p_unit_id uuid)
returns public.calls
language plpgsql
security definer
set search_path = public
as $$
declare
  v_unit public.units;
  v_call public.calls;
  v_attempt public.call_attempts;
  v_first_member public.unit_members;
  v_portaria public.portaria_devices;
begin
  select *
    into v_portaria
  from public.current_portaria_device();

  if not found or v_portaria.can_make_calls is not true then
    raise exception 'Active portaria device not found or cannot make calls';
  end if;

  select *
    into v_unit
  from public.units
  where id = p_unit_id
    and condominium_id = v_portaria.condominium_id;

  if not found then
    raise exception 'Unit not found or not allowed';
  end if;

  perform pg_advisory_xact_lock(hashtext('confia-portaria'), hashtext(v_portaria.id::text));
  perform pg_advisory_xact_lock(hashtext('confia-unit'), hashtext(v_unit.id::text));

  if exists (
    select 1
    from public.calls c
    where c.condominium_id = v_portaria.condominium_id
      and c.status in ('RINGING', 'ANSWERED')
      and c.ended_at is null
      and (
        (c.origin_type = 'PORTARIA' and c.origin_portaria_device_id = v_portaria.id)
        or (c.target_type = 'PORTARIA' and c.target_portaria_device_id = v_portaria.id)
      )
  ) then
    raise exception 'A portaria esta em atendimento. Tente novamente em alguns minutos.';
  end if;

  if exists (
    select 1
    from public.calls c
    where c.condominium_id = v_unit.condominium_id
      and c.status in ('RINGING', 'ANSWERED')
      and c.ended_at is null
      and (
        c.unit_id = v_unit.id
        or c.origin_unit_id = v_unit.id
      )
  ) then
    raise exception 'Esta unidade esta em atendimento. Tente novamente em alguns minutos.';
  end if;

  select *
    into v_first_member
  from public.unit_members
  where unit_id = p_unit_id
    and active_for_calls = true
    and can_receive_calls = true
  order by call_order asc, created_at asc
  limit 1;

  if not found then
    raise exception 'No active member available for calls';
  end if;

  insert into public.calls (
    condominium_id,
    unit_id,
    origin_type,
    origin_portaria_device_id,
    target_type,
    status
  )
  values (
    v_unit.condominium_id,
    v_unit.id,
    'PORTARIA',
    v_portaria.id,
    'UNIT',
    'RINGING'
  )
  returning * into v_call;

  perform public.log_call_event(
    v_call.id,
    'CALL_CREATED',
    auth.uid(),
    'PORTARIA',
    jsonb_build_object('target_type', 'UNIT', 'unit_id', v_unit.id)
  );

  insert into public.call_attempts (call_id, unit_member_id, attempt_order, status)
  values (v_call.id, v_first_member.id, v_first_member.call_order, 'RINGING')
  returning * into v_attempt;

  perform public.log_call_event(
    v_call.id,
    'ATTEMPT_CREATED',
    auth.uid(),
    'PORTARIA',
    jsonb_build_object(
      'attempt_id', v_attempt.id,
      'unit_member_id', v_attempt.unit_member_id,
      'attempt_order', v_attempt.attempt_order
    )
  );

  return v_call;
end;
$$;

create or replace function public.start_unit_to_portaria_call(p_unit_id uuid)
returns public.calls
language plpgsql
security definer
set search_path = public
as $$
declare
  v_unit public.units;
  v_member public.unit_members;
  v_portaria public.portaria_devices;
  v_call public.calls;
begin
  select *
    into v_member
  from public.unit_members
  where unit_id = p_unit_id
    and user_id = auth.uid()
    and active_for_calls = true
    and can_make_calls = true;

  if not found then
    raise exception 'User cannot start calls from this unit';
  end if;

  select *
    into v_unit
  from public.units
  where id = p_unit_id
    and condominium_id = v_member.condominium_id;

  if not found then
    raise exception 'Unit not found or not allowed';
  end if;

  select *
    into v_portaria
  from public.first_active_portaria_device(v_unit.condominium_id);

  if not found then
    raise exception 'No active portaria device available';
  end if;

  perform pg_advisory_xact_lock(hashtext('confia-portaria'), hashtext(v_portaria.id::text));
  perform pg_advisory_xact_lock(hashtext('confia-unit'), hashtext(v_unit.id::text));

  if exists (
    select 1
    from public.calls c
    where c.condominium_id = v_unit.condominium_id
      and c.status in ('RINGING', 'ANSWERED')
      and c.ended_at is null
      and (
        (c.origin_type = 'PORTARIA' and c.origin_portaria_device_id = v_portaria.id)
        or (c.target_type = 'PORTARIA' and c.target_portaria_device_id = v_portaria.id)
      )
  ) then
    raise exception 'A portaria esta em atendimento. Tente novamente em alguns minutos.';
  end if;

  if exists (
    select 1
    from public.calls c
    where c.condominium_id = v_unit.condominium_id
      and c.status in ('RINGING', 'ANSWERED')
      and c.ended_at is null
      and (
        c.unit_id = v_unit.id
        or c.origin_unit_id = v_unit.id
      )
  ) then
    raise exception 'Esta unidade esta em atendimento. Tente novamente em alguns minutos.';
  end if;

  insert into public.calls (
    condominium_id,
    unit_id,
    origin_type,
    origin_unit_id,
    target_type,
    target_portaria_device_id,
    status
  )
  values (
    v_unit.condominium_id,
    v_unit.id,
    'UNIT',
    v_unit.id,
    'PORTARIA',
    v_portaria.id,
    'RINGING'
  )
  returning * into v_call;

  perform public.log_call_event(
    v_call.id,
    'CALL_CREATED',
    auth.uid(),
    'UNIT',
    jsonb_build_object(
      'target_type', 'PORTARIA',
      'unit_id', v_unit.id,
      'target_portaria_device_id', v_portaria.id
    )
  );

  return v_call;
end;
$$;

create or replace function public.start_unit_to_unit_call(
  p_origin_unit_id uuid,
  p_target_unit_id uuid
)
returns public.calls
language plpgsql
security definer
set search_path = public
as $$
declare
  v_origin_unit public.units;
  v_target_unit public.units;
  v_origin_member public.unit_members;
  v_first_target_member public.unit_members;
  v_call public.calls;
  v_attempt public.call_attempts;
  v_first_lock uuid;
  v_second_lock uuid;
begin
  if p_origin_unit_id = p_target_unit_id then
    raise exception 'Origin and target units must be different';
  end if;

  select *
    into v_origin_member
  from public.unit_members
  where unit_id = p_origin_unit_id
    and user_id = auth.uid()
    and active_for_calls = true
    and can_make_calls = true;

  if not found then
    raise exception 'User cannot start calls from this unit';
  end if;

  select *
    into v_origin_unit
  from public.units
  where id = p_origin_unit_id
    and condominium_id = v_origin_member.condominium_id;

  if not found then
    raise exception 'Origin unit not found or not allowed';
  end if;

  select *
    into v_target_unit
  from public.units
  where id = p_target_unit_id
    and condominium_id = v_origin_unit.condominium_id;

  if not found then
    raise exception 'Target unit not found or not allowed';
  end if;

  if v_origin_unit.id::text < v_target_unit.id::text then
    v_first_lock := v_origin_unit.id;
    v_second_lock := v_target_unit.id;
  else
    v_first_lock := v_target_unit.id;
    v_second_lock := v_origin_unit.id;
  end if;

  perform pg_advisory_xact_lock(hashtext('confia-unit'), hashtext(v_first_lock::text));
  perform pg_advisory_xact_lock(hashtext('confia-unit'), hashtext(v_second_lock::text));

  if exists (
    select 1
    from public.calls c
    where c.condominium_id = v_origin_unit.condominium_id
      and c.status in ('RINGING', 'ANSWERED')
      and c.ended_at is null
      and (
        c.unit_id = v_origin_unit.id
        or c.origin_unit_id = v_origin_unit.id
      )
  ) then
    raise exception 'Sua unidade esta em atendimento. Encerre a chamada atual antes de iniciar outra.';
  end if;

  if exists (
    select 1
    from public.calls c
    where c.condominium_id = v_target_unit.condominium_id
      and c.status in ('RINGING', 'ANSWERED')
      and c.ended_at is null
      and (
        c.unit_id = v_target_unit.id
        or c.origin_unit_id = v_target_unit.id
      )
  ) then
    raise exception 'Esta unidade esta em atendimento. Tente novamente em alguns minutos.';
  end if;

  select *
    into v_first_target_member
  from public.unit_members
  where unit_id = v_target_unit.id
    and active_for_calls = true
    and can_receive_calls = true
  order by call_order asc, created_at asc
  limit 1;

  if not found then
    raise exception 'No active member available for calls';
  end if;

  insert into public.calls (
    condominium_id,
    unit_id,
    origin_type,
    origin_unit_id,
    target_type,
    status
  )
  values (
    v_target_unit.condominium_id,
    v_target_unit.id,
    'UNIT',
    v_origin_unit.id,
    'UNIT',
    'RINGING'
  )
  returning * into v_call;

  perform public.log_call_event(
    v_call.id,
    'CALL_CREATED',
    auth.uid(),
    'UNIT',
    jsonb_build_object(
      'target_type', 'UNIT',
      'origin_unit_id', v_origin_unit.id,
      'target_unit_id', v_target_unit.id
    )
  );

  insert into public.call_attempts (call_id, unit_member_id, attempt_order, status)
  values (v_call.id, v_first_target_member.id, v_first_target_member.call_order, 'RINGING')
  returning * into v_attempt;

  perform public.log_call_event(
    v_call.id,
    'ATTEMPT_CREATED',
    auth.uid(),
    'UNIT',
    jsonb_build_object(
      'attempt_id', v_attempt.id,
      'unit_member_id', v_attempt.unit_member_id,
      'attempt_order', v_attempt.attempt_order
    )
  );

  return v_call;
end;
$$;

revoke execute on function public.start_portaria_call(uuid) from public;
revoke execute on function public.start_unit_to_portaria_call(uuid) from public;
revoke execute on function public.start_unit_to_unit_call(uuid, uuid) from public;

grant execute on function public.start_portaria_call(uuid) to authenticated;
grant execute on function public.start_unit_to_portaria_call(uuid) to authenticated;
grant execute on function public.start_unit_to_unit_call(uuid, uuid) to authenticated;
