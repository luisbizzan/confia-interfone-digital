alter table public.app_push_tokens
add column if not exists native_push_token text,
add column if not exists native_push_provider text;

create unique index if not exists idx_app_push_tokens_native_token
on public.app_push_tokens(native_push_token)
where native_push_token is not null;

create or replace function public.register_app_push_token(
  p_expo_push_token text,
  p_platform text default 'unknown',
  p_profile text default null,
  p_device_id text default null,
  p_device_name text default null,
  p_app_version text default null,
  p_app_build text default null,
  p_native_push_token text default null,
  p_native_push_provider text default null
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

  if p_expo_push_token is null or p_expo_push_token !~ '^(ExponentPushToken|ExpoPushToken)\[[A-Za-z0-9_-]+\]$' then
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
    native_push_token,
    native_push_provider,
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
    nullif(p_native_push_token, ''),
    nullif(p_native_push_provider, ''),
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
    native_push_token = excluded.native_push_token,
    native_push_provider = excluded.native_push_provider,
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

revoke execute on function public.register_app_push_token(text, text, text, text, text, text, text, text, text) from public;
grant execute on function public.register_app_push_token(text, text, text, text, text, text, text, text, text) to authenticated;
