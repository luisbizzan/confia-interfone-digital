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

revoke execute on function public.start_unit_to_unit_call(uuid, uuid) from public;
grant execute on function public.start_unit_to_unit_call(uuid, uuid) to authenticated;
