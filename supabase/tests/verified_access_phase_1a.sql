begin;

do $$
declare
  v_missing_tables text[];
begin
  select array_agg(t.table_name order by t.table_name)
    into v_missing_tables
  from (
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
  ) as t(table_name)
  where to_regclass('public.' || t.table_name) is null;

  if v_missing_tables is not null then
    raise exception 'Missing verified access tables: %', v_missing_tables;
  end if;
end $$;

do $$
declare
  v_unprotected text[];
begin
  select array_agg(c.relname order by c.relname)
    into v_unprotected
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relkind = 'r'
    and c.relname like 'verified_access_%'
    and c.relrowsecurity is not true;

  if v_unprotected is not null then
    raise exception 'RLS not enabled on: %', v_unprotected;
  end if;
end $$;

do $$
declare
  v_bad_columns text[];
begin
  select array_agg(table_name || '.' || column_name order by table_name, column_name)
    into v_bad_columns
  from information_schema.columns
  where table_schema = 'public'
    and table_name like 'verified_access_%'
    and data_type in ('text', 'character varying', 'date')
    and (
      column_name in (
        'cpf',
        'full_name',
        'normalized_name',
        'birth_date',
        'phone',
        'mother_name',
        'father_name',
        'document_number',
        'company_document'
      )
      or column_name like '%plaintext%'
    );

  if v_bad_columns is not null then
    raise exception 'Plaintext sensitive columns found: %', v_bad_columns;
  end if;
end $$;

do $$
begin
  if exists (
    select 1
    from public.condominium_features
    where feature_key in ('VERIFIED_ACCESS', 'VERIFIED_ACCESS_BACKGROUND_CHECK')
      and enabled = true
  ) then
    raise exception 'Verified access feature unexpectedly enabled';
  end if;
end $$;

do $$
begin
  if not exists (
    select 1
    from public.verified_access_service_types
    where code = 'OTHER'
      and requires_description = true
  ) then
    raise exception 'OTHER service type must require description';
  end if;
end $$;

do $$
declare
  v_public_grants text[];
begin
  select array_agg(table_name || ':' || privilege_type order by table_name, privilege_type)
    into v_public_grants
  from information_schema.role_table_grants
  where table_schema = 'public'
    and table_name like 'verified_access_%'
    and grantee in ('anon', 'authenticated', 'PUBLIC')
    and privilege_type in ('INSERT', 'UPDATE', 'DELETE');

  if v_public_grants is not null then
    raise exception 'Direct write grants found: %', v_public_grants;
  end if;
end $$;

do $$
declare
  v_role_id uuid := '11111111-1111-1111-1111-111111111111';
  v_condo_a uuid := '11111111-aaaa-4000-8000-000000000001';
  v_condo_b uuid := '11111111-bbbb-4000-8000-000000000001';
  v_unit_a uuid := '22222222-aaaa-4000-8000-000000000001';
  v_unit_b uuid := '22222222-bbbb-4000-8000-000000000001';
  v_user_a uuid := '33333333-aaaa-4000-8000-000000000001';
  v_user_b uuid := '33333333-bbbb-4000-8000-000000000001';
  v_policy_a uuid := '44444444-aaaa-4000-8000-000000000001';
  v_policy_b uuid := '44444444-bbbb-4000-8000-000000000001';
  v_request_a uuid := '55555555-aaaa-4000-8000-000000000001';
  v_request_b uuid := '55555555-bbbb-4000-8000-000000000001';
  v_slot_a uuid := '66666666-aaaa-4000-8000-000000000001';
  v_slot_a_2 uuid := '66666666-aaaa-4000-8000-000000000002';
  v_slot_b uuid := '66666666-bbbb-4000-8000-000000000001';
  v_profile_a uuid := '77777777-aaaa-4000-8000-000000000001';
  v_profile_b uuid := '77777777-bbbb-4000-8000-000000000001';
  v_participant_a uuid := '88888888-aaaa-4000-8000-000000000001';
  v_participant_b uuid := '88888888-bbbb-4000-8000-000000000001';
  v_other_service_type uuid;
