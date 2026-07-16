begin;

select no_plan();

select has_table('public', 'verified_access_network_subjects', 'network subjects table exists');
select has_table('public', 'verified_access_network_subject_identifiers', 'network identifiers table exists');
select has_table('public', 'verified_access_network_subject_links', 'network subject links table exists');
select has_table('public', 'verified_access_network_security_cases', 'network security cases table exists');
select has_table('public', 'verified_access_network_signals', 'network signals table exists');
select has_table('public', 'verified_access_network_signal_reviews', 'network signal reviews table exists');
select has_table('public', 'verified_access_network_appeals', 'network appeals table exists');

select has_column('public', 'verified_access_network_subjects', 'retention_until', 'subjects use canonical retention_until');
select has_column('public', 'verified_access_network_subject_identifiers', 'identifier_hmac', 'identifiers store HMAC only');
select has_column('public', 'verified_access_network_subject_links', 'link_reason', 'links use canonical link_reason');
select has_column('public', 'verified_access_network_subject_links', 'identity_assurance_level', 'links use canonical identity_assurance_level');
select has_column('public', 'verified_access_network_security_cases', 'reported_by_actor_type', 'cases store reporter actor type');
select has_column('public', 'verified_access_network_security_cases', 'reported_at', 'cases store reported_at');
select has_column('public', 'verified_access_network_security_cases', 'expired_at', 'cases store expired_at');
select has_column('public', 'verified_access_network_signals', 'proposed_by_actor_type', 'signals store proposer actor type');
select has_column('public', 'verified_access_network_signals', 'rejected_at', 'signals store rejected_at');
select has_column('public', 'verified_access_network_signals', 'expired_at', 'signals store expired_at');
select has_column('public', 'verified_access_network_signal_reviews', 'reviewer_actor_id', 'reviews require reviewer actor');
select has_column('public', 'verified_access_network_signal_reviews', 'reason_code', 'reviews use canonical reason_code');
select has_column('public', 'verified_access_network_appeals', 'resolved_by_actor_id', 'appeals store resolver actor');

select ok(exists (select 1 from pg_constraint where conname = 'verified_access_network_identifiers_type_check'), 'identifier type check exists');
select ok(exists (select 1 from pg_constraint where conname = 'verified_access_network_subjects_status_check'), 'subject status check exists');
select ok(exists (select 1 from pg_constraint where conname = 'verified_access_network_cases_source_type_check'), 'case source type check exists');
select ok(exists (select 1 from pg_constraint where conname = 'verified_access_network_cases_status_check'), 'case status check exists');
select ok(exists (select 1 from pg_constraint where conname = 'verified_access_network_cases_category_check'), 'case category check exists');
select ok(exists (select 1 from pg_constraint where conname = 'verified_access_network_signals_case_subject_fk'), 'signal case/subject composite FK exists');
select ok(exists (select 1 from pg_constraint where conname = 'verified_access_network_signals_category_check'), 'signal category check exists');
select ok(exists (select 1 from pg_constraint where conname = 'verified_access_network_signals_effect_check'), 'signal effect check exists');
select ok(exists (select 1 from pg_constraint where conname = 'verified_access_network_signals_status_check'), 'signal status check exists');
select ok(exists (select 1 from pg_constraint where conname = 'verified_access_network_reviews_decision_check'), 'review decision check exists');
select ok(exists (select 1 from pg_constraint where conname = 'verified_access_network_appeals_status_check'), 'appeal status check exists');

select ok(to_regclass('public.ux_verified_access_network_cases_id_subject') is not null, 'case id/subject unique index exists');
select ok(to_regclass('public.ux_verified_access_network_identifiers_active_hmac') is not null, 'active identifier HMAC unique index exists');
select ok(to_regclass('public.ux_verified_access_network_identifiers_primary_active') is not null, 'primary active identifier unique index exists');
select ok(to_regclass('public.ux_verified_access_network_links_active_profile') is not null, 'active profile link unique index exists');
select ok(to_regclass('public.ux_verified_access_network_reviews_signal_actor') is not null, 'review unique signal/actor index exists');
select ok(to_regclass('public.idx_verified_access_network_signals_active_actionable') is not null, 'active actionable signal index exists');

select ok(
  to_regprocedure('public.verified_access_network_validate_signal_source_case()') is not null,
  'signal source case validation trigger function exists'
);

select ok(
  exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'verified_access_network_signals'
      and t.tgname = 'verified_access_network_signals_validate_source_case'
      and not t.tgisinternal
  ),
  'signal source case validation trigger exists'
);

select is_empty(
  $$select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname like 'verified_access%hmac%'$$,
  'no verified access SQL HMAC helper exists'
);

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
  from (values ('anon'), ('authenticated'), ('service_role')) as roles(role_name)
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
  cross join (values ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE'), ('TRUNCATE')) as privileges(privilege_name)
) matrix;

select is_empty(
  $$select 1
    from information_schema.role_routine_grants
    where specific_schema = 'public'
      and routine_name = 'verified_access_network_validate_signal_source_case'
      and grantee in ('anon', 'authenticated', 'service_role', 'PUBLIC')$$,
  'no runtime execute grants on signal source validation function'
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

select * from finish();

rollback;
