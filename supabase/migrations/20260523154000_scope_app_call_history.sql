create or replace function public.get_my_call_history(p_limit integer default 50)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with current_units as (
    select um.unit_id
    from public.unit_members um
    where um.user_id = auth.uid()
  ),
  current_portaria_devices as (
    select pd.id
    from public.portaria_devices pd
    where pd.user_id = auth.uid()
      and pd.is_active = true
  ),
  scoped_calls as (
    select distinct c.*
    from public.calls c
    where exists (
        select 1
        from current_units cu
        where cu.unit_id = c.unit_id
           or cu.unit_id = c.origin_unit_id
      )
      or exists (
        select 1
        from current_portaria_devices cpd
        where cpd.id = c.target_portaria_device_id
           or cpd.id = c.origin_portaria_device_id
      )
    order by c.created_at desc
    limit greatest(1, least(coalesce(p_limit, 50), 100))
  )
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
  from scoped_calls c
$$;

revoke execute on function public.get_my_call_history(integer) from public;
grant execute on function public.get_my_call_history(integer) to authenticated;
