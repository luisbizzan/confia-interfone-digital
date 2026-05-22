create table if not exists public.app_error_reports (
  id uuid primary key default gen_random_uuid(),
  condominium_id uuid references public.condominiums(id) on delete set null,
  user_id uuid references auth.users(id) on delete set null,
  profile text,
  source text not null,
  message text not null,
  stack text,
  component_stack text,
  route text,
  app_version text,
  platform text,
  os_version text,
  device_model text,
  call_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint app_error_reports_source_not_empty check (length(trim(source)) > 0),
  constraint app_error_reports_message_not_empty check (length(trim(message)) > 0)
);

create index if not exists idx_app_error_reports_created_at
on public.app_error_reports(created_at desc);

create index if not exists idx_app_error_reports_condominium_created_at
on public.app_error_reports(condominium_id, created_at desc);

alter table public.app_error_reports enable row level security;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'app_error_reports'
      and policyname = 'authenticated users create own app error reports'
  ) then
    create policy "authenticated users create own app error reports"
    on public.app_error_reports for insert
    to authenticated
    with check (
      user_id = auth.uid()
      and (
        condominium_id is null
        or condominium_id = public.current_user_condominium_id()
      )
    );
  end if;
end;
$$;

revoke all on table public.app_error_reports from public, anon;
grant insert on table public.app_error_reports to authenticated;
grant select, insert, update, delete on table public.app_error_reports to service_role;
