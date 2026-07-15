drop trigger if exists verified_access_audit_events_prevent_delete on public.verified_access_audit_events;
drop trigger if exists verified_access_audit_events_prevent_update on public.verified_access_audit_events;
drop function if exists public.verified_access_prevent_audit_mutation();
drop function if exists public.verified_access_service_type_requires_description(uuid);

drop table if exists public.verified_access_audit_events;
drop table if exists public.verified_access_outbox_events;
drop table if exists public.verified_access_eligibility_evaluations;
drop table if exists public.verified_access_participants;
drop table if exists public.verified_access_identity_profiles;
drop table if exists public.verified_access_participant_slots;
drop table if exists public.verified_access_service_request_details;
drop table if exists public.verified_access_requests;
drop table if exists public.verified_access_policies;
drop table if exists public.verified_access_condominium_service_types;
drop table if exists public.verified_access_service_types;

delete from public.condominium_features
where feature_key in ('VERIFIED_ACCESS', 'VERIFIED_ACCESS_BACKGROUND_CHECK')
  and enabled = false;
