begin;

select no_plan();

select has_table('public', 'verified_access_service_types', 'service catalog table exists');
select has_table('public', 'verified_access_condominium_service_types', 'condominium service catalog table exists');
select has_table('public', 'verified_access_policies', 'policies table exists');
select has_table('public', 'verified_access_requests', 'requests table exists');
select has_table('public', 'verified_access_service_request_details', 'service details table exists');
select has_table('public', 'verified_access_participant_slots', 'participant slots table exists');
select has_table('public', 'verified_access_identity_profiles', 'identity profiles table exists');
select has_table('public', 'verified_access_participants', 'participants table exists');
select has_table('public', 'verified_access_eligibility_evaluations', 'eligibility evaluations table exists');
select has_table('public', 'verified_access_outbox_events', 'outbox table exists');
select has_table('public', 'verified_access_audit_events', 'audit table exists');

select ok(to_regclass('public.verified_access_network_subjects') is null, 'no central network subjects table in phase 1A');
select ok(to_regclass('public.verified_access_network_signals') is null, 'no central network signals table in phase 1A');

select has_column('public', 'verified_access_policies', 'visitor_identity_mode', 'policy separates visitor identity mode');
select has_column('public', 'verified_access_policies', 'service_identity_mode', 'policy separates service identity mode');
select has_column('public', 'verified_access_policies', 'visitor_background_mode', 'policy separates visitor background mode');
select has_column('public', 'verified_access_policies', 'service_background_mode', 'policy separates service background mode');
select has_column('public', 'verified_access_policies', 'network_signal_min_severity', 'policy has network severity field');
select has_column('public', 'verified_access_policies', 'timezone', 'policy has timezone');
select has_column('public', 'verified_access_policies', 'invitation_ttl_minutes', 'policy has invitation ttl');
select has_column('public', 'verified_access_policies', 'public_session_ttl_minutes', 'policy has public session ttl');
select has_column('public', 'verified_access_policies', 'max_visitor_participants', 'policy has visitor participant limit');
select has_column('public', 'verified_access_policies', 'max_service_participants', 'policy has service participant limit');
select has_column('public', 'verified_access_policies', 'max_request_duration_minutes', 'policy has max request duration');
select has_column('public', 'verified_access_policies', 'min_notice_minutes', 'policy has min notice');
select has_column('public', 'verified_access_policies', 'max_notice_days', 'policy has max notice');
select has_column('public', 'verified_access_policies', 'allow_open_slots', 'policy has open slot toggle');
select has_column('public', 'verified_access_policies', 'privacy_approval_reference', 'policy has privacy approval reference');
select has_column('public', 'verified_access_policies', 'retention_settings', 'policy has retention settings object');
select has_column('public', 'verified_access_policies', 'additional_settings', 'policy has additional settings object');
select has_column('public', 'verified_access_policies', 'content_checksum', 'policy has content checksum');

select has_column('public', 'verified_access_identity_profiles', 'cpf_ciphertext', 'identity has cpf ciphertext');
select has_column('public', 'verified_access_identity_profiles', 'cpf_tenant_hmac', 'identity has local cpf hmac');
select has_column('public', 'verified_access_identity_profiles', 'document_type', 'identity has document type');
select has_column('public', 'verified_access_identity_profiles', 'document_number_ciphertext', 'identity has document ciphertext');
select has_column('public', 'verified_access_identity_profiles', 'document_number_tenant_hmac', 'identity has local document hmac');
select has_column('public', 'verified_access_identity_profiles', 'document_issuer_country_ciphertext', 'identity has issuer country ciphertext');
select has_column('public', 'verified_access_identity_profiles', 'phone_ciphertext', 'identity has phone ciphertext');
select has_column('public', 'verified_access_identity_profiles', 'phone_tenant_hmac', 'identity has local phone hmac');

select has_column('public', 'verified_access_requests', 'expires_at', 'request has expires_at');
select has_column('public', 'verified_access_requests', 'cancelled_at', 'request has cancelled_at');
select has_column('public', 'verified_access_requests', 'eligibility_expires_at', 'request has eligibility_expires_at');
select has_column('public', 'verified_access_requests', 'eligibility_reason_code', 'request has eligibility_reason_code');
select has_column('public', 'verified_access_eligibility_evaluations', 'actor_type', 'evaluation has actor_type');
select has_column('public', 'verified_access_eligibility_evaluations', 'actor_id', 'evaluation has actor_id');
select has_column('public', 'verified_access_eligibility_evaluations', 'trigger_event_type', 'evaluation has trigger event');
select has_column('public', 'verified_access_eligibility_evaluations', 'input_snapshot_sanitized', 'evaluation has sanitized input snapshot');

select ok(
  (select bool_and(c.relrowsecurity)
   from pg_class c
   join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relname like 'verified_access_%'
     and c.relkind = 'r'),
  'RLS is enabled on all verified_access tables'
);

select is_empty(
  $$select 1
    from pg_policy p
    join pg_class c on c.oid = p.polrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname like 'verified_access_%'
      and (
        pg_get_expr(p.polqual, p.polrelid) = 'true'
        or pg_get_expr(p.polwithcheck, p.polrelid) = 'true'
      )$$,
  'no permissive true RLS policies'
);

