create or replace function public.admin_create_unit(
  p_condominium_id uuid,
  p_type text,
  p_block text,
  p_number text
)
returns public.units
language plpgsql
security definer
set search_path = public
as $$
declare
  v_unit public.units;
begin
  if p_condominium_id is null then
    raise exception 'Condominium id is required';
  end if;

  if nullif(trim(p_number), '') is null then
    raise exception 'Unit number is required';
  end if;

  insert into public.units (condominium_id, type, block, number)
  values (
    p_condominium_id,
    coalesce(nullif(trim(p_type), ''), 'APARTMENT'),
    nullif(trim(p_block), ''),
    trim(p_number)
  )
  returning * into v_unit;

  return v_unit;
end;
$$;

create or replace function public.admin_create_unit_member(
  p_condominium_id uuid,
  p_unit_id uuid,
  p_user_id uuid,
  p_member_type text default 'RESIDENT',
  p_call_order integer default null,
  p_active_for_calls boolean default true,
  p_can_receive_calls boolean default true,
  p_can_make_calls boolean default true
)
returns public.unit_members
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role_id uuid;
  v_unit public.units;
  v_next_order integer;
  v_member public.unit_members;
begin
  if p_condominium_id is null then
    raise exception 'Condominium id is required';
  end if;

  if p_unit_id is null then
    raise exception 'Unit id is required';
  end if;

  if p_user_id is null then
    raise exception 'User id is required';
  end if;

  select *
    into v_unit
  from public.units
  where id = p_unit_id
    and condominium_id = p_condominium_id;

  if not found then
    raise exception 'Unit not found in condominium';
  end if;

  select id
    into v_role_id
  from public.roles
  where name = 'MORADOR'
  limit 1;

  if v_role_id is null then
    raise exception 'MORADOR role not found';
  end if;

  if p_call_order is null then
    select coalesce(max(call_order), 0) + 1
      into v_next_order
    from public.unit_members
    where unit_id = p_unit_id;
  else
    v_next_order := p_call_order;
  end if;

  insert into public.user_profiles (id, condominium_id, role_id)
  values (p_user_id, p_condominium_id, v_role_id)
  on conflict (id) do update
    set condominium_id = excluded.condominium_id,
        role_id = excluded.role_id;

  insert into public.unit_members (
    condominium_id,
    unit_id,
    user_id,
    active_for_calls,
    can_receive_calls,
    can_make_calls,
    member_type,
    call_order
  )
  values (
    p_condominium_id,
    p_unit_id,
    p_user_id,
    coalesce(p_active_for_calls, true),
    coalesce(p_can_receive_calls, true),
    coalesce(p_can_make_calls, true),
    coalesce(nullif(trim(p_member_type), ''), 'RESIDENT'),
    v_next_order
  )
  on conflict (unit_id, user_id) do update
    set active_for_calls = excluded.active_for_calls,
        can_receive_calls = excluded.can_receive_calls,
        can_make_calls = excluded.can_make_calls,
        member_type = excluded.member_type,
        call_order = excluded.call_order
  returning * into v_member;

  return v_member;
end;
$$;

create or replace function public.admin_set_unit_member_call_settings(
  p_unit_member_id uuid,
  p_active_for_calls boolean,
  p_can_receive_calls boolean,
  p_can_make_calls boolean,
  p_call_order integer
)
returns public.unit_members
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member public.unit_members;
begin
  update public.unit_members
    set active_for_calls = coalesce(p_active_for_calls, active_for_calls),
        can_receive_calls = coalesce(p_can_receive_calls, can_receive_calls),
        can_make_calls = coalesce(p_can_make_calls, can_make_calls),
        call_order = coalesce(p_call_order, call_order)
  where id = p_unit_member_id
  returning * into v_member;

  if not found then
    raise exception 'Unit member not found';
  end if;

  return v_member;
end;
$$;

revoke execute on function public.admin_create_unit(uuid, text, text, text) from public;
revoke execute on function public.admin_create_unit_member(uuid, uuid, uuid, text, integer, boolean, boolean, boolean) from public;
revoke execute on function public.admin_set_unit_member_call_settings(uuid, boolean, boolean, boolean, integer) from public;

grant execute on function public.admin_create_unit(uuid, text, text, text) to service_role;
grant execute on function public.admin_create_unit_member(uuid, uuid, uuid, text, integer, boolean, boolean, boolean) to service_role;
grant execute on function public.admin_set_unit_member_call_settings(uuid, boolean, boolean, boolean, integer) to service_role;
