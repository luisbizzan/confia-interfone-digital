create or replace function public.verified_access_transition_allowed(
  p_machine text,
  p_old_status text,
  p_new_status text
)
returns boolean
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
begin
  if p_old_status is not distinct from p_new_status then
    return true;
  end if;

  return case p_machine
    when 'request.status' then
      (p_old_status = 'DRAFT' and p_new_status in ('INVITATIONS_PENDING', 'CANCELLED', 'EXPIRED'))
      or (p_old_status = 'INVITATIONS_PENDING' and p_new_status in ('IN_PROGRESS', 'PARTIALLY_ELIGIBLE', 'ELIGIBLE', 'CANCELLED', 'EXPIRED'))
      or (p_old_status = 'IN_PROGRESS' and p_new_status in ('PARTIALLY_ELIGIBLE', 'ELIGIBLE', 'CANCELLED', 'EXPIRED'))
      or (p_old_status = 'PARTIALLY_ELIGIBLE' and p_new_status in ('ELIGIBLE', 'COMPLETED', 'CANCELLED', 'EXPIRED'))
      or (p_old_status = 'ELIGIBLE' and p_new_status in ('COMPLETED', 'CANCELLED', 'EXPIRED'))

    when 'slot.status' then
      (p_old_status = 'OPEN' and p_new_status in ('RESERVED', 'CLAIMED', 'CANCELLED', 'EXPIRED'))
      or (p_old_status = 'RESERVED' and p_new_status in ('CLAIMED', 'CANCELLED', 'EXPIRED'))
      or (p_old_status = 'CLAIMED' and p_new_status in ('CANCELLED', 'EXPIRED'))
      or (p_old_status = 'CANCELLED' and p_new_status = 'EXPIRED')

    when 'participant.registration_status' then
      (p_old_status = 'NOT_STARTED' and p_new_status in ('INVITED', 'IN_PROGRESS', 'SUBMITTED', 'CANCELLED', 'EXPIRED'))
      or (p_old_status = 'INVITED' and p_new_status in ('IN_PROGRESS', 'SUBMITTED', 'CANCELLED', 'EXPIRED'))
      or (p_old_status = 'IN_PROGRESS' and p_new_status in ('SUBMITTED', 'CANCELLED', 'EXPIRED'))
      or (p_old_status = 'SUBMITTED' and p_new_status in ('CANCELLED', 'EXPIRED'))

    when 'participant.identity_status' then
      (p_old_status = 'UNVERIFIED' and p_new_status in ('SELF_DECLARED', 'CONTACT_VERIFIED', 'DOCUMENT_CAPTURED', 'DOCUMENT_VERIFIED', 'LIVENESS_VERIFIED', 'IDENTITY_VERIFIED', 'MANUAL_VERIFIED', 'INCONCLUSIVE', 'TECHNICAL_ERROR'))
      or (p_old_status = 'SELF_DECLARED' and p_new_status in ('CONTACT_VERIFIED', 'DOCUMENT_CAPTURED', 'DOCUMENT_VERIFIED', 'LIVENESS_VERIFIED', 'IDENTITY_VERIFIED', 'MANUAL_VERIFIED', 'INCONCLUSIVE', 'TECHNICAL_ERROR'))
      or (p_old_status = 'CONTACT_VERIFIED' and p_new_status in ('DOCUMENT_CAPTURED', 'DOCUMENT_VERIFIED', 'LIVENESS_VERIFIED', 'IDENTITY_VERIFIED', 'MANUAL_VERIFIED', 'INCONCLUSIVE', 'TECHNICAL_ERROR'))
      or (p_old_status = 'DOCUMENT_CAPTURED' and p_new_status in ('DOCUMENT_VERIFIED', 'LIVENESS_VERIFIED', 'IDENTITY_VERIFIED', 'MANUAL_VERIFIED', 'INCONCLUSIVE', 'TECHNICAL_ERROR'))
      or (p_old_status = 'DOCUMENT_VERIFIED' and p_new_status in ('LIVENESS_VERIFIED', 'IDENTITY_VERIFIED', 'MANUAL_VERIFIED', 'INCONCLUSIVE', 'TECHNICAL_ERROR'))
      or (p_old_status = 'LIVENESS_VERIFIED' and p_new_status in ('IDENTITY_VERIFIED', 'MANUAL_VERIFIED', 'INCONCLUSIVE', 'TECHNICAL_ERROR'))
      or (p_old_status = 'INCONCLUSIVE' and p_new_status in ('SELF_DECLARED', 'CONTACT_VERIFIED', 'DOCUMENT_CAPTURED', 'DOCUMENT_VERIFIED', 'LIVENESS_VERIFIED', 'IDENTITY_VERIFIED', 'MANUAL_VERIFIED', 'TECHNICAL_ERROR'))
      or (p_old_status = 'TECHNICAL_ERROR' and p_new_status in ('SELF_DECLARED', 'CONTACT_VERIFIED', 'DOCUMENT_CAPTURED', 'DOCUMENT_VERIFIED', 'LIVENESS_VERIFIED', 'IDENTITY_VERIFIED', 'MANUAL_VERIFIED', 'INCONCLUSIVE'))

    when 'participant.background_status' then
      (p_old_status = 'NOT_REQUIRED' and p_new_status in ('NOT_STARTED', 'PENDING', 'EXPIRED'))
      or (p_old_status = 'NOT_STARTED' and p_new_status in ('PENDING', 'INCONCLUSIVE', 'PROVIDER_ERROR', 'EXPIRED'))
      or (p_old_status = 'PENDING' and p_new_status in ('NEGATIVE_CERTIFICATE', 'ADVERSE_INFORMATION_REVIEW', 'MANUAL_CONFIRMATION_REQUIRED', 'INCONCLUSIVE', 'PROVIDER_ERROR', 'EXPIRED'))
      or (p_old_status = 'INCONCLUSIVE' and p_new_status in ('PENDING', 'PROVIDER_ERROR', 'EXPIRED'))
      or (p_old_status = 'PROVIDER_ERROR' and p_new_status in ('PENDING', 'INCONCLUSIVE', 'EXPIRED'))

    when 'participant.network_status' then
      (p_old_status = 'NOT_ENABLED' and p_new_status in ('NO_ACTIVE_NETWORK_SIGNAL', 'NETWORK_REVALIDATION_REQUIRED', 'NETWORK_MANUAL_REVIEW_REQUIRED', 'NETWORK_CREDENTIAL_HOLD'))
      or (p_old_status = 'NO_ACTIVE_NETWORK_SIGNAL' and p_new_status in ('NETWORK_REVALIDATION_REQUIRED', 'NETWORK_MANUAL_REVIEW_REQUIRED', 'NETWORK_CREDENTIAL_HOLD', 'NETWORK_SIGNAL_EXPIRED', 'NETWORK_SIGNAL_REVOKED'))
      or (p_old_status = 'NETWORK_REVALIDATION_REQUIRED' and p_new_status in ('NO_ACTIVE_NETWORK_SIGNAL', 'NETWORK_MANUAL_REVIEW_REQUIRED', 'NETWORK_CREDENTIAL_HOLD', 'NETWORK_SIGNAL_EXPIRED', 'NETWORK_SIGNAL_REVOKED'))
      or (p_old_status = 'NETWORK_MANUAL_REVIEW_REQUIRED' and p_new_status in ('NO_ACTIVE_NETWORK_SIGNAL', 'NETWORK_REVALIDATION_REQUIRED', 'NETWORK_CREDENTIAL_HOLD', 'NETWORK_SIGNAL_EXPIRED', 'NETWORK_SIGNAL_REVOKED'))
      or (p_old_status = 'NETWORK_CREDENTIAL_HOLD' and p_new_status in ('NO_ACTIVE_NETWORK_SIGNAL', 'NETWORK_REVALIDATION_REQUIRED', 'NETWORK_MANUAL_REVIEW_REQUIRED', 'NETWORK_SIGNAL_EXPIRED', 'NETWORK_SIGNAL_REVOKED'))
      or (p_old_status = 'NETWORK_SIGNAL_EXPIRED' and p_new_status in ('NO_ACTIVE_NETWORK_SIGNAL', 'NETWORK_REVALIDATION_REQUIRED', 'NETWORK_MANUAL_REVIEW_REQUIRED', 'NETWORK_CREDENTIAL_HOLD'))
      or (p_old_status = 'NETWORK_SIGNAL_REVOKED' and p_new_status in ('NO_ACTIVE_NETWORK_SIGNAL', 'NETWORK_REVALIDATION_REQUIRED', 'NETWORK_MANUAL_REVIEW_REQUIRED', 'NETWORK_CREDENTIAL_HOLD'))

    when 'participant.eligibility_status' then
      (p_old_status = 'PENDING' and p_new_status in ('ELIGIBLE', 'REVIEW_REQUIRED', 'CORRECTION_REQUIRED', 'DENIED_MANUAL', 'CANCELLED', 'EXPIRED'))
      or (p_old_status = 'REVIEW_REQUIRED' and p_new_status in ('ELIGIBLE', 'CORRECTION_REQUIRED', 'DENIED_MANUAL', 'CANCELLED', 'EXPIRED'))
      or (p_old_status = 'CORRECTION_REQUIRED' and p_new_status in ('PENDING', 'ELIGIBLE', 'REVIEW_REQUIRED', 'DENIED_MANUAL', 'CANCELLED', 'EXPIRED'))
      or (p_old_status = 'ELIGIBLE' and p_new_status in ('REVIEW_REQUIRED', 'CANCELLED', 'EXPIRED'))

    when 'network.subject.status' then
      (p_old_status = 'ACTIVE' and p_new_status in ('UNDER_REVIEW', 'DISPUTED', 'MERGED', 'RETIRED'))
      or (p_old_status = 'UNDER_REVIEW' and p_new_status in ('ACTIVE', 'DISPUTED', 'MERGED', 'RETIRED'))
      or (p_old_status = 'DISPUTED' and p_new_status in ('ACTIVE', 'UNDER_REVIEW', 'MERGED', 'RETIRED'))

    when 'network.identifier.status' then
      p_old_status = 'ACTIVE' and p_new_status in ('REVOKED', 'EXPIRED')

    when 'network.link.status' then
      (p_old_status = 'ACTIVE' and p_new_status in ('DISPUTED', 'UNLINKED'))
      or (p_old_status = 'DISPUTED' and p_new_status in ('ACTIVE', 'UNLINKED'))

    when 'network.case.status' then
      (p_old_status = 'REPORTED' and p_new_status in ('TRIAGE', 'UNDER_REVIEW', 'SUBSTANTIATED', 'DISMISSED', 'CLOSED', 'EXPIRED'))
      or (p_old_status = 'TRIAGE' and p_new_status in ('UNDER_REVIEW', 'SUBSTANTIATED', 'DISMISSED', 'CLOSED', 'EXPIRED'))
      or (p_old_status = 'UNDER_REVIEW' and p_new_status in ('SUBSTANTIATED', 'DISMISSED', 'CLOSED', 'EXPIRED'))
      or (p_old_status = 'SUBSTANTIATED' and p_new_status in ('CLOSED', 'EXPIRED'))

    when 'network.signal.status' then
      (p_old_status = 'DRAFT' and p_new_status in ('UNDER_REVIEW', 'REJECTED', 'EXPIRED'))
      or (p_old_status = 'UNDER_REVIEW' and p_new_status in ('ACTIVE', 'REJECTED', 'EXPIRED'))
      or (p_old_status = 'ACTIVE' and p_new_status in ('SUSPENDED', 'REVOKED', 'EXPIRED'))
      or (p_old_status = 'SUSPENDED' and p_new_status in ('ACTIVE', 'REVOKED', 'EXPIRED'))

    when 'network.appeal.status' then
      (p_old_status = 'OPEN' and p_new_status in ('UNDER_REVIEW', 'CLOSED'))
      or (p_old_status = 'UNDER_REVIEW' and p_new_status in ('UPHELD', 'AMENDED', 'REVOKED', 'CLOSED'))

    else false
  end;
