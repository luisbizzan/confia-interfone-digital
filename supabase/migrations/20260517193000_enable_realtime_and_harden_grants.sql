alter table public.calls replica identity full;
alter table public.call_attempts replica identity full;
alter table public.call_events replica identity full;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'calls'
  ) then
    alter publication supabase_realtime add table public.calls;
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'call_attempts'
  ) then
    alter publication supabase_realtime add table public.call_attempts;
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'call_events'
  ) then
    alter publication supabase_realtime add table public.call_events;
  end if;
end $$;

revoke insert, update, delete on table public.roles from anon, authenticated;
revoke insert, update, delete on table public.condominiums from anon, authenticated;
revoke insert, update, delete on table public.units from anon, authenticated;
revoke insert, update, delete on table public.user_profiles from anon, authenticated;
revoke insert, update, delete on table public.unit_members from anon, authenticated;
revoke insert, update, delete on table public.calls from anon, authenticated;
revoke insert, update, delete on table public.call_attempts from anon, authenticated;
revoke insert, update, delete on table public.call_events from anon, authenticated;
revoke insert, update, delete on table public.portaria_devices from anon, authenticated;
revoke insert, update, delete on table public.persons from anon, authenticated;
revoke insert, update, delete on table public.person_phones from anon, authenticated;
revoke insert, update, delete on table public.unit_contacts from anon, authenticated;

grant select on table public.roles to authenticated;
grant select on table public.condominiums to authenticated;
grant select on table public.units to authenticated;
grant select on table public.user_profiles to authenticated;
grant select on table public.unit_members to authenticated;
grant select on table public.calls to authenticated;
grant select on table public.call_attempts to authenticated;
grant select on table public.call_events to authenticated;
grant select on table public.portaria_devices to authenticated;
grant select on table public.persons to authenticated;
grant select on table public.person_phones to authenticated;
grant select on table public.unit_contacts to authenticated;
