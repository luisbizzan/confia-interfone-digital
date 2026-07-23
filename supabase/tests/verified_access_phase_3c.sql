begin;
select no_plan();

select has_table(
  'public',
  'verified_access_maintenance_findings',
  'Phase 3C maintenance findings table exists'
);

select ok(
  (
    select relrowsecurity
    from pg_class
    where oid = 'public.verified_access_maintenance_findings'::regclass
  ),
  'maintenance findings have RLS enabled'
);

select is_empty(
  $$select 1
    from pg_policy
    where polrelid = 'public.verified_access_maintenance_findings'::regclass$$,
  'maintenance findings are default-deny'
);

select is_empty(
  $$select 1
    from information_schema.role_table_grants
    where table_schema = 'public'
      and table_name = 'verified_access_maintenance_findings'
      and grantee in ('PUBLIC', 'anon', 'authenticated', 'service_role')$$,
  'runtime roles have no maintenance findings grants'
);

select has_function(
  'public',
  'verified_access_expire_invitations',
  array['integer', 'boolean', 'text'],
  'invitation expiration job exists'
);
select has_function(
  'public',
  'verified_access_expire_public_sessions',
  array['integer', 'boolean', 'text'],
  'public-session expiration job exists'
);
select has_function(
  'public',
  'verified_access_purge_public_commands',
  array['integer', 'boolean', 'text'],
  'public-command purge job exists'
);
select has_function(
  'public',
  'verified_access_purge_rate_limit_buckets',
  array['integer', 'boolean', 'text'],
  'rate-limit purge job exists'
);
select has_function(
  'public',
  'verified_access_reconcile_public_registration_state',
  array['integer', 'boolean', 'text'],
  'reconciliation job exists'
);
select has_function(
  'public',
  'verified_access_process_outbox',
  array['integer', 'boolean', 'text'],
  'outbox processing job exists'
);
select has_function(
  'public',
  'verified_access_apply_retention_policy',
  array['integer', 'boolean', 'text'],
  'retention job exists'
);

select ok(
  (
    select bool_and(
      p.prosecdef
      and p.proconfig @> array['search_path=public, pg_temp']::text[]
    )
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'verified_access_expire_invitations',
        'verified_access_expire_public_sessions',
        'verified_access_purge_public_commands',
        'verified_access_purge_rate_limit_buckets',
        'verified_access_reconcile_public_registration_state',
        'verified_access_process_outbox',
        'verified_access_apply_retention_policy'
      )
  ),
  'maintenance jobs are security definer with fixed search_path'
);

select ok(
  (
    select bool_and(
      not has_function_privilege('anon', p.oid, 'EXECUTE')
      and not has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and has_function_privilege('service_role', p.oid, 'EXECUTE')
      and not exists (
        select 1
        from aclexplode(p.proacl) acl
        where acl.grantee = 0 and acl.privilege_type = 'EXECUTE'
      )
    )
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'verified_access_expire_invitations',
        'verified_access_expire_public_sessions',
        'verified_access_purge_public_commands',
        'verified_access_purge_rate_limit_buckets',
        'verified_access_reconcile_public_registration_state',
        'verified_access_process_outbox',
        'verified_access_apply_retention_policy'
      )
  ),
  'only the maintenance executor inherited by service_role reaches jobs'
);

select ok(
  (
    select bool_and(
      not p.prosecdef
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
      and not has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and not has_function_privilege('service_role', p.oid, 'EXECUTE')
      and not exists (
        select 1
        from aclexplode(p.proacl) acl
        where acl.grantee = 0 and acl.privilege_type = 'EXECUTE'
      )
    )
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'verified_access_phase3c_assert_job_input',
        'verified_access_phase3c_record_finding',
        'verified_access_phase3c_result'
      )
  ),
  'Phase 3C helpers are security invoker and private'
);

select throws_ok(
  $$select public.verified_access_expire_invitations(0, true, 'phase3c-test')$$,
  '22023',
  'MAINTENANCE_BATCH_SIZE_INVALID',
  'zero batch size is rejected'
);
select throws_ok(
  $$select public.verified_access_expire_invitations(501, true, 'phase3c-test')$$,
  '22023',
  'MAINTENANCE_BATCH_SIZE_INVALID',
  'oversized batch is rejected'
);
select throws_ok(
  $$select public.verified_access_expire_invitations(1, null, 'phase3c-test')$$,
  '22023',
  'MAINTENANCE_DRY_RUN_INVALID',
  'null dry-run cannot become a write'
);
select throws_ok(
  $$select public.verified_access_expire_invitations(1, true, 'bad')$$,
  '22023',
  'MAINTENANCE_CORRELATION_ID_INVALID',
  'short correlation ID is rejected'
);

select ok(
  not exists (
    select 1
    from public.condominium_features
    where feature_key in (
      'VERIFIED_ACCESS',
      'VERIFIED_ACCESS_BACKGROUND_CHECK'
    )
      and enabled
  ),
  'Phase 3C migration enables no feature'
);

select is_empty(
  $$select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'verified_access_maintenance_findings'
      and column_name ~ '(name|phone|email|document|token|cpf|birth|address|payload|metadata)'$$,
  'maintenance findings contain no PII or free-form payload columns'
);

select * from finish();
rollback;