end;
$$;

create or replace function public.verified_access_validate_request_state_machine()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
begin
  if not public.verified_access_transition_allowed('request.status', old.status, new.status) then
    raise exception 'REQUEST_STATUS_TRANSITION_INVALID: % -> %', old.status, new.status
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

create or replace function public.verified_access_validate_slot_state_machine()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
begin
  if not public.verified_access_transition_allowed('slot.status', old.status, new.status) then
    raise exception 'SLOT_STATUS_TRANSITION_INVALID: % -> %', old.status, new.status
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

create or replace function public.verified_access_validate_participant_state_machines()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
begin
  if not public.verified_access_transition_allowed('participant.registration_status', old.registration_status, new.registration_status) then
    raise exception 'PARTICIPANT_REGISTRATION_STATUS_TRANSITION_INVALID: % -> %', old.registration_status, new.registration_status
      using errcode = 'P0001';
  end if;

  if not public.verified_access_transition_allowed('participant.identity_status', old.identity_status, new.identity_status) then
    raise exception 'PARTICIPANT_IDENTITY_STATUS_TRANSITION_INVALID: % -> %', old.identity_status, new.identity_status
      using errcode = 'P0001';
  end if;

  if not public.verified_access_transition_allowed('participant.background_status', old.background_status, new.background_status) then
    raise exception 'PARTICIPANT_BACKGROUND_STATUS_TRANSITION_INVALID: % -> %', old.background_status, new.background_status
      using errcode = 'P0001';
  end if;

  if not public.verified_access_transition_allowed('participant.network_status', old.network_status, new.network_status) then
    raise exception 'PARTICIPANT_NETWORK_STATUS_TRANSITION_INVALID: % -> %', old.network_status, new.network_status
      using errcode = 'P0001';
  end if;

  if not public.verified_access_transition_allowed('participant.eligibility_status', old.eligibility_status, new.eligibility_status) then
    raise exception 'PARTICIPANT_ELIGIBILITY_STATUS_TRANSITION_INVALID: % -> %', old.eligibility_status, new.eligibility_status
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

