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

revoke execute on function public.verified_access_validate_service_request_details() from public, anon, authenticated;
revoke execute on function public.verified_access_validate_slot_capacity() from public, anon, authenticated;
revoke execute on function public.verified_access_prevent_outbox_business_mutation() from public, anon, authenticated;
revoke execute on function public.verified_access_prevent_audit_mutation() from public, anon, authenticated;

grant select, insert, update on table public.verified_access_service_types to service_role;
grant select, insert, update on table public.verified_access_condominium_service_types to service_role;
grant select, insert, update on table public.verified_access_policies to service_role;
grant select, insert, update on table public.verified_access_requests to service_role;
grant select, insert, update on table public.verified_access_service_request_details to service_role;
grant select, insert, update on table public.verified_access_participant_slots to service_role;
grant select, insert, update on table public.verified_access_identity_profiles to service_role;
grant select, insert, update on table public.verified_access_participants to service_role;
grant select, insert on table public.verified_access_eligibility_evaluations to service_role;
grant select, insert, update on table public.verified_access_outbox_events to service_role;
grant select, insert on table public.verified_access_audit_events to service_role;

comment on function public.verified_access_validate_service_request_details() is
  'Valida tipo SERVICE_PROVIDER e descricao obrigatoria para catalogos que exigem descricao. Security invoker; sem grant publico.';
comment on function public.verified_access_validate_slot_capacity() is
  'Impede slot_number acima do participant_limit da solicitacao. Security invoker; sem grant publico.';
comment on function public.verified_access_prevent_outbox_business_mutation() is
  'Impede alteracao de payload de negocio da outbox apos insert, permitindo apenas campos operacionais.';
comment on function public.verified_access_prevent_audit_mutation() is
  'Impede update, delete e truncate na auditoria do Acesso Verificado. Append-only na Fase 1A.';
