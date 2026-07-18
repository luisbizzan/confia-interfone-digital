create or replace function public.verified_access_policy_payload_allowed_keys()
returns text[]
language sql
security invoker
set search_path = public, pg_temp
as $$
  select array[
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
  ];
$$;

create or replace function public.verified_access_validate_policy_payload(p_policy jsonb)
returns void
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_key text;
  v_allowed text[] := public.verified_access_policy_payload_allowed_keys();
  v_controlled text[] := array[
    'id',
    'condominium_id',
    'version',
    'schema_version',
    'status',
    'content_checksum',
    'created_by_actor_type',
    'created_by_actor_id',
    'approved_by_actor_id',
    'approved_at',
    'activated_by_actor_id',
    'activated_at',
    'retired_at',
    'created_at',
    'updated_at',
    'actor',
    'actor_id'
  ];
begin
  if p_policy is null or jsonb_typeof(p_policy) <> 'object' then
    raise exception 'POLICY_PAYLOAD_INVALID: p_policy must be a JSON object'
      using errcode = '22023';
  end if;

  for v_key in select jsonb_object_keys(p_policy)
  loop
    if v_key = any(v_controlled) then
      raise exception 'POLICY_PAYLOAD_SERVER_CONTROLLED_KEY: %', v_key
        using errcode = '22023';
    end if;

    if not v_key = any(v_allowed) then
      raise exception 'POLICY_PAYLOAD_UNKNOWN_KEY: %', v_key
        using errcode = '22023';
    end if;
  end loop;

  if p_policy ? 'network_signal_rules' and jsonb_typeof(p_policy->'network_signal_rules') <> 'object' then
    raise exception 'POLICY_PAYLOAD_INVALID_TYPE: network_signal_rules'
      using errcode = '22023';
  end if;

  if p_policy ? 'retention_settings' and jsonb_typeof(p_policy->'retention_settings') <> 'object' then
    raise exception 'POLICY_PAYLOAD_INVALID_TYPE: retention_settings'
      using errcode = '22023';
  end if;

  if p_policy ? 'additional_settings' and jsonb_typeof(p_policy->'additional_settings') <> 'object' then
    raise exception 'POLICY_PAYLOAD_INVALID_TYPE: additional_settings'
      using errcode = '22023';
  end if;

  if p_policy ? 'network_hold_enabled' and jsonb_typeof(p_policy->'network_hold_enabled') <> 'boolean' then
    raise exception 'POLICY_PAYLOAD_INVALID_TYPE: network_hold_enabled'
      using errcode = '22023';
  end if;

  if p_policy ? 'allow_open_slots' and jsonb_typeof(p_policy->'allow_open_slots') <> 'boolean' then
    raise exception 'POLICY_PAYLOAD_INVALID_TYPE: allow_open_slots'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from unnest(array[
      'invitation_ttl_minutes',
      'public_session_ttl_minutes',
      'max_visitor_participants',
      'max_service_participants',
      'max_request_duration_minutes',
      'min_notice_minutes',
      'max_notice_days'
    ]) as keys(key_name)
    where p_policy ? key_name
      and (
        jsonb_typeof(p_policy->key_name) <> 'number'
        or (p_policy->>key_name) !~ '^[0-9]+$'
      )
  ) then
    raise exception 'POLICY_PAYLOAD_INVALID_TYPE: integer field'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from unnest(array[
      'visitor_identity_mode',
      'service_identity_mode',
      'minimum_identity_assurance_level',
      'visitor_background_mode',
      'service_background_mode',
      'network_identity_mode',
      'network_signal_mode',
      'network_signal_min_severity',
      'timezone',
      'privacy_approval_reference',
      'background_approval_reference',
      'network_approval_reference'
    ]) as keys(key_name)
    where p_policy ? key_name
      and jsonb_typeof(p_policy->key_name) not in ('string', 'null')
  ) then
    raise exception 'POLICY_PAYLOAD_INVALID_TYPE: text field'
      using errcode = '22023';
  end if;
end;
$$;

create or replace function public.verified_access_policy_content_checksum(p_policy jsonb)
returns text
language sql
security invoker
set search_path = public, pg_temp
as $$
  select md5(p_policy::text);
$$;

