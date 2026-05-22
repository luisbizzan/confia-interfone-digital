create table if not exists public.condominium_features (
  condominium_id uuid not null references public.condominiums(id) on delete cascade,
  feature_key text not null,
  enabled boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (condominium_id, feature_key),
  constraint condominium_features_feature_key_uppercase
    check (feature_key = upper(feature_key))
);

create index if not exists idx_condominium_features_feature_key_enabled
on public.condominium_features(feature_key, enabled);

insert into public.condominium_features (condominium_id, feature_key, enabled)
select id, 'INTERCOM', true
from public.condominiums
on conflict (condominium_id, feature_key) do nothing;

alter table public.condominium_features enable row level security;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'condominium_features'
      and policyname = 'users read own condominium features'
  ) then
    create policy "users read own condominium features"
    on public.condominium_features for select
    to authenticated
    using (condominium_id = public.current_user_condominium_id());
  end if;
end;
$$;

create or replace function public.condominium_feature_enabled(
  p_condominium_id uuid,
  p_feature_key text
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.condominium_features cf
    where cf.condominium_id = p_condominium_id
      and cf.feature_key = upper(trim(p_feature_key))
      and cf.enabled = true
  )
$$;

create or replace function public.enforce_call_feature()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.condominium_feature_enabled(new.condominium_id, 'INTERCOM') then
    raise exception 'Intercom feature is disabled for this condominium';
  end if;

  return new;
end;
$$;

drop trigger if exists calls_require_intercom_feature on public.calls;
create trigger calls_require_intercom_feature
before insert on public.calls
for each row
execute function public.enforce_call_feature();

create or replace function public.admin_get_condominium_overview(p_condominium_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_condominium jsonb;
  v_features jsonb;
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

  select coalesce(jsonb_object_agg(cf.feature_key, cf.enabled), '{}'::jsonb)
    into v_features
  from public.condominium_features cf
  where cf.condominium_id = p_condominium_id;

  v_condominium := v_condominium || jsonb_build_object('features', v_features);

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
      'portaria_device_count', coalesce(portaria_counts.count, 0),
      'features', coalesce(feature_flags.features, '{}'::jsonb)
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
  left join lateral (
    select jsonb_object_agg(cf.feature_key, cf.enabled) as features
    from public.condominium_features cf
    where cf.condominium_id = c.id
  ) feature_flags on true
$$;

create or replace function public.get_current_user_context()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile jsonb;
  v_features jsonb;
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

  select coalesce(jsonb_object_agg(cf.feature_key, cf.enabled), '{}'::jsonb)
    into v_features
  from public.condominium_features cf
  where cf.condominium_id = (v_profile ->> 'condominium_id')::uuid;

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
    'features', v_features,
    'unit_members', v_unit_members,
    'portaria_devices', v_portaria_devices
  );
end;
$$;

create or replace function public.admin_create_condominium_with_portaria(
  p_condominium_name text,
  p_condominium_document text,
  p_portaria_user_id uuid,
  p_portaria_device_name text default 'Portaria',
  p_create_default_unit boolean default false,
  p_default_unit_type text default 'APARTMENT',
  p_default_unit_block text default null,
  p_default_unit_number text default null,
  p_intercom_enabled boolean default true
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

  insert into public.condominium_features (condominium_id, feature_key, enabled)
  values (v_condominium.id, 'INTERCOM', coalesce(p_intercom_enabled, true));

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

drop function if exists public.admin_create_condominium_with_portaria(text, text, uuid, text, boolean, text, text, text);

revoke all on table public.condominium_features from public, anon;
grant select on table public.condominium_features to authenticated;
grant select, insert, update, delete on table public.condominium_features to service_role;

revoke execute on function public.condominium_feature_enabled(uuid, text) from public;
revoke execute on function public.enforce_call_feature() from public;
revoke execute on function public.admin_get_condominium_overview(uuid) from public;
revoke execute on function public.admin_list_condominiums() from public;
revoke execute on function public.admin_create_condominium_with_portaria(text, text, uuid, text, boolean, text, text, text, boolean) from public;

grant execute on function public.condominium_feature_enabled(uuid, text) to authenticated, service_role;
grant execute on function public.admin_get_condominium_overview(uuid) to service_role;
grant execute on function public.admin_list_condominiums() to service_role;
grant execute on function public.admin_create_condominium_with_portaria(text, text, uuid, text, boolean, text, text, text, boolean) to service_role;
