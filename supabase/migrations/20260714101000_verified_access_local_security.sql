alter table public.verified_access_service_types enable row level security;
alter table public.verified_access_condominium_service_types enable row level security;
alter table public.verified_access_policies enable row level security;
alter table public.verified_access_requests enable row level security;
alter table public.verified_access_service_request_details enable row level security;
alter table public.verified_access_participant_slots enable row level security;
alter table public.verified_access_identity_profiles enable row level security;
alter table public.verified_access_participants enable row level security;
alter table public.verified_access_eligibility_evaluations enable row level security;
alter table public.verified_access_outbox_events enable row level security;
alter table public.verified_access_audit_events enable row level security;

revoke all on table public.verified_access_service_types from public, anon, authenticated;
revoke all on table public.verified_access_condominium_service_types from public, anon, authenticated;
revoke all on table public.verified_access_policies from public, anon, authenticated;
revoke all on table public.verified_access_requests from public, anon, authenticated;
revoke all on table public.verified_access_service_request_details from public, anon, authenticated;
revoke all on table public.verified_access_participant_slots from public, anon, authenticated;
revoke all on table public.verified_access_identity_profiles from public, anon, authenticated;
revoke all on table public.verified_access_participants from public, anon, authenticated;
revoke all on table public.verified_access_eligibility_evaluations from public, anon, authenticated;
revoke all on table public.verified_access_outbox_events from public, anon, authenticated;
revoke all on table public.verified_access_audit_events from public, anon, authenticated;

revoke execute on function public.verified_access_service_type_requires_description(uuid) from public, anon, authenticated;
grant execute on function public.verified_access_service_type_requires_description(uuid) to service_role;

grant select, insert, update, delete on table public.verified_access_service_types to service_role;
grant select, insert, update, delete on table public.verified_access_condominium_service_types to service_role;
grant select, insert, update, delete on table public.verified_access_policies to service_role;
grant select, insert, update, delete on table public.verified_access_requests to service_role;
grant select, insert, update, delete on table public.verified_access_service_request_details to service_role;
grant select, insert, update, delete on table public.verified_access_participant_slots to service_role;
grant select, insert, update, delete on table public.verified_access_identity_profiles to service_role;
grant select, insert, update, delete on table public.verified_access_participants to service_role;
grant select, insert, update, delete on table public.verified_access_eligibility_evaluations to service_role;
grant select, insert, update, delete on table public.verified_access_outbox_events to service_role;
grant select, insert on table public.verified_access_audit_events to service_role;

create or replace function public.verified_access_prevent_audit_mutation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  raise exception 'verified_access_audit_events is append-only';
end;
$$;

drop trigger if exists verified_access_audit_events_prevent_update on public.verified_access_audit_events;
create trigger verified_access_audit_events_prevent_update
before update on public.verified_access_audit_events
for each row
execute function public.verified_access_prevent_audit_mutation();

drop trigger if exists verified_access_audit_events_prevent_delete on public.verified_access_audit_events;
create trigger verified_access_audit_events_prevent_delete
before delete on public.verified_access_audit_events
for each row
execute function public.verified_access_prevent_audit_mutation();

revoke execute on function public.verified_access_prevent_audit_mutation() from public, anon, authenticated;
grant execute on function public.verified_access_prevent_audit_mutation() to service_role;

comment on function public.verified_access_prevent_audit_mutation() is
  'Impede update/delete na auditoria do Acesso Verificado. Append-only na Fase 1A.';