select is_empty(
  $$select 1
    from information_schema.role_table_grants
    where table_schema = 'public'
      and table_name like 'verified_access_%'
      and grantee in ('anon', 'authenticated', 'PUBLIC')$$,
  'no direct verified_access grants for public roles'
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
      ('authenticated')
  ) as roles(role_name)
  cross join (
    values
      ('verified_access_service_types'),
      ('verified_access_condominium_service_types'),
      ('verified_access_policies'),
      ('verified_access_requests'),
      ('verified_access_service_request_details'),
      ('verified_access_participant_slots'),
      ('verified_access_identity_profiles'),
      ('verified_access_participants'),
      ('verified_access_eligibility_evaluations'),
      ('verified_access_outbox_events'),
      ('verified_access_audit_events')
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

select is(
  has_table_privilege('service_role', format('public.%I', table_name), privilege_name),
  expected,
  format('service_role %s on %s = %s', privilege_name, table_name, expected)
)
from (
  values
    ('verified_access_service_types', true, true, true, false, false),
    ('verified_access_condominium_service_types', true, true, true, false, false),
    ('verified_access_policies', true, true, true, false, false),
    ('verified_access_requests', true, true, true, false, false),
    ('verified_access_service_request_details', true, true, true, false, false),
    ('verified_access_participant_slots', true, true, true, false, false),
    ('verified_access_identity_profiles', true, true, true, false, false),
    ('verified_access_participants', true, true, true, false, false),
    ('verified_access_eligibility_evaluations', true, true, false, false, false),
    ('verified_access_outbox_events', true, true, true, false, false),
    ('verified_access_audit_events', true, true, false, false, false)
) as grants(table_name, can_select, can_insert, can_update, can_delete, can_truncate)
cross join lateral (
  values
    ('SELECT', can_select),
    ('INSERT', can_insert),
    ('UPDATE', can_update),
    ('DELETE', can_delete),
    ('TRUNCATE', can_truncate)
) as privileges(privilege_name, expected);

select is_empty(
  $$select 1
    from information_schema.role_routine_grants
    where specific_schema = 'public'
      and routine_name like 'verified_access_%'
      and grantee in ('anon', 'authenticated', 'PUBLIC')$$,
  'no helper function grants for public roles'
);

select ok(to_regprocedure('public.verified_access_service_type_requires_description(uuid)') is null, 'cross-table CHECK helper was removed');

select ok(to_regprocedure('public.verified_access_validate_service_request_details()') is not null, 'service details trigger function exists');
select ok(to_regprocedure('public.verified_access_validate_service_type_requirement_change()') is not null, 'service type requirement change trigger function exists');
select ok(to_regprocedure('public.verified_access_validate_slot_capacity()') is not null, 'slot capacity trigger function exists');
select ok(to_regprocedure('public.verified_access_prevent_outbox_business_mutation()') is not null, 'outbox immutability trigger function exists');
select ok(to_regprocedure('public.verified_access_prevent_audit_mutation()') is not null, 'audit append-only trigger function exists');

select ok(
  exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'verified_access_service_types'
      and t.tgname = 'verified_access_service_types_validate_requirement_change'
      and not t.tgisinternal
  ),
  'service type requirement change trigger exists'
);

select ok(to_regclass('public.ux_verified_access_policies_id_condominium_version') is not null, 'policy id/tenant/version unique index exists');
select ok(to_regclass('public.ux_verified_access_slots_id_request_condominium') is not null, 'slot id/request/tenant unique index exists');
select ok(to_regclass('public.ux_verified_access_participants_id_request_condominium') is not null, 'participant id/request/tenant unique index exists');
select ok(to_regclass('public.ux_units_id_condominium_id') is not null, 'unit tenant helper index exists');
select ok(to_regclass('public.ux_user_profiles_id_condominium_id') is not null, 'user profile tenant helper index exists');
select ok(to_regclass('public.ux_verified_access_identity_profiles_phone_tenant_hmac') is null, 'old unique phone hmac index does not exist');
select ok(to_regclass('public.idx_verified_access_identity_profiles_phone_tenant_hmac') is not null, 'non-unique phone hmac lookup index exists');
select is(
  (
    select i.indisunique
    from pg_index i
    where i.indexrelid = 'public.idx_verified_access_identity_profiles_phone_tenant_hmac'::regclass
  ),
  false,
  'phone hmac lookup index is not unique'
);

select ok(exists (select 1 from pg_constraint where conname = 'verified_access_requests_policy_version_fk'), 'request policy version composite FK exists');
select ok(exists (select 1 from pg_constraint where conname = 'verified_access_participants_slot_request_tenant_fk'), 'participant slot/request composite FK exists');
select ok(exists (select 1 from pg_constraint where conname = 'verified_access_evaluations_participant_request_tenant_fk'), 'evaluation participant/request composite FK exists');
select ok(exists (select 1 from pg_constraint where conname = 'verified_access_evaluations_policy_version_fk'), 'evaluation policy version composite FK exists');
select ok(exists (select 1 from pg_constraint where conname = 'verified_access_policies_privacy_approval_check'), 'privacy approval check exists');

select isnt_empty(
  $$select 1
    from public.verified_access_service_types
    where code = 'OTHER'
      and requires_description = true$$,
  'OTHER service type is seeded and requires description'
);

select is_empty(
  $$select 1
    from public.condominium_features
    where feature_key in ('VERIFIED_ACCESS', 'VERIFIED_ACCESS_BACKGROUND_CHECK')
      and enabled = true$$,
  'verified access features are not enabled by migration'
);

select is_empty(
  $$select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name like 'verified_access_%'
      and data_type in ('text', 'character varying', 'date')
      and (
        column_name in ('cpf', 'full_name', 'normalized_name', 'birth_date', 'phone', 'mother_name', 'father_name', 'document_number', 'company_document')
        or column_name like '%plaintext%'
      )$$,
  'no forbidden plaintext sensitive columns'
);

select * from finish();

rollback;
