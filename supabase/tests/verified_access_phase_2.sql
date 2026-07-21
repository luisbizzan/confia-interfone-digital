begin;

select no_plan();

select has_table('public', 'verified_access_request_commands', 'Phase 2 command table exists');
select has_column('public', 'verified_access_request_commands', 'id', 'command has id');
select has_column('public', 'verified_access_request_commands', 'condominium_id', 'command has tenant');
select has_column('public', 'verified_access_request_commands', 'actor_user_id', 'command has actor');
select has_column('public', 'verified_access_request_commands', 'command_type', 'command has type');
select has_column('public', 'verified_access_request_commands', 'idempotency_key', 'command has idempotency key');
select has_column('public', 'verified_access_request_commands', 'input_fingerprint', 'command has fingerprint');
select has_column('public', 'verified_access_request_commands', 'request_id', 'command has request link');
select has_column('public', 'verified_access_request_commands', 'status', 'command has status');
select has_column('public', 'verified_access_request_commands', 'result_payload', 'command has sanitized result');
select has_column('public', 'verified_access_request_commands', 'completed_at', 'command has completion timestamp');

select ok(
  (select c.relrowsecurity from pg_class c where c.oid = 'public.verified_access_request_commands'::regclass),
  'command table has RLS enabled'
);
select is_empty(
  $$select 1 from pg_policy where polrelid = 'public.verified_access_request_commands'::regclass$$,
  'command table has no permissive policies'
);
select is_empty(
  $$select 1 from information_schema.role_table_grants
    where table_schema = 'public'
      and table_name = 'verified_access_request_commands'
      and grantee in ('PUBLIC', 'anon', 'authenticated', 'service_role')$$,
  'runtime roles have no direct command table grants'
);

select has_function('public', 'verified_access_list_resident_service_types', array['uuid'], 'catalog RPC exists');
select has_function('public', 'verified_access_create_resident_request', array['uuid','text','text','text','timestamp with time zone','timestamp with time zone','text','text','integer','text','text'], 'create RPC exists');
select has_function('public', 'verified_access_list_resident_requests', array['text','text','timestamp with time zone','timestamp with time zone','timestamp with time zone','uuid','integer'], 'list RPC exists');
select has_function('public', 'verified_access_get_resident_request', array['uuid'], 'get RPC exists');
select has_function('public', 'verified_access_cancel_resident_request', array['uuid','text','text','text'], 'cancel RPC exists');

select ok(
  (select bool_and(p.prosecdef and p.proconfig @> array['search_path=public, pg_temp']::text[])
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname in (
     'verified_access_list_resident_service_types',
     'verified_access_create_resident_request',
     'verified_access_list_resident_requests',
     'verified_access_get_resident_request',
     'verified_access_cancel_resident_request'
   )),
  'all five resident RPCs are security definer with fixed search_path'
);

select ok(
  (select bool_and(has_function_privilege('authenticated', p.oid, 'EXECUTE'))
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname in (
     'verified_access_list_resident_service_types',
     'verified_access_create_resident_request',
     'verified_access_list_resident_requests',
     'verified_access_get_resident_request',
     'verified_access_cancel_resident_request'
   )),
  'authenticated has only the technical EXECUTE path to resident RPCs'
);

select ok(
  (select bool_and(
     not has_function_privilege('anon', p.oid, 'EXECUTE')
     and not has_function_privilege('service_role', p.oid, 'EXECUTE')
     and not exists (
       select 1 from aclexplode(p.proacl) a
       where a.grantee = 0 and a.privilege_type = 'EXECUTE'
     )
   )
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname in (
     'verified_access_list_resident_service_types',
     'verified_access_create_resident_request',
     'verified_access_list_resident_requests',
     'verified_access_get_resident_request',
     'verified_access_cancel_resident_request'
   )),
  'anon and service_role cannot execute resident RPCs'
);

select ok(
  (select bool_and(
     not has_function_privilege('anon', p.oid, 'EXECUTE')
     and not has_function_privilege('authenticated', p.oid, 'EXECUTE')
     and not has_function_privilege('service_role', p.oid, 'EXECUTE')
     and not exists (
       select 1 from aclexplode(p.proacl) a
       where a.grantee = 0 and a.privilege_type = 'EXECUTE'
     )
   )
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname like 'verified_access_phase2_%'),
  'Phase 2 helpers have no runtime EXECUTE grants'
);

select ok(
  not exists (
    select 1 from public.condominium_features
    where feature_key = 'VERIFIED_ACCESS' and enabled is true
  ),
  'VERIFIED_ACCESS remains disabled after migrations'
);

select throws_ok(
  $$insert into public.verified_access_request_commands (
      condominium_id, actor_user_id, command_type, idempotency_key,
      input_fingerprint, status
    ) values (
      gen_random_uuid(), gen_random_uuid(), 'OTHER', '0123456789abcdef',
      'v1:' || repeat('a', 64), 'PROCESSING'
    )$$,
  '23503',
  null,
  'tenant FKs reject orphan commands before invalid taxonomies can persist'
);

select * from finish();
rollback;
