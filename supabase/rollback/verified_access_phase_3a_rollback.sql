begin;

revoke verified_access_phase3a_resident_executor from authenticated;

drop function if exists public.verified_access_list_resident_invitation_status(uuid);
drop function if exists public.verified_access_revoke_resident_invitation(uuid, text, text, text);
drop function if exists public.verified_access_resend_resident_invitation(uuid, text, text, text);
drop function if exists public.verified_access_issue_resident_invitation(uuid, text, text, text);
drop function if exists public.verified_access_phase3a_expire_slot_invitations(uuid, uuid, uuid, text);
drop function if exists public.verified_access_phase3a_validate_command_input(text, text);
drop function if exists public.verified_access_phase3a_assert_token_hash(text);

drop table if exists public.verified_access_invitation_commands;
drop table if exists public.verified_access_invitations;

drop role if exists verified_access_phase3a_resident_executor;

commit;