create or replace function public.verified_access_validate_network_subject_state_machine()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
begin
  if not public.verified_access_transition_allowed('network.subject.status', old.status, new.status) then
    raise exception 'NETWORK_SUBJECT_STATUS_TRANSITION_INVALID: % -> %', old.status, new.status
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

create or replace function public.verified_access_validate_network_identifier_state_machine()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
begin
  if not public.verified_access_transition_allowed('network.identifier.status', old.status, new.status) then
    raise exception 'NETWORK_IDENTIFIER_STATUS_TRANSITION_INVALID: % -> %', old.status, new.status
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

create or replace function public.verified_access_validate_network_link_state_machine()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
begin
  if not public.verified_access_transition_allowed('network.link.status', old.link_status, new.link_status) then
    raise exception 'NETWORK_LINK_STATUS_TRANSITION_INVALID: % -> %', old.link_status, new.link_status
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

create or replace function public.verified_access_validate_network_case_state_machine()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
begin
  if not public.verified_access_transition_allowed('network.case.status', old.status, new.status) then
    raise exception 'NETWORK_CASE_STATUS_TRANSITION_INVALID: % -> %', old.status, new.status
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

create or replace function public.verified_access_validate_network_signal_state_machine()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
begin
  if not public.verified_access_transition_allowed('network.signal.status', old.status, new.status) then
    raise exception 'NETWORK_SIGNAL_STATUS_TRANSITION_INVALID: % -> %', old.status, new.status
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

