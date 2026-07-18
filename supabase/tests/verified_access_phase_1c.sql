begin;

select no_plan();

select has_function('public', 'verified_access_transition_allowed', array['text', 'text', 'text'], 'transition helper exists');
select has_function('public', 'verified_access_validate_request_state_machine', array[]::text[], 'request state trigger function exists');
select has_function('public', 'verified_access_validate_slot_state_machine', array[]::text[], 'slot state trigger function exists');
select has_function('public', 'verified_access_validate_participant_state_machines', array[]::text[], 'participant state trigger function exists');
select has_function('public', 'verified_access_validate_policy_state_machine', array[]::text[], 'policy state trigger function exists');
select has_function('public', 'verified_access_create_policy_draft', array['uuid', 'jsonb', 'text', 'uuid', 'text'], 'create policy draft RPC exists');
select has_function('public', 'verified_access_activate_policy', array['uuid', 'uuid', 'text', 'text', 'text'], 'activate policy RPC exists');
select has_function('public', 'verified_access_retire_policy', array['uuid', 'uuid', 'text', 'text', 'text'], 'retire policy RPC exists');
select has_function('public', 'verified_access_write_audit_event', array['uuid', 'text', 'text', 'text', 'uuid', 'text', 'text', 'text', 'jsonb'], 'audit helper exists');
select has_function('public', 'verified_access_enqueue_outbox_event', array['uuid', 'text', 'uuid', 'text', 'text', 'jsonb'], 'outbox helper exists');

select ok(
  exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'verified_access_validate_request_state_machine',
        'verified_access_validate_slot_state_machine',
        'verified_access_validate_participant_state_machines',
        'verified_access_validate_network_subject_state_machine',
        'verified_access_validate_network_identifier_state_machine',
        'verified_access_validate_network_link_state_machine',
        'verified_access_validate_network_case_state_machine',
        'verified_access_validate_network_signal_state_machine',
        'verified_access_validate_network_appeal_state_machine'
      )
      and p.prosecdef = false
    having count(*) = 9
  ),
  'all state machine trigger functions are security invoker'
);

select ok(
  exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'verified_access_write_audit_event',
        'verified_access_enqueue_outbox_event',
        'verified_access_create_policy_draft',
        'verified_access_activate_policy',
        'verified_access_retire_policy'
      )
      and p.prosecdef = true
    having count(*) = 5
  ),
  'policy RPCs and audit/outbox helpers are security definer'
);

select is_empty(
  $$select 1
    from information_schema.role_routine_grants
    where specific_schema = 'public'
      and routine_name in (
        'verified_access_transition_allowed',
        'verified_access_validate_request_state_machine',
        'verified_access_validate_slot_state_machine',
        'verified_access_validate_participant_state_machines',
        'verified_access_validate_policy_state_machine',
        'verified_access_create_policy_draft',
        'verified_access_activate_policy',
        'verified_access_retire_policy',
        'verified_access_write_audit_event',
        'verified_access_enqueue_outbox_event'
      )
      and grantee in ('PUBLIC', 'anon', 'authenticated', 'service_role')$$,
  'no direct execute grants on Phase 1C functions for runtime roles'
);

select ok(
  public.verified_access_transition_allowed('request.status', 'DRAFT', 'INVITATIONS_PENDING'),
  'request DRAFT can move to INVITATIONS_PENDING'
);
select ok(
  not public.verified_access_transition_allowed('request.status', 'COMPLETED', 'IN_PROGRESS'),
  'request COMPLETED is final'
);
select ok(
  public.verified_access_transition_allowed('slot.status', 'OPEN', 'RESERVED'),
  'slot OPEN can move to RESERVED'
);
select ok(
  not public.verified_access_transition_allowed('slot.status', 'EXPIRED', 'OPEN'),
  'slot EXPIRED is final'
);
select ok(
  public.verified_access_transition_allowed('participant.registration_status', 'INVITED', 'SUBMITTED'),
  'participant registration can skip to SUBMITTED'
);
select ok(
  not public.verified_access_transition_allowed('participant.eligibility_status', 'DENIED_MANUAL', 'ELIGIBLE'),
  'manual denial is final'
);
select ok(
  public.verified_access_transition_allowed('network.signal.status', 'UNDER_REVIEW', 'ACTIVE'),
  'network signal can activate after review'
);
select ok(
  not public.verified_access_transition_allowed('network.case.status', 'DISMISSED', 'SUBSTANTIATED'),
  'dismissed case is final'
);
select ok(
  public.verified_access_transition_allowed('network.appeal.status', 'UNDER_REVIEW', 'AMENDED'),
  'appeal can resolve as amended'
);
select ok(
  not public.verified_access_transition_allowed('network.subject.status', 'MERGED', 'ACTIVE'),
  'merged subject is final'
);

select is(
  public.verified_access_policy_payload_allowed_keys(),
  array[
    'visitor_identity_mode',
    'service_identity_mode',
    'minimum_identity_assurance_level',
    'visitor_background_mode',
    'service_background_mode',
    'network_identity_mode',
    'network_signal_mode',
    'network_signal_min_severity',
    'network_signal_rules',
    'network_hold_enabled',
    'timezone',
    'invitation_ttl_minutes',
    'public_session_ttl_minutes',
    'max_visitor_participants',
    'max_service_participants',
    'max_request_duration_minutes',
    'min_notice_minutes',
    'max_notice_days',
    'allow_open_slots',
    'privacy_approval_reference',
    'background_approval_reference',
    'network_approval_reference',
    'retention_settings',
    'additional_settings'
  ],
  'p_policy allowlist is exact'
);

select lives_ok(
  $$select public.verified_access_validate_policy_payload('{"network_signal_rules":{},"allow_open_slots":true,"max_visitor_participants":4}'::jsonb)$$,
  'valid p_policy payload accepted'
);

select throws_ok(
  $$select public.verified_access_validate_policy_payload('{"status":"ACTIVE"}'::jsonb)$$,
  '22023',
  null,
  'server-controlled policy status rejected'
);

select throws_ok(
  $$select public.verified_access_validate_policy_payload('{"unexpected":true}'::jsonb)$$,
  '22023',
  null,
  'unknown p_policy key rejected'
);

select throws_ok(
  $$select public.verified_access_validate_policy_payload('{"network_signal_rules":[]}'::jsonb)$$,
  '22023',
  null,
  'network_signal_rules must be object'
);

select is_empty(
  $$select 1
    from information_schema.views
    where table_schema = 'public'
      and table_name like 'verified_access_%policy%'$$,
  'no Phase 1C policy views created'
);

select is_empty(
  $$select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname like 'verified_access%hmac%'$$,
  'no SQL HMAC helpers created'
);

select * from finish();

rollback;
