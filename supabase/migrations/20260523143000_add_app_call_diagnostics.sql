create table if not exists public.app_call_diagnostics (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid(),
  condominium_id uuid,
  profile text,
  action text not null,
  result text not null check (result in ('STARTED', 'SUCCESS', 'ERROR')),
  call_id uuid,
  unit_id uuid,
  target_unit_id uuid,
  duration_ms integer,
  error_message text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_app_call_diagnostics_user_created_at
on public.app_call_diagnostics(user_id, created_at desc);

create index if not exists idx_app_call_diagnostics_condominium_created_at
on public.app_call_diagnostics(condominium_id, created_at desc);

create index if not exists idx_app_call_diagnostics_call_created_at
on public.app_call_diagnostics(call_id, created_at desc);

alter table public.app_call_diagnostics enable row level security;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'app_call_diagnostics'
      and policyname = 'authenticated users insert own diagnostics'
  ) then
    create policy "authenticated users insert own diagnostics"
    on public.app_call_diagnostics
    for insert
    to authenticated
    with check (user_id = auth.uid());
  end if;
end $$;

revoke all on table public.app_call_diagnostics from public, anon;
grant insert on table public.app_call_diagnostics to authenticated;
grant select, insert, update, delete on table public.app_call_diagnostics to service_role;