begin
  select id
    into v_other_service_type
  from public.verified_access_service_types
  where code = 'OTHER';

  if v_other_service_type is null then
    raise exception 'OTHER service type not found';
  end if;

  insert into public.roles (id, name)
  values (v_role_id, 'VERIFIED_ACCESS_TEST_ROLE')
  on conflict (name) do update
    set name = excluded.name
  returning id into v_role_id;

  insert into auth.users (
    id,
    instance_id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at
  )
  values
    (
      v_user_a,
      '00000000-0000-0000-0000-000000000000',
      'authenticated',
      'authenticated',
      'verified-access-a@example.invalid',
      '',
      now(),
      '{}'::jsonb,
      '{}'::jsonb,
      now(),
      now()
    ),
    (
      v_user_b,
      '00000000-0000-0000-0000-000000000000',
      'authenticated',
      'authenticated',
      'verified-access-b@example.invalid',
      '',
      now(),
      '{}'::jsonb,
      '{}'::jsonb,
      now(),
      now()
    )
  on conflict (id) do nothing;

  insert into public.condominiums (id, name, document)
  values
    (v_condo_a, 'Verified Access Test A', 'VA-A'),
    (v_condo_b, 'Verified Access Test B', 'VA-B')
  on conflict (id) do nothing;

  insert into public.units (id, condominium_id, type, block, number)
  values
    (v_unit_a, v_condo_a, 'APARTMENT', 'A', '101'),
    (v_unit_b, v_condo_b, 'APARTMENT', 'B', '202')
  on conflict (id) do nothing;

  insert into public.user_profiles (id, condominium_id, role_id)
  values
    (v_user_a, v_condo_a, v_role_id),
    (v_user_b, v_condo_b, v_role_id)
  on conflict (id) do update
    set condominium_id = excluded.condominium_id,
        role_id = excluded.role_id;

  insert into public.verified_access_policies (
    id,
    condominium_id,
    version,
    status,
    policy_content_checksum
  )
  values
    (v_policy_a, v_condo_a, 1, 'ACTIVE', repeat('a', 64)),
    (v_policy_b, v_condo_b, 1, 'ACTIVE', repeat('b', 64));

  insert into public.verified_access_requests (
    id,
    condominium_id,
    unit_id,
    requested_by_user_id,
    request_type,
    status,
    starts_at,
    ends_at,
    timezone,
    participant_limit,
    policy_id,
    policy_version
  )
  values
    (v_request_a, v_condo_a, v_unit_a, v_user_a, 'SERVICE_PROVIDER', 'DRAFT', now(), now() + interval '1 day', 'America/Sao_Paulo', 2, v_policy_a, 1),
    (v_request_b, v_condo_b, v_unit_b, v_user_b, 'VISITOR', 'DRAFT', now(), now() + interval '1 day', 'America/Sao_Paulo', 1, v_policy_b, 1);

  insert into public.verified_access_participant_slots (id, condominium_id, request_id, slot_number)
  values
    (v_slot_a, v_condo_a, v_request_a, 1),
    (v_slot_a_2, v_condo_a, v_request_a, 2),
    (v_slot_b, v_condo_b, v_request_b, 1);

  insert into public.verified_access_identity_profiles (
    id,
    condominium_id,
    full_name_ciphertext,
    full_name_hmac,
    tenant_subject_hmac,
    encryption_key_version,
    hmac_key_version
  )
  values
    (v_profile_a, v_condo_a, '\x01'::bytea, repeat('a', 32), repeat('a', 32), 1, 1),
    (v_profile_b, v_condo_b, '\x02'::bytea, repeat('b', 32), repeat('b', 32), 1, 1);

  insert into public.verified_access_participants (
    id,
    condominium_id,
    request_id,
    slot_id,
    identity_profile_id,
    registration_status,
    identity_status,
    background_status,
    network_status,
    eligibility_status
  )
  values
    (v_participant_a, v_condo_a, v_request_a, v_slot_a, v_profile_a, 'SUBMITTED', 'SELF_DECLARED', 'NOT_REQUIRED', 'NOT_ENABLED', 'PENDING'),
    (v_participant_b, v_condo_b, v_request_b, v_slot_b, v_profile_b, 'SUBMITTED', 'SELF_DECLARED', 'NOT_REQUIRED', 'NOT_ENABLED', 'PENDING');

  insert into public.verified_access_eligibility_evaluations (
    condominium_id,
    request_id,
    participant_id,
    policy_id,
    policy_version,
    input_identity_status,
    input_background_status,
    input_network_status,
    outcome,
    decision_source,
    metadata
  )
  values (
    v_condo_a,
    v_request_a,
    v_participant_a,
    v_policy_a,
    1,
    'SELF_DECLARED',
    'NOT_REQUIRED',
    'NOT_ENABLED',
    'REVIEW_REQUIRED',
    'SYSTEM_RULES',
    '{"reason":"fixture"}'::jsonb
  );

  begin
    insert into public.verified_access_policies (
      condominium_id,
      version,
      policy_content_checksum,
      network_signal_rules
    )
    values (
      v_condo_a,
      2,
      repeat('c', 64),
      '[{"effect":"AUTO_DENY_NETWORK"}]'::jsonb
    );

    raise exception 'AUTO_DENY_NETWORK should have failed';
  exception
    when check_violation then
      null;
  end;

  begin
    insert into public.verified_access_requests (
      condominium_id,
      unit_id,
      requested_by_user_id,
      request_type,
      starts_at,
      ends_at,
      timezone,
      participant_limit,
      policy_id,
      policy_version
    )
    values (
      v_condo_a,
      v_unit_b,
      v_user_a,
      'VISITOR',
      now(),
      now() + interval '1 day',
      'America/Sao_Paulo',
      1,
      v_policy_a,
      1
    );

    raise exception 'Cross-condominium unit should have failed';
  exception
    when foreign_key_violation then
      null;
  end;

  begin
    insert into public.verified_access_requests (
      condominium_id,
      unit_id,
      requested_by_user_id,
      request_type,
      starts_at,
      ends_at,
      timezone,
      participant_limit,
      policy_id,
      policy_version
    )
    values (
      v_condo_a,
      v_unit_a,
      v_user_b,
      'VISITOR',
      now(),
      now() + interval '1 day',
      'America/Sao_Paulo',
      1,
      v_policy_a,
      1
    );

    raise exception 'Cross-condominium requester should have failed';
  exception
    when foreign_key_violation then
      null;
  end;

  begin
    insert into public.verified_access_requests (
      condominium_id,
      unit_id,
      requested_by_user_id,
      request_type,
      starts_at,
      ends_at,
      timezone,
      participant_limit,
      policy_id,
      policy_version
    )
    values (
      v_condo_a,
      v_unit_a,
      v_user_a,
      'VISITOR',
      now(),
      now() + interval '1 day',
      'America/Sao_Paulo',
      1,
      v_policy_b,
      1
    );

    raise exception 'Cross-condominium policy should have failed';
  exception
    when foreign_key_violation then
      null;
  end;

  begin
    insert into public.verified_access_requests (
      condominium_id,
      unit_id,
      requested_by_user_id,
      request_type,
      starts_at,
      ends_at,
      timezone,
      participant_limit,
      policy_id,
      policy_version
    )
    values (
      v_condo_a,
      v_unit_a,
      v_user_a,
      'VISITOR',
      now() + interval '1 day',
      now(),
      'America/Sao_Paulo',
      1,
      v_policy_a,
      1
    );

    raise exception 'Invalid request period should have failed';
  exception
    when check_violation then
      null;
  end;

  begin
    insert into public.verified_access_requests (
      condominium_id,
      unit_id,
      requested_by_user_id,
      request_type,
      starts_at,
      ends_at,
      timezone,
      participant_limit,
      policy_id,
      policy_version
    )
    values (
      v_condo_a,
      v_unit_a,
      v_user_a,
      'VISITOR',
      now(),
      now() + interval '1 day',
      'America/Sao_Paulo',
      0,
      v_policy_a,
      1
    );

    raise exception 'Invalid participant limit should have failed';
  exception
    when check_violation then
      null;
  end;

  begin
    insert into public.verified_access_service_request_details (
      request_id,
      condominium_id,
      service_type_id
    )
    values (
      v_request_a,
      v_condo_a,
      v_other_service_type
    );

    raise exception 'OTHER without description should have failed';
  exception
    when check_violation then
      null;
  end;

  begin
    insert into public.verified_access_participant_slots (
      condominium_id,
      request_id,
      slot_number
    )
    values (
      v_condo_a,
      v_request_a,
      1
    );

    raise exception 'Duplicate slot number should have failed';
  exception
    when unique_violation then
      null;
  end;

  begin
    insert into public.verified_access_participants (
      condominium_id,
      request_id,
      slot_id,
      identity_profile_id
    )
    values (
      v_condo_a,
      v_request_a,
      v_slot_a_2,
      v_profile_b
    );

    raise exception 'Cross-condominium identity profile should have failed';
  exception
    when foreign_key_violation then
      null;
  end;

  begin
    insert into public.verified_access_eligibility_evaluations (
      condominium_id,
      request_id,
      participant_id,
      policy_id,
      policy_version,
      input_identity_status,
      input_background_status,
      input_network_status,
      outcome,
      decision_source
    )
    values (
      v_condo_a,
      v_request_a,
      v_participant_b,
      v_policy_a,
      1,
      'SELF_DECLARED',
      'NOT_REQUIRED',
      'NOT_ENABLED',
      'REVIEW_REQUIRED',
      'SYSTEM_RULES'
    );

    raise exception 'Cross-condominium participant evaluation should have failed';
  exception
    when foreign_key_violation then
      null;
  end;

  insert into public.verified_access_outbox_events (
    condominium_id,
    aggregate_type,
    aggregate_id,
    event_type,
    deduplication_key,
    payload
  )
  values (
    v_condo_a,
    'REQUEST',
    v_request_a,
    'REQUEST_CREATED',
    'verified-access-test-dedup',
    '{"event":"created"}'::jsonb
  );

  begin
    insert into public.verified_access_outbox_events (
      condominium_id,
      aggregate_type,
      aggregate_id,
      event_type,
      deduplication_key,
      payload
    )
    values (
      v_condo_a,
      'REQUEST',
      v_request_a,
      'REQUEST_CREATED',
      'verified-access-test-dedup',
      '{"event":"created-again"}'::jsonb
    );

    raise exception 'Duplicate outbox deduplication key should have failed';
  exception
    when unique_violation then
      null;
  end;

  begin
    insert into public.verified_access_outbox_events (
      condominium_id,
      aggregate_type,
      aggregate_id,
      event_type,
      deduplication_key,
      payload
    )
    values (
      v_condo_a,
      'REQUEST',
      v_request_a,
      'REQUEST_CREATED',
      'verified-access-token-test',
      '{"token":"secret"}'::jsonb
    );

    raise exception 'Outbox token payload should have failed';
  exception
    when check_violation then
      null;
  end;

  begin
    insert into public.verified_access_audit_events (
      condominium_id,
      aggregate_type,
      aggregate_id,
      event_type,
      metadata
    )
    values (
      v_condo_a,
      'REQUEST',
      v_request_a,
      'REQUEST_CREATED',
      '{"cpf":"00000000000"}'::jsonb
    );

    raise exception 'Audit PII payload should have failed';
  exception
    when check_violation then
      null;
  end;

  insert into public.verified_access_audit_events (
    id,
    condominium_id,
    aggregate_type,
    aggregate_id,
    event_type,
    metadata
  )
  values (
    '99999999-aaaa-4000-8000-000000000001',
    v_condo_a,
    'REQUEST',
    v_request_a,
    'REQUEST_CREATED',
    '{"event":"created"}'::jsonb
  );

  begin
    update public.verified_access_audit_events
    set metadata = '{"event":"mutated"}'::jsonb
    where id = '99999999-aaaa-4000-8000-000000000001';

    raise exception 'Audit update should have failed';
  exception
    when raise_exception then
      null;
  end;

  begin
    delete from public.verified_access_audit_events
    where id = '99999999-aaaa-4000-8000-000000000001';

    raise exception 'Audit delete should have failed';
  exception
    when raise_exception then
      null;
  end;
end $$;

rollback;
