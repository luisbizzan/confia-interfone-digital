create table if not exists public.app_push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  condominium_id uuid not null references public.condominiums(id) on delete cascade,
  expo_push_token text not null unique,
  platform text not null check (platform in ('android', 'ios', 'web', 'unknown')),
  profile text,
  device_id text,
  device_name text,
  app_version text,
  app_build text,
  is_active boolean not null default true,
  last_registered_at timestamptz not null default now(),
  disabled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_app_push_tokens_user_active
on public.app_push_tokens(user_id, is_active);

create index if not exists idx_app_push_tokens_condominium_active
on public.app_push_tokens(condominium_id, is_active);

alter table public.app_push_tokens enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'app_push_tokens'
      and policyname = 'users read own push tokens'
  ) then
    create policy "users read own push tokens"
    on public.app_push_tokens for select
    to authenticated
    using (user_id = auth.uid());
  end if;
end $$;

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists app_push_tokens_touch_updated_at on public.app_push_tokens;
create trigger app_push_tokens_touch_updated_at
before update on public.app_push_tokens
for each row execute function public.touch_updated_at();

create or replace function public.register_app_push_token(
  p_expo_push_token text,
  p_platform text default 'unknown',
  p_profile text default null,
  p_device_id text default null,
  p_device_name text default null,
  p_app_version text default null,
  p_app_build text default null
)
returns public.app_push_tokens
language plpgsql
security definer
set search_path = public
as $$
declare
  v_condominium_id uuid;
  v_token public.app_push_tokens;
begin
  if auth.uid() is null then
    raise exception 'Unauthorized';
  end if;

  if p_expo_push_token is null or p_expo_push_token !~ '^ExponentPushToken\\[[A-Za-z0-9_-]+\\]$|^ExpoPushToken\\[[A-Za-z0-9_-]+\\]$' then
    raise exception 'Invalid Expo push token';
  end if;

  select up.condominium_id
    into v_condominium_id
  from public.user_profiles up
  where up.id = auth.uid();

  if not found then
    raise exception 'User profile not found';
  end if;

  insert into public.app_push_tokens (
    user_id,
    condominium_id,
    expo_push_token,
    platform,
    profile,
    device_id,
    device_name,
    app_version,
    app_build,
    is_active,
    last_registered_at,
    disabled_at
  )
  values (
    auth.uid(),
    v_condominium_id,
    p_expo_push_token,
    coalesce(nullif(p_platform, ''), 'unknown'),
    nullif(p_profile, ''),
    nullif(p_device_id, ''),
    nullif(p_device_name, ''),
    nullif(p_app_version, ''),
    nullif(p_app_build, ''),
    true,
    now(),
    null
  )
  on conflict (expo_push_token)
  do update set
    user_id = excluded.user_id,
    condominium_id = excluded.condominium_id,
    platform = excluded.platform,
    profile = excluded.profile,
    device_id = excluded.device_id,
    device_name = excluded.device_name,
    app_version = excluded.app_version,
    app_build = excluded.app_build,
    is_active = true,
    last_registered_at = now(),
    disabled_at = null
  returning * into v_token;

  return v_token;
end;
$$;

create or replace function public.unregister_app_push_token(p_expo_push_token text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Unauthorized';
  end if;

  update public.app_push_tokens
  set is_active = false,
      disabled_at = now()
  where user_id = auth.uid()
    and expo_push_token = p_expo_push_token;
end;
$$;

revoke all on table public.app_push_tokens from anon, authenticated;
grant select on table public.app_push_tokens to authenticated;
grant select, insert, update, delete on table public.app_push_tokens to service_role;

revoke execute on function public.register_app_push_token(text, text, text, text, text, text, text) from public;
revoke execute on function public.unregister_app_push_token(text) from public;

grant execute on function public.register_app_push_token(text, text, text, text, text, text, text) to authenticated;
grant execute on function public.unregister_app_push_token(text) to authenticated;
