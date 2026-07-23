begin;
select no_plan();

select has_table('public', 'verified_access_public_sessions', 'public session table exists');
select has_table('public', 'verified_access_public_registration_commands', 'public command table exists');
select has_table('public', 'verified_access_public_rate_limits', 'public rate limit table exists');
select has_column('public', 'verified_access_public_sessions', 'session_token_hash', 'session persists only a token hash');
select has_column('public', 'verified_access_identity_profiles', 'guardian_name_ciphertext', 'guardian name is protected');
select has_column('public', 'verified_access_identity_profiles', 'privacy_notice_version', 'privacy notice version is persisted');

select ok((select bool_and(relrowsecurity) from pg_class where oid in (
  'public.verified_access_public_sessions'::regclass,
  'public.verified_access_public_registration_commands'::regclass,
  'public.verified_access_public_rate_limits'::regclass
)), 'all Phase 3B tables have RLS enabled');
select is_empty($$select 1 from pg_policy where polrelid in (
  'public.verified_access_public_sessions'::regclass,
  'public.verified_access_public_registration_commands'::regclass,
  'public.verified_access_public_rate_limits'::regclass
)$$, 'Phase 3B tables are default-deny');
select is_empty($$select 1 from information_schema.role_table_grants
where table_schema='public'
and table_name in ('verified_access_public_sessions','verified_access_public_registration_commands','verified_access_public_rate_limits')
and grantee in ('PUBLIC','anon','authenticated','service_role')$$, 'runtime roles have no Phase 3B table grants');

select has_function('public', 'verified_access_public_exchange_invitation', array['text','text','text','text','text','text','text'], 'exchange RPC exists');
select has_function('public', 'verified_access_public_get_registration', array['text','text','text'], 'get RPC exists');
select has_function('public', 'verified_access_public_start_registration', array['text','text','text','text','text'], 'start RPC exists');
select has_function('public', 'verified_access_public_submit_registration', array['text','text','text','text','text','bytea','bytea','text','bytea','text','bytea','text','bytea','bytea','text','boolean','bytea','bytea','text','text','integer','integer','text'], 'submit RPC exists');
select has_function('public', 'verified_access_public_registration_status', array['text','text','text'], 'status RPC exists');

select ok((select bool_and(p.prosecdef and p.proconfig @> array['search_path=public, pg_temp']::text[])
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname in (
    'verified_access_public_exchange_invitation','verified_access_public_get_registration',
    'verified_access_public_start_registration','verified_access_public_submit_registration',
    'verified_access_public_registration_status'
  )), 'public registration RPCs are security definer with fixed search_path');
select ok((select bool_and(
    not has_function_privilege('anon',p.oid,'EXECUTE')
    and not has_function_privilege('authenticated',p.oid,'EXECUTE')
    and has_function_privilege('service_role',p.oid,'EXECUTE')
    and not exists (
      select 1 from aclexplode(p.proacl) a
      where a.grantee = 0 and a.privilege_type = 'EXECUTE'
    )
  ) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname in (
    'verified_access_public_exchange_invitation','verified_access_public_get_registration',
    'verified_access_public_start_registration','verified_access_public_submit_registration',
    'verified_access_public_registration_status'
  )), 'only the Edge executor inherited by service_role reaches public RPCs');
select ok((select bool_and(
    not has_function_privilege('anon',p.oid,'EXECUTE')
    and not has_function_privilege('authenticated',p.oid,'EXECUTE')
    and not has_function_privilege('service_role',p.oid,'EXECUTE')
    and not exists (
      select 1 from aclexplode(p.proacl) a
      where a.grantee = 0 and a.privilege_type = 'EXECUTE'
    )
  ) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname like 'verified_access_phase3b_%'), 'Phase 3B helpers have no runtime EXECUTE');

select ok((select bool_and(
    not has_function_privilege('anon',p.oid,'EXECUTE')
    and not has_function_privilege('authenticated',p.oid,'EXECUTE')
    and not has_function_privilege('service_role',p.oid,'EXECUTE')
    and not exists (
      select 1 from aclexplode(p.proacl) a
      where a.grantee = 0 and a.privilege_type = 'EXECUTE'
    )
  ) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname in (
    'verified_access_resend_resident_invitation_phase3a',
    'verified_access_revoke_resident_invitation_phase3a'
  )), 'renamed Phase 3A implementations are internal only');
select ok((select pg_get_expr(i.indpred,i.indrelid) like '%OPENED%'
  from pg_index i where i.indexrelid='public.ux_verified_access_invitations_active_slot'::regclass),
  'active invitation uniqueness includes OPENED');

select throws_ok($$select public.verified_access_phase3b_assert_hash('raw-token','INVALID')$$, '22023', 'INVALID', 'raw tokens are rejected by hash-only RPC boundary');
select throws_ok($$select public.verified_access_phase3b_assert_command_input('short','valid-correlation')$$, '22023', 'PUBLIC_REGISTRATION_PAYLOAD_INVALID', 'short idempotency keys are rejected');
select ok(not exists(select 1 from public.condominium_features where feature_key='VERIFIED_ACCESS' and enabled), 'migration does not enable VERIFIED_ACCESS');
select is_empty($$select 1 from information_schema.columns where table_schema='public' and table_name='verified_access_public_sessions' and column_name not in ('id','condominium_id','request_id','invitation_id','participant_slot_id','session_token_hash','token_version','status','expires_at','started_at','last_seen_at','revoked_at','completed_at','created_at','updated_at')$$, 'session table contains no PII columns');

select * from finish();
rollback;
