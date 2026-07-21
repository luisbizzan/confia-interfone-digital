begin;
select no_plan();

select has_table('public', 'verified_access_invitations', 'invitation table exists');
select has_table('public', 'verified_access_invitation_commands', 'invitation command table exists');
select has_column('public', 'verified_access_invitations', 'token_hash', 'only the token hash is persisted');
select has_column('public', 'verified_access_invitations', 'participant_slot_id', 'invitation belongs to a slot');
select has_column('public', 'verified_access_invitations', 'expires_at', 'invitation has an expiry');

select ok((select relrowsecurity from pg_class where oid = 'public.verified_access_invitations'::regclass), 'invitation RLS is enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.verified_access_invitation_commands'::regclass), 'command RLS is enabled');
select is_empty($$select 1 from pg_policy where polrelid in ('public.verified_access_invitations'::regclass, 'public.verified_access_invitation_commands'::regclass)$$, 'Phase 3A tables have default-deny RLS');
select is_empty($$select 1 from information_schema.role_table_grants where table_schema='public' and table_name in ('verified_access_invitations','verified_access_invitation_commands') and grantee in ('PUBLIC','anon','authenticated','service_role')$$, 'runtime roles have no table grants');

select has_function('public', 'verified_access_issue_resident_invitation', array['uuid','text','text','text'], 'issue RPC exists');
select has_function('public', 'verified_access_resend_resident_invitation', array['uuid','text','text','text'], 'resend RPC exists');
select has_function('public', 'verified_access_revoke_resident_invitation', array['uuid','text','text','text'], 'revoke RPC exists');
select has_function('public', 'verified_access_list_resident_invitation_status', array['uuid'], 'status RPC exists');

select ok((select bool_and(p.prosecdef and p.proconfig @> array['search_path=public, pg_temp']::text[]) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('verified_access_issue_resident_invitation','verified_access_resend_resident_invitation','verified_access_revoke_resident_invitation','verified_access_list_resident_invitation_status')), 'RPCs are security definer with fixed search_path');
select ok((select bool_and(has_function_privilege('authenticated', p.oid, 'EXECUTE') and not has_function_privilege('anon', p.oid, 'EXECUTE') and not has_function_privilege('service_role', p.oid, 'EXECUTE')) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('verified_access_issue_resident_invitation','verified_access_resend_resident_invitation','verified_access_revoke_resident_invitation','verified_access_list_resident_invitation_status')), 'only authenticated can reach the Phase 3A RPCs');
select ok((select bool_and(not has_function_privilege('anon',p.oid,'EXECUTE') and not has_function_privilege('authenticated',p.oid,'EXECUTE') and not has_function_privilege('service_role',p.oid,'EXECUTE')) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'verified_access_phase3a_%'), 'helpers have no runtime EXECUTE');

select throws_ok($$select public.verified_access_phase3a_assert_token_hash('raw-token')$$, '22023', 'INVITATION_TOKEN_HASH_INVALID', 'raw or malformed token values are rejected');
select ok(not exists(select 1 from public.condominium_features where feature_key='VERIFIED_ACCESS' and enabled), 'migration does not enable VERIFIED_ACCESS');

select * from finish();
rollback;
