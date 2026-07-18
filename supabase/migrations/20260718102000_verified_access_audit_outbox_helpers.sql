create or replace function public.verified_access_assert_sanitized_payload(
  p_payload jsonb,
  p_label text
)
returns void
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception '%_PAYLOAD_MUST_BE_OBJECT', p_label
      using errcode = '22023';
  end if;

  if p_payload::text ~* '(cpf|documento|document|doc_number|phone|telefone|email|nome|name|person_name|token|secret|certidao|certid|biometr)' then
    raise exception '%_PAYLOAD_FORBIDDEN_PII_ALIAS', p_label
      using errcode = '22023';
  end if;
end;
$$;

create or replace function public.verified_access_write_audit_event(
  p_condominium_id uuid,
  p_actor_type text,
  p_actor_id text,
  p_aggregate_type text,
  p_aggregate_id uuid,
  p_event_type text,
  p_reason_code text default null,
  p_correlation_id text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_audit_id uuid;
begin
  perform public.verified_access_assert_sanitized_payload(coalesce(p_metadata, '{}'::jsonb), 'AUDIT');

  insert into public.verified_access_audit_events (
    condominium_id,
    aggregate_type,
    aggregate_id,
    event_type,
    actor_type,
    reason_code,
    correlation_id,
    metadata
  )
  values (
    p_condominium_id,
    p_aggregate_type,
    p_aggregate_id,
    p_event_type,
    p_actor_type,
    p_reason_code,
    p_correlation_id,
    coalesce(p_metadata, '{}'::jsonb) || jsonb_build_object('actor_id_present', nullif(trim(coalesce(p_actor_id, '')), '') is not null)
  )
  returning id into v_audit_id;

  return v_audit_id;
end;
$$;

create or replace function public.verified_access_enqueue_outbox_event(
  p_condominium_id uuid,
  p_aggregate_type text,
  p_aggregate_id uuid,
  p_event_type text,
  p_deduplication_key text,
  p_payload jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_outbox_id uuid;
begin
  perform public.verified_access_assert_sanitized_payload(coalesce(p_payload, '{}'::jsonb), 'OUTBOX');

  insert into public.verified_access_outbox_events (
    condominium_id,
    aggregate_type,
    aggregate_id,
    event_type,
    deduplication_key,
    payload
  )
  values (
    p_condominium_id,
    p_aggregate_type,
    p_aggregate_id,
    p_event_type,
    p_deduplication_key,
    coalesce(p_payload, '{}'::jsonb)
  )
  on conflict (deduplication_key) do nothing
  returning id into v_outbox_id;

  if v_outbox_id is null then
    select id
      into v_outbox_id
    from public.verified_access_outbox_events
    where deduplication_key = p_deduplication_key;
  end if;

  return v_outbox_id;
end;
$$;

revoke execute on function public.verified_access_assert_sanitized_payload(jsonb, text) from public, anon, authenticated, service_role;
revoke execute on function public.verified_access_write_audit_event(uuid, text, text, text, uuid, text, text, text, jsonb) from public, anon, authenticated, service_role;
revoke execute on function public.verified_access_enqueue_outbox_event(uuid, text, uuid, text, text, jsonb) from public, anon, authenticated, service_role;

comment on function public.verified_access_assert_sanitized_payload(jsonb, text) is
  'Internal Phase 1C payload sanitizer. Security invoker; no direct runtime grants.';
comment on function public.verified_access_write_audit_event(uuid, text, text, text, uuid, text, text, text, jsonb) is
  'Internal Phase 1C audit helper. Security definer, fixed search_path, called only by policy RPCs.';
comment on function public.verified_access_enqueue_outbox_event(uuid, text, uuid, text, text, jsonb) is
  'Internal Phase 1C outbox helper. Security definer, fixed search_path, called only by policy RPCs.';
