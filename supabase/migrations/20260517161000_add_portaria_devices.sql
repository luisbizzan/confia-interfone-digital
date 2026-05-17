create table if not exists public.portaria_devices (
  id uuid primary key default gen_random_uuid(),
  condominium_id uuid not null references public.condominiums(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  is_active boolean not null default true,
  can_receive_calls boolean not null default true,
  can_make_calls boolean not null default true,
  priority_order integer not null default 1,
  created_at timestamptz not null default now(),
  unique (condominium_id, user_id)
);

alter table public.calls
add column if not exists target_type text not null default 'UNIT';

alter table public.calls
add column if not exists target_portaria_device_id uuid references public.portaria_devices(id);

alter table public.calls
add column if not exists origin_portaria_device_id uuid references public.portaria_devices(id);

alter table public.calls
drop constraint if exists calls_target_type_check;

alter table public.calls
add constraint calls_target_type_check
check (target_type in ('UNIT', 'PORTARIA'));

create index if not exists idx_portaria_devices_condominium_active
on public.portaria_devices(condominium_id, is_active, priority_order);

create index if not exists idx_calls_target_portaria_device_id
on public.calls(target_portaria_device_id);

alter table public.portaria_devices enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'portaria_devices'
      and policyname = 'users read portaria devices in condominium'
  ) then
    create policy "users read portaria devices in condominium"
    on public.portaria_devices for select
    to authenticated
    using (condominium_id = public.current_user_condominium_id());
  end if;
end $$;

create or replace function public.current_user_role_name()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select r.name
  from public.user_profiles up
  join public.roles r on r.id = up.role_id
  where up.id = auth.uid()
$$;

create or replace function public.current_portaria_device()
returns public.portaria_devices
language sql
stable
security definer
set search_path = public
as $$
  select pd.*
  from public.portaria_devices pd
  where pd.user_id = auth.uid()
    and pd.condominium_id = public.current_user_condominium_id()
    and pd.is_active = true
  order by pd.priority_order asc, pd.created_at asc
  limit 1
$$;

create or replace function public.first_active_portaria_device(p_condominium_id uuid)
returns public.portaria_devices
language sql
stable
security definer
set search_path = public
as $$
  select pd.*
  from public.portaria_devices pd
  where pd.condominium_id = p_condominium_id
    and pd.is_active = true
    and pd.can_receive_calls = true
  order by pd.priority_order asc, pd.created_at asc
  limit 1
$$;

create or replace function public.start_portaria_call(p_unit_id uuid)
returns public.calls
language plpgsql
security definer
set search_path = public
as $$
declare
  v_unit public.units;
  v_call public.calls;
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

  insert into public.call_attempts (call_id, unit_member_id, attempt_order, status)
  values (v_call.id, v_first_member.id, v_first_member.call_order, 'RINGING');

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
        ended_at = now()
  where id = p_call_id
  returning * into v_call;

  return v_call;
end;
$$;

create or replace function public.start_call(p_unit_id uuid)
returns public.calls
language sql
security definer
set search_path = public
as $$
  select public.start_portaria_call(p_unit_id)
$$;

revoke execute on function public.current_user_role_name() from public;
revoke execute on function public.current_portaria_device() from public;
revoke execute on function public.first_active_portaria_device(uuid) from public;
revoke execute on function public.start_portaria_call(uuid) from public;
revoke execute on function public.start_unit_to_portaria_call(uuid) from public;
revoke execute on function public.answer_portaria_call(uuid) from public;
revoke execute on function public.start_call(uuid) from public;

grant execute on function public.current_user_role_name() to authenticated;
grant execute on function public.current_portaria_device() to authenticated;
grant execute on function public.start_portaria_call(uuid) to authenticated;
grant execute on function public.start_unit_to_portaria_call(uuid) to authenticated;
grant execute on function public.answer_portaria_call(uuid) to authenticated;
grant execute on function public.first_active_portaria_device(uuid) to authenticated, service_role;
grant execute on function public.start_call(uuid) to authenticated;
