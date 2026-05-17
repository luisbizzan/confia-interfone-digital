create or replace function public.portaria_role_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select id
  from public.roles
  where name = 'PORTARIA'
  limit 1
$$;

create or replace function public.admin_create_condominium_with_portaria(
  p_condominium_name text,
  p_condominium_document text,
  p_portaria_user_id uuid,
  p_portaria_device_name text default 'Portaria',
  p_create_default_unit boolean default false,
  p_default_unit_type text default 'APARTMENT',
  p_default_unit_block text default null,
  p_default_unit_number text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_condominium public.condominiums;
  v_portaria_device public.portaria_devices;
  v_default_unit public.units;
  v_portaria_role_id uuid;
begin
  if nullif(trim(p_condominium_name), '') is null then
    raise exception 'Condominium name is required';
  end if;

  if p_portaria_user_id is null then
    raise exception 'Portaria user id is required';
  end if;

  select public.portaria_role_id()
    into v_portaria_role_id;

  if v_portaria_role_id is null then
    raise exception 'PORTARIA role not found';
  end if;

  insert into public.condominiums (name, document)
  values (trim(p_condominium_name), nullif(trim(p_condominium_document), ''))
  returning * into v_condominium;

  insert into public.user_profiles (id, condominium_id, role_id)
  values (p_portaria_user_id, v_condominium.id, v_portaria_role_id)
  on conflict (id) do update
    set condominium_id = excluded.condominium_id,
        role_id = excluded.role_id;

  insert into public.portaria_devices (
    condominium_id,
    user_id,
    name,
    is_active,
    can_receive_calls,
    can_make_calls,
    priority_order
  )
  values (
    v_condominium.id,
    p_portaria_user_id,
    coalesce(nullif(trim(p_portaria_device_name), ''), 'Portaria'),
    true,
    true,
    true,
    1
  )
  returning * into v_portaria_device;

  if p_create_default_unit then
    insert into public.units (condominium_id, type, block, number)
    values (
      v_condominium.id,
      coalesce(nullif(trim(p_default_unit_type), ''), 'APARTMENT'),
      nullif(trim(p_default_unit_block), ''),
      coalesce(nullif(trim(p_default_unit_number), ''), '101')
    )
    returning * into v_default_unit;
  end if;

  return jsonb_build_object(
    'condominium_id', v_condominium.id,
    'portaria_user_id', p_portaria_user_id,
    'portaria_device_id', v_portaria_device.id,
    'default_unit_id', v_default_unit.id
  );
end;
$$;

revoke execute on function public.portaria_role_id() from public;
revoke execute on function public.admin_create_condominium_with_portaria(text, text, uuid, text, boolean, text, text, text) from public;

grant execute on function public.portaria_role_id() to authenticated, service_role;
grant execute on function public.admin_create_condominium_with_portaria(text, text, uuid, text, boolean, text, text, text) to service_role;