create or replace function public.verified_access_validate_network_appeal_state_machine()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
begin
  if not public.verified_access_transition_allowed('network.appeal.status', old.status, new.status) then
    raise exception 'NETWORK_APPEAL_STATUS_TRANSITION_INVALID: % -> %', old.status, new.status
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

drop trigger if exists verified_access_requests_validate_state_machine on public.verified_access_requests;
create trigger verified_access_requests_validate_state_machine
before update of status on public.verified_access_requests
for each row execute function public.verified_access_validate_request_state_machine();

drop trigger if exists verified_access_slots_validate_state_machine on public.verified_access_participant_slots;
create trigger verified_access_slots_validate_state_machine
before update of status on public.verified_access_participant_slots
for each row execute function public.verified_access_validate_slot_state_machine();

drop trigger if exists verified_access_participants_validate_state_machines on public.verified_access_participants;
create trigger verified_access_participants_validate_state_machines
before update of registration_status, identity_status, background_status, network_status, eligibility_status
on public.verified_access_participants
for each row execute function public.verified_access_validate_participant_state_machines();

drop trigger if exists verified_access_network_subjects_validate_state_machine on public.verified_access_network_subjects;
create trigger verified_access_network_subjects_validate_state_machine
before update of status on public.verified_access_network_subjects
for each row execute function public.verified_access_validate_network_subject_state_machine();