create or replace function public.verified_access_validate_policy_state_machine()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_rpc_context text := current_setting('app.verified_access_policy_rpc', true);
begin
  if old.status = 'ACTIVE' and v_rpc_context <> 'activate' then
    raise exception 'POLICY_ACTIVE_IMMUTABLE'
      using errcode = 'P0001';
  end if;

  if old.status = 'ACTIVE' and v_rpc_context = 'activate' then
    if new.status <> 'RETIRED'
       or new.retired_at is null
       or new.condominium_id <> old.condominium_id
       or new.version <> old.version
       or new.content_checksum <> old.content_checksum then
      raise exception 'POLICY_ACTIVE_REPLACEMENT_ONLY'
        using errcode = 'P0001';
    end if;

    return new;
  end if;

  if old.status is distinct from new.status then
    if old.status = 'DRAFT' and new.status = 'ACTIVE' and v_rpc_context = 'activate' then
      return new;
    end if;

    if old.status = 'DRAFT' and new.status = 'RETIRED' and v_rpc_context = 'retire' then
      return new;
    end if;

    raise exception 'POLICY_STATUS_TRANSITION_INVALID: % -> %', old.status, new.status
      using errcode = 'P0001';
  end if;

  if old.status = 'RETIRED' and new is distinct from old then
    raise exception 'POLICY_RETIRED_IMMUTABLE'
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

drop trigger if exists verified_access_policies_validate_state_machine on public.verified_access_policies;
create trigger verified_access_policies_validate_state_machine
before update on public.verified_access_policies
for each row execute function public.verified_access_validate_policy_state_machine();

