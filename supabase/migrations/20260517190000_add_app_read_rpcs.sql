create or replace function public.get_current_user_context()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile jsonb;
  v_unit_members jsonb;
  v_portaria_devices jsonb;
begin
  select jsonb_build_object(
    'user_id', up.id,
    'condominium_id', up.condominium_id,
    'role', r.name
  )
    into v_profile
  from public.user_profiles up
  join public.roles r on r.id = up.role_id
  where up.id = auth.uid();

  if v_profile is null then
    raise exception 'User profile not found';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', um.id,
      'unit_id', um.unit_id,
      'member_type', um.member_type,
      'active_for_calls', um.active_for_calls,
      'can_receive_calls', um.can_receive_calls,
      'can_make_calls', um.can_make_calls,
      'call_order', um.call_order,
      'unit', jsonb_build_object(
        'id', u.id,
        'type', u.type,
        'block', u.block,
        'number', u.number
      )
    )
    order by u.block, u.number, um.call_order
  ), '[]'::jsonb)
    into v_unit_members
  from public.unit_members um
  join public.units u on u.id = um.unit_id
  where um.user_id = auth.uid();

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', pd.id,
      'name', pd.name,
      'is_active', pd.is_active,
      'can_receive_calls', pd.can_receive_calls,
      'can_make_calls', pd.can_make_calls,
      'priority_order', pd.priority_order
    )
    order by pd.priority_order, pd.created_at
  ), '[]'::jsonb)
    into v_portaria_devices
  from public.portaria_devices pd
  where pd.user_id = auth.uid();

  return jsonb_build_object(
    'profile', v_profile,
    'unit_members', v_unit_members,
    'portaria_devices', v_portaria_devices
  );
end;
$$;

create or replace function public.get_my_pending_calls()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_unit_calls jsonb;
  v_portaria_calls jsonb;
begin
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'call_id', c.id,
      'attempt_id', ca.id,
      'unit_id', c.unit_id,
      'origin_type', c.origin_type,
      'origin_unit_id', c.origin_unit_id,
      'origin_portaria_device_id', c.origin_portaria_device_id,
      'target_type', c.target_type,
      'status', c.status,
      'started_at', c.started_at,
      'attempt_started_at', ca.started_at
    )
    order by ca.started_at desc
  ), '[]'::jsonb)
    into v_unit_calls
  from public.calls c
  join public.call_attempts ca on ca.call_id = c.id
  join public.unit_members um on um.id = ca.unit_member_id
  where c.status = 'RINGING'
    and c.target_type = 'UNIT'
    and ca.status = 'RINGING'
    and um.user_id = auth.uid()
    and um.active_for_calls = true
    and um.can_receive_calls = true;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'call_id', c.id,
      'unit_id', c.unit_id,
      'origin_type', c.origin_type,
      'origin_unit_id', c.origin_unit_id,
      'target_type', c.target_type,
      'target_portaria_device_id', c.target_portaria_device_id,
      'status', c.status,
      'started_at', c.started_at
    )
    order by c.started_at desc
  ), '[]'::jsonb)
    into v_portaria_calls
  from public.calls c
  join public.portaria_devices pd on pd.id = c.target_portaria_device_id
  where c.status = 'RINGING'
    and c.target_type = 'PORTARIA'
    and pd.user_id = auth.uid()
    and pd.is_active = true
    and pd.can_receive_calls = true;

  return jsonb_build_object(
    'unit_calls', v_unit_calls,
    'portaria_calls', v_portaria_calls
  );
end;
$$;

create or replace function public.get_my_call_history(p_limit integer default 50)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', c.id,
      'unit_id', c.unit_id,
      'origin_type', c.origin_type,
      'origin_unit_id', c.origin_unit_id,
      'origin_portaria_device_id', c.origin_portaria_device_id,
      'target_type', c.target_type,
      'target_portaria_device_id', c.target_portaria_device_id,
      'status', c.status,
      'answered_by', c.answered_by,
      'started_at', c.started_at,
      'answered_at', c.answered_at,
      'ended_at', c.ended_at,
      'created_at', c.created_at
    )
    order by c.created_at desc
  ), '[]'::jsonb)
  from (
    select distinct c.*
    from public.calls c
    left join public.unit_members um
      on um.unit_id = c.unit_id
      and um.user_id = auth.uid()
    left join public.portaria_devices pd
      on pd.condominium_id = c.condominium_id
      and pd.user_id = auth.uid()
    where um.id is not null
       or pd.id is not null
    order by c.created_at desc
    limit greatest(1, least(coalesce(p_limit, 50), 100))
  ) c
$$;

revoke execute on function public.get_current_user_context() from public;
revoke execute on function public.get_my_pending_calls() from public;
revoke execute on function public.get_my_call_history(integer) from public;

grant execute on function public.get_current_user_context() to authenticated;
grant execute on function public.get_my_pending_calls() to authenticated;
grant execute on function public.get_my_call_history(integer) to authenticated;