drop trigger if exists verified_access_network_identifiers_validate_state_machine on public.verified_access_network_subject_identifiers;
create trigger verified_access_network_identifiers_validate_state_machine
before update of status on public.verified_access_network_subject_identifiers
for each row execute function public.verified_access_validate_network_identifier_state_machine();

drop trigger if exists verified_access_network_links_validate_state_machine on public.verified_access_network_subject_links;
create trigger verified_access_network_links_validate_state_machine
before update of link_status on public.verified_access_network_subject_links
for each row execute function public.verified_access_validate_network_link_state_machine();

drop trigger if exists verified_access_network_cases_validate_state_machine on public.verified_access_network_security_cases;
create trigger verified_access_network_cases_validate_state_machine
before update of status on public.verified_access_network_security_cases
for each row execute function public.verified_access_validate_network_case_state_machine();

drop trigger if exists verified_access_network_signals_validate_state_machine on public.verified_access_network_signals;
create trigger verified_access_network_signals_validate_state_machine
before update of status on public.verified_access_network_signals
for each row execute function public.verified_access_validate_network_signal_state_machine();

drop trigger if exists verified_access_network_appeals_validate_state_machine on public.verified_access_network_appeals;
create trigger verified_access_network_appeals_validate_state_machine
before update of status on public.verified_access_network_appeals
for each row execute function public.verified_access_validate_network_appeal_state_machine();

revoke execute on function public.verified_access_transition_allowed(text, text, text) from public, anon, authenticated, service_role;
revoke execute on function public.verified_access_validate_request_state_machine() from public, anon, authenticated, service_role;
revoke execute on function public.verified_access_validate_slot_state_machine() from public, anon, authenticated, service_role;
revoke execute on function public.verified_access_validate_participant_state_machines() from public, anon, authenticated, service_role;
revoke execute on function public.verified_access_validate_network_subject_state_machine() from public, anon, authenticated, service_role;
revoke execute on function public.verified_access_validate_network_identifier_state_machine() from public, anon, authenticated, service_role;
revoke execute on function public.verified_access_validate_network_link_state_machine() from public, anon, authenticated, service_role;
revoke execute on function public.verified_access_validate_network_case_state_machine() from public, anon, authenticated, service_role;
revoke execute on function public.verified_access_validate_network_signal_state_machine() from public, anon, authenticated, service_role;
revoke execute on function public.verified_access_validate_network_appeal_state_machine() from public, anon, authenticated, service_role;
