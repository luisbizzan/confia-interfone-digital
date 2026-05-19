create or replace function public.answer_call(p_call_id uuid, p_user_id uuid)
returns public.calls
language plpgsql
security definer
set search_path = public
as $$
declare
  v_call public.calls;
  v_member public.unit_members;
  v_attempt public.call_attempts;
begin
  if p_user_id <> auth.uid() then
    raise exception 'User cannot answer on behalf of another user';
  end if;

  select *
    into v_call
  from public.calls
  where id = p_call_id
    and status = 'RINGING'
    and target_type = 'UNIT'
  for update;

  if not found then
    raise exception 'Call not found or not ringing';
  end if;

  select *
    into v_member
  from public.unit_members
  where unit_id = v_call.unit_id
    and user_id = p_user_id
    and active_for_calls = true
    and can_receive_calls = true;

  if not found then
    raise exception 'User cannot answer this call';
  end if;

  select *
    into v_attempt
  from public.call_attempts
  where call_id = p_call_id
    and unit_member_id = v_member.id
    and status = 'RINGING'
  for update;

  if not found then
    raise exception 'No active attempt for this user';
  end if;

  update public.call_attempts
    set status = 'ANSWERED',
        ended_at = now()
  where id = v_attempt.id;

  update public.calls
    set status = 'ANSWERED',
        answered_by = p_user_id,
        answered_at = now(),
        ended_at = null
  where id = p_call_id
  returning * into v_call;

  perform public.log_call_event(
    v_call.id,
    'CALL_ANSWERED',
    auth.uid(),
    'UNIT',
    jsonb_build_object('attempt_id', v_attempt.id, 'unit_member_id', v_member.id)
  );

  return v_call;
end;
$$;

create or replace function public.answer_portaria_call(p_call_id uuid)
returns public.calls
language plpgsql
security definer
set search_path = public
as $$
declare
  v_call public.calls;
  v_portaria public.portaria_devices;
begin
  select *
    into v_portaria
  from public.current_portaria_device();

  if not found or v_portaria.can_receive_calls is not true then
    raise exception 'Active portaria device not found or cannot receive calls';
  end if;

  select *
    into v_call
  from public.calls
  where id = p_call_id
    and status = 'RINGING'
    and target_type = 'PORTARIA'
    and target_portaria_device_id = v_portaria.id
  for update;

  if not found then
    raise exception 'Call not found or not assigned to this portaria device';
  end if;

  update public.calls
    set status = 'ANSWERED',
        answered_by = auth.uid(),
        answered_at = now(),
        ended_at = null
  where id = p_call_id
  returning * into v_call;

  perform public.log_call_event(
    v_call.id,
    'CALL_ANSWERED',
    auth.uid(),
    'PORTARIA',
    jsonb_build_object('portaria_device_id', v_portaria.id)
  );

  return v_call;
end;
$$;
