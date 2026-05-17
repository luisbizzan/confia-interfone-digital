create or replace function public.admin_get_condominium_overview(p_condominium_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_condominium jsonb;
  v_portaria_devices jsonb;
  v_units jsonb;
  v_recent_calls jsonb;
begin
  if p_condominium_id is null then
    raise exception 'Condominium id is required';
  end if;

  select to_jsonb(c)
    into v_condominium
  from public.condominiums c
  where c.id = p_condominium_id;

  if v_condominium is null then
    raise exception 'Condominium not found';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', pd.id,
      'user_id', pd.user_id,
      'name', pd.name,
      'is_active', pd.is_active,
      'can_receive_calls', pd.can_receive_calls,
      'can_make_calls', pd.can_make_calls,
      'priority_order', pd.priority_order,
      'created_at', pd.created_at
    )
    order by pd.priority_order asc, pd.created_at asc
  ), '[]'::jsonb)
    into v_portaria_devices
  from public.portaria_devices pd
  where pd.condominium_id = p_condominium_id;

  select coalesce(jsonb_agg(unit_doc order by unit_sort_block, unit_sort_number), '[]'::jsonb)
    into v_units
  from (
    select
      u.block as unit_sort_block,
      u.number as unit_sort_number,
      jsonb_build_object(
        'id', u.id,
        'type', u.type,
        'block', u.block,
        'number', u.number,
        'created_at', u.created_at,
        'members', coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'id', um.id,
              'user_id', um.user_id,
              'member_type', um.member_type,
              'active_for_calls', um.active_for_calls,
              'can_receive_calls', um.can_receive_calls,
              'can_make_calls', um.can_make_calls,
              'call_order', um.call_order,
              'created_at', um.created_at
            )
            order by um.call_order asc, um.created_at asc
          )
          from public.unit_members um
          where um.unit_id = u.id
        ), '[]'::jsonb)
      ) as unit_doc
    from public.units u
    where u.condominium_id = p_condominium_id
  ) units_with_members;

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
    into v_recent_calls
  from (
    select *
    from public.calls
    where condominium_id = p_condominium_id
    order by created_at desc
    limit 25
  ) c;

  return jsonb_build_object(
    'condominium', v_condominium,
    'portaria_devices', v_portaria_devices,
    'units', v_units,
    'recent_calls', v_recent_calls
  );
end;
$$;

create or replace function public.admin_list_condominiums()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', c.id,
      'name', c.name,
      'document', c.document,
      'created_at', c.created_at,
      'unit_count', coalesce(unit_counts.count, 0),
      'portaria_device_count', coalesce(portaria_counts.count, 0)
    )
    order by c.created_at desc
  ), '[]'::jsonb)
  from public.condominiums c
  left join lateral (
    select count(*)::integer
    from public.units u
    where u.condominium_id = c.id
  ) unit_counts(count) on true
  left join lateral (
    select count(*)::integer
    from public.portaria_devices pd
    where pd.condominium_id = c.id
  ) portaria_counts(count) on true
$$;

revoke execute on function public.admin_get_condominium_overview(uuid) from public;
revoke execute on function public.admin_list_condominiums() from public;

grant execute on function public.admin_get_condominium_overview(uuid) to service_role;
grant execute on function public.admin_list_condominiums() to service_role;