create or replace function public.verified_access_create_policy_draft(
  p_condominium_id uuid,
  p_policy jsonb,
  p_actor_id text,
  p_base_policy_id uuid default null,
  p_idempotency_key text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_policy public.verified_access_policies%rowtype;
  v_policy_id uuid;
  v_version integer;
  v_event_key text;
begin
  perform public.verified_access_validate_policy_payload(coalesce(p_policy, '{}'::jsonb));

  if nullif(trim(coalesce(p_actor_id, '')), '') is null then
    raise exception 'POLICY_ACTOR_REQUIRED'
      using errcode = '22023';
  end if;

  if p_idempotency_key is not null then
    select aggregate_id
      into v_policy_id
    from public.verified_access_audit_events
    where event_type = 'POLICY_DRAFT_CREATED'
      and correlation_id = p_idempotency_key
      and condominium_id = p_condominium_id
    order by occurred_at
    limit 1;

    if v_policy_id is not null then
      return v_policy_id;
    end if;
  end if;

  perform 1
  from public.verified_access_policies
  where condominium_id = p_condominium_id
  for update;

  select coalesce(max(version), 0) + 1
    into v_version
  from public.verified_access_policies
  where condominium_id = p_condominium_id;

  if p_base_policy_id is not null then
    select *
      into v_policy
    from public.verified_access_policies
    where id = p_base_policy_id
      and condominium_id = p_condominium_id;

    if not found then
      raise exception 'POLICY_BASE_NOT_FOUND'
        using errcode = 'P0001';
    end if;
  else
    v_policy.condominium_id := p_condominium_id;
    v_policy.schema_version := 2;
    v_policy.visitor_identity_mode := 'DISABLED';
    v_policy.service_identity_mode := 'DISABLED';
    v_policy.minimum_identity_assurance_level := 'SELF_DECLARED';
    v_policy.visitor_background_mode := 'DISABLED';
    v_policy.service_background_mode := 'DISABLED';
    v_policy.network_identity_mode := 'DISABLED';
    v_policy.network_signal_mode := 'DISABLED';
    v_policy.network_signal_min_severity := 'LOW';
    v_policy.network_signal_rules := '{}'::jsonb;
    v_policy.network_hold_enabled := false;
    v_policy.timezone := 'America/Sao_Paulo';
    v_policy.invitation_ttl_minutes := 10080;
    v_policy.public_session_ttl_minutes := 30;
    v_policy.max_visitor_participants := 10;
    v_policy.max_service_participants := 20;
    v_policy.max_request_duration_minutes := 1440;
    v_policy.min_notice_minutes := 0;
    v_policy.max_notice_days := 90;
    v_policy.allow_open_slots := true;
    v_policy.retention_settings := '{"standard_days":90,"sensitive_days":30}'::jsonb;
    v_policy.additional_settings := '{}'::jsonb;
  end if;

  v_policy.id := gen_random_uuid();
  v_policy.version := v_version;
  v_policy.status := 'DRAFT';
  v_policy.created_by_actor_type := 'SERVICE_ROLE';
  v_policy.created_by_actor_id := p_actor_id;
  v_policy.approved_by_actor_id := null;
  v_policy.approved_at := null;
  v_policy.activated_by_actor_id := null;
  v_policy.activated_at := null;
  v_policy.retired_at := null;

  v_policy.visitor_identity_mode := coalesce(nullif(p_policy->>'visitor_identity_mode', ''), v_policy.visitor_identity_mode);
  v_policy.service_identity_mode := coalesce(nullif(p_policy->>'service_identity_mode', ''), v_policy.service_identity_mode);
  v_policy.minimum_identity_assurance_level := coalesce(nullif(p_policy->>'minimum_identity_assurance_level', ''), v_policy.minimum_identity_assurance_level);
  v_policy.visitor_background_mode := coalesce(nullif(p_policy->>'visitor_background_mode', ''), v_policy.visitor_background_mode);
  v_policy.service_background_mode := coalesce(nullif(p_policy->>'service_background_mode', ''), v_policy.service_background_mode);
  v_policy.network_identity_mode := coalesce(nullif(p_policy->>'network_identity_mode', ''), v_policy.network_identity_mode);
  v_policy.network_signal_mode := coalesce(nullif(p_policy->>'network_signal_mode', ''), v_policy.network_signal_mode);
  v_policy.network_signal_min_severity := coalesce(nullif(p_policy->>'network_signal_min_severity', ''), v_policy.network_signal_min_severity);
  v_policy.network_signal_rules := coalesce(p_policy->'network_signal_rules', v_policy.network_signal_rules);
  v_policy.network_hold_enabled := coalesce((p_policy->>'network_hold_enabled')::boolean, v_policy.network_hold_enabled);
  v_policy.timezone := coalesce(nullif(p_policy->>'timezone', ''), v_policy.timezone);
  v_policy.invitation_ttl_minutes := coalesce((p_policy->>'invitation_ttl_minutes')::integer, v_policy.invitation_ttl_minutes);
  v_policy.public_session_ttl_minutes := coalesce((p_policy->>'public_session_ttl_minutes')::integer, v_policy.public_session_ttl_minutes);
  v_policy.max_visitor_participants := coalesce((p_policy->>'max_visitor_participants')::integer, v_policy.max_visitor_participants);
  v_policy.max_service_participants := coalesce((p_policy->>'max_service_participants')::integer, v_policy.max_service_participants);
  v_policy.max_request_duration_minutes := coalesce((p_policy->>'max_request_duration_minutes')::integer, v_policy.max_request_duration_minutes);
  v_policy.min_notice_minutes := coalesce((p_policy->>'min_notice_minutes')::integer, v_policy.min_notice_minutes);
  v_policy.max_notice_days := coalesce((p_policy->>'max_notice_days')::integer, v_policy.max_notice_days);
  v_policy.allow_open_slots := coalesce((p_policy->>'allow_open_slots')::boolean, v_policy.allow_open_slots);
  v_policy.privacy_approval_reference := coalesce(nullif(p_policy->>'privacy_approval_reference', ''), v_policy.privacy_approval_reference);
  v_policy.background_approval_reference := coalesce(nullif(p_policy->>'background_approval_reference', ''), v_policy.background_approval_reference);
  v_policy.network_approval_reference := coalesce(nullif(p_policy->>'network_approval_reference', ''), v_policy.network_approval_reference);
  v_policy.retention_settings := coalesce(p_policy->'retention_settings', v_policy.retention_settings);
  v_policy.additional_settings := coalesce(p_policy->'additional_settings', v_policy.additional_settings);
  v_policy.content_checksum := public.verified_access_policy_content_checksum(jsonb_build_object(
    'schema_version', v_policy.schema_version,
    'visitor_identity_mode', v_policy.visitor_identity_mode,
    'service_identity_mode', v_policy.service_identity_mode,
    'minimum_identity_assurance_level', v_policy.minimum_identity_assurance_level,
    'visitor_background_mode', v_policy.visitor_background_mode,
    'service_background_mode', v_policy.service_background_mode,
    'network_identity_mode', v_policy.network_identity_mode,
    'network_signal_mode', v_policy.network_signal_mode,
    'network_signal_min_severity', v_policy.network_signal_min_severity,
    'network_signal_rules', v_policy.network_signal_rules,
    'network_hold_enabled', v_policy.network_hold_enabled,
    'timezone', v_policy.timezone,
    'invitation_ttl_minutes', v_policy.invitation_ttl_minutes,
    'public_session_ttl_minutes', v_policy.public_session_ttl_minutes,
    'max_visitor_participants', v_policy.max_visitor_participants,
    'max_service_participants', v_policy.max_service_participants,
    'max_request_duration_minutes', v_policy.max_request_duration_minutes,
    'min_notice_minutes', v_policy.min_notice_minutes,
    'max_notice_days', v_policy.max_notice_days,
    'allow_open_slots', v_policy.allow_open_slots,
    'privacy_approval_reference', v_policy.privacy_approval_reference,
    'background_approval_reference', v_policy.background_approval_reference,
    'network_approval_reference', v_policy.network_approval_reference,
    'retention_settings', v_policy.retention_settings,
    'additional_settings', v_policy.additional_settings
  ));

  insert into public.verified_access_policies (
    id, condominium_id, version, schema_version, status,
    visitor_identity_mode, service_identity_mode, minimum_identity_assurance_level,
    visitor_background_mode, service_background_mode,
    network_identity_mode, network_signal_mode, network_signal_min_severity,
    network_signal_rules, network_hold_enabled, timezone,
    invitation_ttl_minutes, public_session_ttl_minutes, max_visitor_participants,
    max_service_participants, max_request_duration_minutes, min_notice_minutes,
    max_notice_days, allow_open_slots, privacy_approval_reference,
    background_approval_reference, network_approval_reference, retention_settings,
    additional_settings, content_checksum, created_by_actor_type, created_by_actor_id
  )
  values (
    v_policy.id, p_condominium_id, v_policy.version, v_policy.schema_version, v_policy.status,
    v_policy.visitor_identity_mode, v_policy.service_identity_mode, v_policy.minimum_identity_assurance_level,
    v_policy.visitor_background_mode, v_policy.service_background_mode,
    v_policy.network_identity_mode, v_policy.network_signal_mode, v_policy.network_signal_min_severity,
    v_policy.network_signal_rules, v_policy.network_hold_enabled, v_policy.timezone,
    v_policy.invitation_ttl_minutes, v_policy.public_session_ttl_minutes, v_policy.max_visitor_participants,
    v_policy.max_service_participants, v_policy.max_request_duration_minutes, v_policy.min_notice_minutes,
    v_policy.max_notice_days, v_policy.allow_open_slots, v_policy.privacy_approval_reference,
    v_policy.background_approval_reference, v_policy.network_approval_reference, v_policy.retention_settings,
    v_policy.additional_settings, v_policy.content_checksum, v_policy.created_by_actor_type, v_policy.created_by_actor_id
  )
  returning id into v_policy_id;

  v_event_key := coalesce('verified_access:policy:draft_created:' || p_idempotency_key, 'verified_access:policy:draft_created:' || v_policy_id::text);
  perform public.verified_access_write_audit_event(p_condominium_id, 'SERVICE_ROLE', p_actor_id, 'POLICY', v_policy_id, 'POLICY_DRAFT_CREATED', 'POLICY_DRAFT_CREATED', p_idempotency_key, jsonb_build_object('policy_version', v_version));
  perform public.verified_access_enqueue_outbox_event(p_condominium_id, 'POLICY', v_policy_id, 'POLICY_DRAFT_CREATED', v_event_key, jsonb_build_object('policy_id', v_policy_id, 'policy_version', v_version));

  return v_policy_id;
end;
$$;

create or replace function public.verified_access_activate_policy(
  p_condominium_id uuid,
  p_policy_id uuid,
  p_actor_id text,
  p_approval_reference text,
  p_idempotency_key text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_existing_policy_id uuid;
  v_policy public.verified_access_policies%rowtype;
  v_event_key text;
begin
  if nullif(trim(coalesce(p_actor_id, '')), '') is null then
    raise exception 'POLICY_ACTOR_REQUIRED'
      using errcode = '22023';
  end if;

  if nullif(trim(coalesce(p_approval_reference, '')), '') is null then
    raise exception 'POLICY_APPROVAL_REFERENCE_REQUIRED'
      using errcode = '22023';
  end if;

  if p_idempotency_key is not null then
    select aggregate_id
      into v_existing_policy_id
    from public.verified_access_audit_events
    where event_type = 'POLICY_ACTIVATED'
      and correlation_id = p_idempotency_key
      and condominium_id = p_condominium_id
    order by occurred_at
    limit 1;

    if v_existing_policy_id is not null then
      return v_existing_policy_id;
    end if;
  end if;

  perform set_config('app.verified_access_policy_rpc', 'activate', true);

  perform 1
  from public.verified_access_policies
  where condominium_id = p_condominium_id
  for update;

  select *
    into v_policy
  from public.verified_access_policies
  where id = p_policy_id
    and condominium_id = p_condominium_id
  for update;

  if not found then
    raise exception 'POLICY_NOT_FOUND'
      using errcode = 'P0001';
  end if;

  if v_policy.status <> 'DRAFT' then
    raise exception 'POLICY_ACTIVATION_REQUIRES_DRAFT'
      using errcode = 'P0001';
  end if;

  update public.verified_access_policies
  set status = 'RETIRED',
      retired_at = now(),
      updated_at = now()
  where condominium_id = p_condominium_id
    and status = 'ACTIVE'
    and id <> p_policy_id;

  update public.verified_access_policies
  set status = 'ACTIVE',
      approved_by_actor_id = p_actor_id,
      approved_at = now(),
      activated_by_actor_id = p_actor_id,
      activated_at = now(),
      updated_at = now()
  where id = p_policy_id
    and condominium_id = p_condominium_id;

  v_event_key := coalesce('verified_access:policy:activated:' || p_idempotency_key, 'verified_access:policy:activated:' || p_policy_id::text);
  perform public.verified_access_write_audit_event(p_condominium_id, 'SERVICE_ROLE', p_actor_id, 'POLICY', p_policy_id, 'POLICY_ACTIVATED', 'POLICY_ACTIVATED', p_idempotency_key, jsonb_build_object('approval_reference_present', true));
  perform public.verified_access_enqueue_outbox_event(p_condominium_id, 'POLICY', p_policy_id, 'POLICY_ACTIVATED', v_event_key, jsonb_build_object('policy_id', p_policy_id));

  return p_policy_id;
end;
$$;

create or replace function public.verified_access_retire_policy(
  p_condominium_id uuid,
  p_policy_id uuid,
  p_actor_id text,
  p_reason_code text,
  p_idempotency_key text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_existing_policy_id uuid;
  v_status text;
  v_event_key text;
begin
  if nullif(trim(coalesce(p_actor_id, '')), '') is null then
    raise exception 'POLICY_ACTOR_REQUIRED'
      using errcode = '22023';
  end if;

  if nullif(trim(coalesce(p_reason_code, '')), '') is null then
    raise exception 'POLICY_RETIRE_REASON_REQUIRED'
      using errcode = '22023';
  end if;

  if p_idempotency_key is not null then
    select aggregate_id
      into v_existing_policy_id
    from public.verified_access_audit_events
    where event_type = 'POLICY_DRAFT_RETIRED'
      and correlation_id = p_idempotency_key
      and condominium_id = p_condominium_id
    order by occurred_at
    limit 1;

    if v_existing_policy_id is not null then
      return v_existing_policy_id;
    end if;
  end if;

  perform set_config('app.verified_access_policy_rpc', 'retire', true);

  select status
    into v_status
  from public.verified_access_policies
  where id = p_policy_id
    and condominium_id = p_condominium_id
  for update;

  if not found then
    raise exception 'POLICY_NOT_FOUND'
      using errcode = 'P0001';
  end if;

  if v_status = 'ACTIVE' then
    raise exception 'POLICY_ACTIVE_REPLACEMENT_REQUIRED'
      using errcode = 'P0001';
  end if;

  if v_status <> 'DRAFT' then
    raise exception 'POLICY_RETIRE_REQUIRES_DRAFT'
      using errcode = 'P0001';
  end if;

  update public.verified_access_policies
  set status = 'RETIRED',
      retired_at = now(),
      updated_at = now()
  where id = p_policy_id
    and condominium_id = p_condominium_id;

  v_event_key := coalesce('verified_access:policy:draft_retired:' || p_idempotency_key, 'verified_access:policy:draft_retired:' || p_policy_id::text);
  perform public.verified_access_write_audit_event(p_condominium_id, 'SERVICE_ROLE', p_actor_id, 'POLICY', p_policy_id, 'POLICY_DRAFT_RETIRED', p_reason_code, p_idempotency_key, jsonb_build_object('reason_code', p_reason_code));
  perform public.verified_access_enqueue_outbox_event(p_condominium_id, 'POLICY', p_policy_id, 'POLICY_DRAFT_RETIRED', v_event_key, jsonb_build_object('policy_id', p_policy_id, 'reason_code', p_reason_code));

  return p_policy_id;
end;
$$;

revoke execute on function public.verified_access_policy_payload_allowed_keys() from public, anon, authenticated, service_role;
revoke execute on function public.verified_access_validate_policy_payload(jsonb) from public, anon, authenticated, service_role;
revoke execute on function public.verified_access_policy_content_checksum(jsonb) from public, anon, authenticated, service_role;
revoke execute on function public.verified_access_validate_policy_state_machine() from public, anon, authenticated, service_role;
revoke execute on function public.verified_access_create_policy_draft(uuid, jsonb, text, uuid, text) from public, anon, authenticated, service_role;
revoke execute on function public.verified_access_activate_policy(uuid, uuid, text, text, text) from public, anon, authenticated, service_role;
revoke execute on function public.verified_access_retire_policy(uuid, uuid, text, text, text) from public, anon, authenticated, service_role;
