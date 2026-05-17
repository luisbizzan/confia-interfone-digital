create extension if not exists "uuid-ossp" with schema extensions;
create extension if not exists "pgcrypto" with schema extensions;

create table if not exists public.roles (
  id uuid primary key default extensions.uuid_generate_v4(),
  name text not null unique
);

create table if not exists public.condominiums (
  id uuid primary key default extensions.uuid_generate_v4(),
  name text not null,
  document text,
  created_at timestamptz default now()
);

create table if not exists public.units (
  id uuid primary key default extensions.uuid_generate_v4(),
  condominium_id uuid not null references public.condominiums(id) on delete cascade,
  type text not null check (type in ('APARTMENT', 'HOUSE')),
  block text,
  number text not null,
  created_at timestamptz default now()
);

create table if not exists public.user_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  condominium_id uuid not null references public.condominiums(id) on delete cascade,
  role_id uuid not null references public.roles(id),
  created_at timestamptz default now()
);

create table if not exists public.unit_members (
  id uuid primary key default gen_random_uuid(),
  condominium_id uuid not null references public.condominiums(id) on delete cascade,
  unit_id uuid not null references public.units(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  active_for_calls boolean not null default false,
  can_receive_calls boolean not null default true,
  can_make_calls boolean not null default true,
  created_at timestamptz default now(),
  member_type text default 'RESIDENT' check (member_type in ('RESIDENT', 'DEVICE', 'PORTARIA')),
  call_order integer not null default 1,
  unique (unit_id, user_id)
);

create table if not exists public.calls (
  id uuid primary key default gen_random_uuid(),
  condominium_id uuid not null references public.condominiums(id) on delete cascade,
  unit_id uuid not null references public.units(id) on delete cascade,
  origin_type text not null check (origin_type in ('PORTARIA', 'UNIT')),
  origin_unit_id uuid references public.units(id),
  status text not null default 'RINGING' check (status in ('RINGING', 'ANSWERED', 'MISSED', 'CANCELLED')),
  answered_by uuid,
  started_at timestamptz not null default now(),
  answered_at timestamptz,
  ended_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.call_attempts (
  id uuid primary key default gen_random_uuid(),
  call_id uuid not null references public.calls(id) on delete cascade,
  unit_member_id uuid not null references public.unit_members(id) on delete restrict,
  attempt_order integer not null,
  status text not null default 'RINGING' check (status in ('RINGING', 'ANSWERED', 'NO_ANSWER', 'FAILED')),
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.persons (
  id uuid primary key default extensions.uuid_generate_v4(),
  unit_id uuid not null references public.units(id) on delete cascade,
  full_name text not null,
  created_at timestamptz default now()
);

create table if not exists public.person_phones (
  id uuid primary key default extensions.uuid_generate_v4(),
  person_id uuid not null references public.persons(id) on delete cascade,
  phone_number text not null,
  priority integer not null default 1,
  created_at timestamptz default now()
);

create table if not exists public.unit_contacts (
  id uuid primary key default gen_random_uuid(),
  condominium_id uuid not null references public.condominiums(id) on delete cascade,
  unit_id uuid not null references public.units(id) on delete cascade,
  user_id uuid,
  phone_number text,
  contact_type text not null,
  priority_order integer not null,
  max_attempts integer not null default 3,
  is_active boolean not null default true,
  created_at timestamptz default now()
);

create index if not exists idx_units_condominium_id on public.units(condominium_id);
create index if not exists idx_unit_members_unit_order on public.unit_members(unit_id, active_for_calls, call_order);
create index if not exists idx_calls_status_started_at on public.calls(status, started_at);
create index if not exists idx_call_attempts_call_status on public.call_attempts(call_id, status);

drop function if exists public.start_call(uuid);
drop function if exists public.answer_call(uuid, uuid);
drop function if exists public.process_call_timeout(uuid);
drop function if exists public.process_expired_calls();

create or replace function public.current_user_condominium_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select up.condominium_id
  from public.user_profiles up
  where up.id = auth.uid()
$$;

create or replace function public.start_call(p_unit_id uuid)
returns public.calls
language plpgsql
security definer
set search_path = public
as $$
declare
  v_unit public.units;
  v_call public.calls;
  v_first_member public.unit_members;
begin
  select *
    into v_unit
  from public.units
  where id = p_unit_id
    and condominium_id = public.current_user_condominium_id();

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

  insert into public.calls (condominium_id, unit_id, origin_type, status)
  values (v_unit.condominium_id, v_unit.id, 'PORTARIA', 'RINGING')
  returning * into v_call;

  insert into public.call_attempts (call_id, unit_member_id, attempt_order, status)
  values (v_call.id, v_first_member.id, v_first_member.call_order, 'RINGING');

  return v_call;
end;
$$;

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
        ended_at = now()
  where id = p_call_id
  returning * into v_call;

  return v_call;
end;
$$;

create or replace function public.process_call_timeout(p_call_id uuid)
returns public.calls
language plpgsql
security definer
set search_path = public
as $$
declare
  v_call public.calls;
  v_attempt public.call_attempts;
  v_next_member public.unit_members;
begin
  select *
    into v_call
  from public.calls
  where id = p_call_id
    and status = 'RINGING'
  for update skip locked;

  if not found then
    return null;
  end if;

  select *
    into v_attempt
  from public.call_attempts
  where call_id = p_call_id
    and status = 'RINGING'
  order by started_at desc
  limit 1
  for update;

  if not found then
    return v_call;
  end if;

  if v_attempt.started_at > now() - interval '20 seconds' then
    return v_call;
  end if;

  update public.call_attempts
    set status = 'NO_ANSWER',
        ended_at = now()
  where id = v_attempt.id;

  select *
    into v_next_member
  from public.unit_members
  where unit_id = v_call.unit_id
    and active_for_calls = true
    and can_receive_calls = true
    and call_order > v_attempt.attempt_order
  order by call_order asc, created_at asc
  limit 1;

  if found then
    insert into public.call_attempts (call_id, unit_member_id, attempt_order, status)
    values (v_call.id, v_next_member.id, v_next_member.call_order, 'RINGING');
  else
    update public.calls
      set status = 'MISSED',
          ended_at = now()
    where id = v_call.id
    returning * into v_call;
  end if;

  return v_call;
end;
$$;

create or replace function public.process_expired_calls()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_call record;
  v_processed integer := 0;
begin
  for v_call in
    select c.id
    from public.calls c
    join public.call_attempts ca on ca.call_id = c.id
    where c.status = 'RINGING'
      and ca.status = 'RINGING'
      and ca.started_at <= now() - interval '20 seconds'
  loop
    perform public.process_call_timeout(v_call.id);
    v_processed := v_processed + 1;
  end loop;

  return jsonb_build_object('processed', v_processed);
end;
$$;

alter table public.roles enable row level security;
alter table public.condominiums enable row level security;
alter table public.units enable row level security;
alter table public.user_profiles enable row level security;
alter table public.unit_members enable row level security;
alter table public.calls enable row level security;
alter table public.call_attempts enable row level security;
alter table public.persons enable row level security;
alter table public.person_phones enable row level security;
alter table public.unit_contacts enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'roles'
      and policyname = 'roles are readable by authenticated users'
  ) then
    create policy "roles are readable by authenticated users"
    on public.roles for select
    to authenticated
    using (true);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'condominiums'
      and policyname = 'users read own condominium'
  ) then
    create policy "users read own condominium"
    on public.condominiums for select
    to authenticated
    using (id = public.current_user_condominium_id());
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'units'
      and policyname = 'users read units in condominium'
  ) then
    create policy "users read units in condominium"
    on public.units for select
    to authenticated
    using (condominium_id = public.current_user_condominium_id());
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'user_profiles'
      and policyname = 'users read own profile'
  ) then
    create policy "users read own profile"
    on public.user_profiles for select
    to authenticated
    using (id = auth.uid());
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'unit_members'
      and policyname = 'users read unit members in condominium'
  ) then
    create policy "users read unit members in condominium"
    on public.unit_members for select
    to authenticated
    using (condominium_id = public.current_user_condominium_id());
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'calls'
      and policyname = 'users read calls in condominium'
  ) then
    create policy "users read calls in condominium"
    on public.calls for select
    to authenticated
    using (condominium_id = public.current_user_condominium_id());
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'call_attempts'
      and policyname = 'users read call attempts in condominium'
  ) then
    create policy "users read call attempts in condominium"
    on public.call_attempts for select
    to authenticated
    using (
      exists (
        select 1
        from public.calls c
        where c.id = call_attempts.call_id
          and c.condominium_id = public.current_user_condominium_id()
      )
    );
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'persons'
      and policyname = 'users read persons through condominium units'
  ) then
    create policy "users read persons through condominium units"
    on public.persons for select
    to authenticated
    using (
      exists (
        select 1
        from public.units u
        where u.id = persons.unit_id
          and u.condominium_id = public.current_user_condominium_id()
      )
    );
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'person_phones'
      and policyname = 'users read person phones through condominium units'
  ) then
    create policy "users read person phones through condominium units"
    on public.person_phones for select
    to authenticated
    using (
      exists (
        select 1
        from public.persons p
        join public.units u on u.id = p.unit_id
        where p.id = person_phones.person_id
          and u.condominium_id = public.current_user_condominium_id()
      )
    );
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'unit_contacts'
      and policyname = 'users read unit contacts in condominium'
  ) then
    create policy "users read unit contacts in condominium"
    on public.unit_contacts for select
    to authenticated
    using (condominium_id = public.current_user_condominium_id());
  end if;
end $$;

revoke execute on function public.current_user_condominium_id() from public;
revoke execute on function public.start_call(uuid) from public;
revoke execute on function public.answer_call(uuid, uuid) from public;
revoke execute on function public.process_call_timeout(uuid) from public;
revoke execute on function public.process_expired_calls() from public;

grant execute on function public.current_user_condominium_id() to authenticated;
grant execute on function public.start_call(uuid) to authenticated;
grant execute on function public.answer_call(uuid, uuid) to authenticated;
grant execute on function public.process_call_timeout(uuid) to service_role;
grant execute on function public.process_expired_calls() to service_role;
