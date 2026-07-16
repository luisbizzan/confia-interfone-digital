begin;

select no_plan();

select has_table('public', 'verified_access_network_subjects', 'network subjects table exists');
select has_table('public', 'verified_access_network_subject_identifiers', 'network identifiers table exists');
select has_table('public', 'verified_access_network_subject_links', 'network subject links table exists');
select has_table('public', 'verified_access_network_security_cases', 'network security cases table exists');
select has_table('public', 'verified_access_network_signals', 'network signals table exists');
select has_table('public', 'verified_access_network_signal_reviews', 'network signal reviews table exists');
select has_table('public', 'verified_access_network_appeals', 'network appeals table exists');

select has_column('public', 'verified_access_network_subjects', 'identity_assurance_level', 'subjects have identity assurance');
select has_column('public', 'verified_access_network_subject_identifiers', 'identifier_hmac', 'identifiers store HMAC only');
select has_column('public', 'verified_access_network_subject_links', 'identity_profile_id', 'links target local identity profiles');
select has_column('public', 'verified_access_network_security_cases', 'metadata_sanitized', 'cases store sanitized metadata');
select has_column('public', 'verified_access_network_signals', 'effect', 'signals have explicit effect');
select has_column('public', 'verified_access_network_signal_reviews', 'decision', 'reviews store decisions');
select has_column('public', 'verified_access_network_appeals', 'request_reference_hash', 'appeals store hashed request reference');

select ok(exists (select 1 from pg_constraint where conname = 'verified_access_network_identifiers_type_check'), 'identifier type check exists');
select ok(exists (select 1 from pg_constraint where conname = 'verified_access_network_links_profile_tenant_fk'), 'profile tenant FK exists');
select ok(exists (select 1 from pg_constraint where conname = 'verified_access_network_cases_source_participant_fk'), 'case source participant tenant FK exists');
select ok(exists (select 1 from pg_constraint where conname = 'verified_access_network_cases_metadata_sanitized_check'), 'case sanitized metadata check exists');
select ok(exists (select 1 from pg_constraint where conname = 'verified_access_network_signals_effect_check'), 'signal effect check exists');
select ok(exists (select 1 from pg_constraint where conname = 'verified_access_network_signals_window_check'), 'signal validity window check exists');
select ok(exists (select 1 from pg_constraint where conname = 'verified_access_network_appeals_resolution_check'), 'appeal resolution check exists');

select ok(to_regclass('public.ux_verified_access_network_identifiers_active_hmac') is not null, 'active identifier HMAC unique index exists');
select ok(to_regclass('public.ux_verified_access_network_identifiers_primary_active') is not null, 'primary active identifier unique index exists');
select ok(to_regclass('public.ux_verified_access_network_links_active_profile') is not null, 'active profile link unique index exists');
select ok(to_regclass('public.idx_verified_access_network_signals_active_actionable') is not null, 'active actionable signal index exists');
select ok(to_regclass('public.idx_verified_access_network_cases_source_condominium') is not null, 'source condominium case index exists');
select ok(to_regclass('public.idx_verified_access_network_appeals_review_due') is not null, 'appeal due index exists');

select ok(
  (select bool_and(c.relrowsecurity)
   from pg_class c
   join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relname in (
       'verified_access_network_subjects',
       'verified_access_network_subject_identifiers',
       'verified_access_network_subject_links',
       'verified_access_network_security_cases',
       'verified_access_network_signals',
       'verified_access_network_signal_reviews',
       'verified_access_network_appeals'
     )
     and c.relkind = 'r'),
  'RLS is enabled on all Phase 1B central tables'
);

select is_empty(
  $$select 1
    from pg_policy p
    join pg_class c on c.oid = p.polrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname like 'verified_access_network_%'$$,
  'no RLS policies exist for central network tables'
);

select ok(
  not has_table_privilege(role_name, format('public.%I', table_name), privilege_name),
  format('%s has no direct %s on %s', role_name, privilege_name, table_name)
)
from (
  select *
  from (
    values
      ('anon'),
      ('authenticated'),
      ('service_role')
  ) as roles(role_name)
  cross join (
    values
      ('verified_access_network_subjects'),
      ('verified_access_network_subject_identifiers'),
      ('verified_access_network_subject_links'),
      ('verified_access_network_security_cases'),
      ('verified_access_network_signals'),
      ('verified_access_network_signal_reviews'),
      ('verified_access_network_appeals')
  ) as tables(table_name)
  cross join (
    values
      ('SELECT'),
      ('INSERT'),
      ('UPDATE'),
      ('DELETE'),
      ('TRUNCATE')
  ) as privileges(privilege_name)
) matrix;

select is_empty(
  $$select 1
    from information_schema.role_table_grants
    where table_schema = 'public'
      and table_name like 'verified_access_network_%'
      and grantee in ('anon', 'authenticated', 'service_role', 'PUBLIC')$$,
  'no direct central network grants for runtime roles'
);

select is_empty(
  $$select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname like 'verified_access_network_%'$$,
  'no central network SQL functions were created'
);

select is_empty(
  $$select 1
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname like 'verified_access_network_%'
      and not t.tgisinternal$$,
  'no central network triggers were created'
);

select is_empty(
  $$select 1
    from information_schema.views
    where table_schema = 'public'
      and table_name like 'verified_access_network_%'$$,
  'no central network views were created'
);

select is_empty(
  $$select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name like 'verified_access_network_%'
      and (
        column_name in (
          'cpf',
          'phone',
          'email',
          'full_name',
          'normalized_name',
          'birth_date',
          'mother_name',
          'father_name',
          'document_number',
          'face_template',
          'biometric_template'
        )
        or column_name like '%ciphertext%'
        or column_name like '%plaintext%'
      )$$,
  'central network tables contain no civil PII, ciphertext or plaintext columns'
);

select is_empty(
  $$select 1
    from public.condominium_features
    where feature_key in (
        'VERIFIED_ACCESS_NETWORK_IDENTITY',
        'VERIFIED_ACCESS_NETWORK_SIGNALS',
        'VERIFIED_ACCESS_NETWORK_HOLD'
      )
      and enabled is true$$,
  'network feature flags are not enabled by migration'
);

select ok(to_regclass('public.verified_access_network_subject_operational_cases') is null, 'no operational subject case table exists');
select ok(to_regclass('public.verified_access_network_subject_search') is null, 'no network search table exists');
select ok(to_regprocedure('public.verified_access_network_hmac(text)') is null, 'no SQL HMAC helper exists');

select * from finish();

rollback;
