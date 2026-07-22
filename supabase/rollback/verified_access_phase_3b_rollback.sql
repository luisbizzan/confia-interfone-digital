begin;

revoke verified_access_phase3b_public_executor from service_role;

revoke execute on function public.verified_access_resend_resident_invitation(uuid, text, text, text)
  from verified_access_phase3a_resident_executor;
revoke execute on function public.verified_access_revoke_resident_invitation(uuid, text, text, text)
  from verified_access_phase3a_resident_executor;
drop function if exists public.verified_access_resend_resident_invitation(uuid, text, text, text);
drop function if exists public.verified_access_revoke_resident_invitation(uuid, text, text, text);
alter function public.verified_access_resend_resident_invitation_phase3a(uuid, text, text, text)
  rename to verified_access_resend_resident_invitation;
alter function public.verified_access_revoke_resident_invitation_phase3a(uuid, text, text, text)
  rename to verified_access_revoke_resident_invitation;
grant execute on function public.verified_access_resend_resident_invitation(uuid, text, text, text)
  to verified_access_phase3a_resident_executor;
grant execute on function public.verified_access_revoke_resident_invitation(uuid, text, text, text)
  to verified_access_phase3a_resident_executor;

drop index public.ux_verified_access_invitations_active_slot;
create unique index ux_verified_access_invitations_active_slot
on public.verified_access_invitations(participant_slot_id)
where status in ('PENDING', 'SENT');

drop trigger if exists verified_access_invitations_invalidate_public_sessions
  on public.verified_access_invitations;
drop trigger if exists verified_access_public_sessions_validate_transition
  on public.verified_access_public_sessions;

drop function if exists public.verified_access_public_registration_status(text, text, text);
drop function if exists public.verified_access_public_submit_registration(
  text, text, text, text, text, bytea, bytea, text, bytea, text, bytea,
  text, bytea, bytea, text, boolean, bytea, bytea, text, text, integer,
  integer, text
);
drop function if exists public.verified_access_public_start_registration(text, text, text, text, text);
drop function if exists public.verified_access_public_get_registration(text, text, text);
drop function if exists public.verified_access_public_exchange_invitation(text, text, text, text, text, text, text);

drop function if exists public.verified_access_phase3b_invalidate_sessions_for_invitation();
drop function if exists public.verified_access_phase3b_validate_session_transition();
drop function if exists public.verified_access_phase3b_rate_limit(text, text, integer, interval, uuid);
drop function if exists public.verified_access_phase3b_assert_command_input(text, text);
drop function if exists public.verified_access_phase3b_assert_hash(text, text);

drop table if exists public.verified_access_public_registration_commands;
drop table if exists public.verified_access_public_rate_limits;
drop table if exists public.verified_access_public_sessions;

alter table public.verified_access_identity_profiles
  drop constraint if exists verified_access_identity_profiles_guardian_key_check,
  drop constraint if exists verified_access_identity_profiles_registration_bundle_check,
  drop column if exists submitted_at,
  drop column if exists acknowledged_at,
  drop column if exists terms_version,
  drop column if exists privacy_notice_version,
  drop column if exists guardian_relationship_ciphertext,
  drop column if exists guardian_name_ciphertext,
  drop column if exists is_minor;

drop role if exists verified_access_phase3b_public_executor;

commit;
