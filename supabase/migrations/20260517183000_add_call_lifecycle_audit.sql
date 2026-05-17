create table if not exists public.call_events (
  id uuid primary key default gen_random_uuid(),
  condominium_id uuid not null references public.condominiums(id) on delete cascade,
  call_id uuid not null references public.calls(id) on delete cascade,
  event_type text not null check (
    event_type in (
      'CALL_CREATED',
      'ATTEMPT_CREATED',
      'ATTEMPT_NO_ANSWER',
      'CALL_ANSWERED',
      'CALL_MISSED',
      'CALL_CANCELLED',
      'CALL_ENDED'
    )
  ),
  actor_user_id uuid,
  actor_type text not null default 'SYSTEM' check (actor_type in ('SYSTEM', 'PORTARIA', 'UNIT')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_call_events_call_created_at
on public.call_events(call_id, created_at);

create index if not exists idx_call_events_condominium_created_at
on public.call_events(condominium_id, created_at desc);

alter table public.call_events enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'call_events'
      and policyname = 'users read call events in condominium'
  ) then
    create policy "users read call events in condominium"
    on public.call_events for select
    to authenticated
    using (condominium_id = public.current_user_condominium_id());
  end if;
end $$;

create or replace function public.log_call_event(
  p_call_id uuid,
  p_event_type text,
  p_actor_user_id uuid default null,
  p_actor_type text default 'SYSTEM',
  p_metadata jsonb default '{}'::jsonb
)
returns public.call_events
language plpgsql
security definer
set search_path = public
as $$
declare
  v_call public.calls;
  v_event public.call_events;
begin
  select *
    into v_call
  from public.calls
  where id = p_call_id;

  if not found then
    raise exception 'Call not found';
  end if;

  insert into public.call_events (
    condominium_id,
    call_id,
    event_type,
    actor_user_id,
    actor_type,
    metadata
  )
  values (
    v_call.condominium_id,
    v_call.id,
    p_event_type,
    p_actor_user_id,
    coalesce(p_actor_type, 'SYSTEM'),
    coalesce(p_metadata, '{}'::jsonb)
  )
  returning * into v_event;

  return v_event;
end;
$$;

create or replace function public.start_portaria_call(p_unit_id uuid)
returns public.calls
language plpgsql
security definer
set search_path = public
as $$
declare
  v_unit public.units;
  v_call public.calls;
  v_attempt public.call_attempts;
  v_first_member public.unit_members;
  v_portaria public.portaria_devices;
begin
  select *
    into v_portaria
  from public.current_portaria_device();

  if not found or v_portaria.can_make_calls is not true then
    raise exception 'Active portaria device not found or cannot make calls';
  end if;

  select *
    into v_unit
  from public.units
  where id = p_unit_id
    and condominium_id = v_portaria.condominium_id;

  if not found then
    raise exception 'Unit not found or not allowed';
  end if;

  select *
    into v_first_member
  from public.unit_members
  where unit_id = p_unit_id
    and active_for_calls = true
    and can_receive_calls = true
  order by call_order asc, created_at asc
  limit 1;

  if not found then
    raise exception 'No active member available for calls';
  end if;

  insert into public.calls (
    condominium_id,
    unit_id,
    origin_type,
    origin_portaria_device_id,
    target_type,
    status
  )
  values (
    v_unit.condominium_id,
    v_unit.id,
    'PORTARIA',
    v_portaria.id,
    'UNIT',
    'RINGING'
  )
  returning * into v_call;

  perform public.log_call_event(
    v_call.id,
    'CALL_CREATED',
    auth.uid(),
    'PORTARIA',
    jsonb_build_object('target_type', 'UNIT', 'unit_id', v_unit.id)
  );

  insert into public.call_attempts (call_id, unit_member_id, attempt_order, status)
  values (v_call.id, v_first_member.id, v_first_member.call_order, 'RINGING')
  returning * into v_attempt;

  perform public.log_call_event(
    v_call.id,
    'ATTEMPT_CREATED',
    auth.uid(),
    'PORTARIA',
    jsonb_build_object(
      'attempt_id', v_attempt.id,
      'unit_member_id', v_attempt.unit_member_id,
      'attempt_order', v_attempt.attempt_order
    )
  );

  return v_call;
end;
$$;

create or replace function public.start_unit_to_portaria_call(p_unit_id uuid)
returns public.calls
language plpgsql
security definer
set search_path = public
as $$
declare
  v_unit public.units;
  v_member public.unit_members;
  v_portaria public.portaria_devices;
  v_call public.calls;
begin
  select *
    into v_member
  from public.unit_members
  where unit_id = p_unit_id
    and user_id = auth.uid()
    and can_make_calls = true;

  if not found then
    raise exception 'User cannot start calls from this unit';
  end if;

  select *
    into v_unit
  from public.units
  where id = p_unit_id
    and condominium_id = v_member.condominium_id;

  if not found then
    raise exception 'Unit not found or not allowed';
  end if;

  select *
    into v_portaria
  from public.first_active_portaria_device(v_unit.condominium_id);

  if not found then
    raise exception 'No active portaria device available';
  end if;

  insert into public.calls (
    condominium_id,
    unit_id,
    origin_type,
    origin_unit_id,
    target_type,
    target_portaria_device_id,
    status
  )
  values (
    v_unit.condominium_id,
    v_unit.id,
    'UNIT',
    v_unit.id,
    'PORTARIA',
    v_portaria.id,
    'RINGING'
  )
  returning * into v_call;

  perform public.log_call_event(
    v_call.id,
    'CALL_CREATED',
    auth.uid(),
    'UNIT',
    jsonb_build_object(
      'target_type', 'PORTARIA',
      'unit_id', v_unit.id,
      'target_portaria_device_id', v_portaria.id
    )
  );

  return v_call;
end;
$$;

create or replace function public.answer_call(p_call_id uuid, p_user_id uuid)
returns public.calls
language plpgsql
security definer
set search_path = public
as $$
declare
  v_call public.calls;
  v_member public.unit_members;
  v_attempt public.call_attempts;
begin
  if p_user_id <> auth.uid() then
    raise exception 'User cannot answer on behalf of another user';
  end if;

  select *
    into v_call
  from public.calls
  where id = p_call_id
    and status = 'RINGING'
    and target_type = 'UNIT'
  for update;

  if not found then
    raise exception 'Call not found or not ringing';
  end if;

  select *
    into v_member
  from public.unit_members
  where unit_id = v_call.unit_id
    and user_id = p_user_id
    and active_for_calls = true
    and can_receive_calls = true;

  if not found then
    raise exception 'User cannot answer this call';
  end if;

  select *
    into v_attempt
  from public.call_attempts
  where call_id = p_call_id
    and unit_member_id = v_member.id
    and status = 'RINGING'
  for update;

  if not found then
    raise exception 'No active attempt for this user';
  end if;

  update public.call_attempts
    set status = 'ANSWERED',
        ended_at = now()
  where id = v_attempt.id;

  update public.calls
    set status = 'ANSWERED',
        answered_by = p_user_id,
        answered_at = now(),
        ended_at = now()
  where id = p_call_id
  returning * into v_call;

  perform public.log_call_event(
    v_call.id,
    'CALL_ANSWERED',
    auth.uid(),
    'UNIT',
    jsonb_build_object('attempt_id', v_attempt.id, 'unit_member_id', v_member.id)
  );

  return v_call;
end;
$$;

create or replace function public.answer_portaria_call(p_call_id uuid)
returns public.calls
language plpgsql
security definer
set search_path = public
as $$
declare
  v_call public.calls;
  v_portaria public.portaria_devices;
begin
  select *
    into v_portaria
  from public.current_portaria_device();

  if not found or v_portaria.can_receive_calls is not true then
    raise exception 'Active portaria device not found or cannot receive calls';
  end if;

  select *
    into v_call
  from public.calls
  where id = p_call_id
    and status = 'RINGING'
    and target_type = 'PORTARIA'
    and target_portaria_device_id = v_portaria.id
  for update;

  if not found then
    raise exception 'Call not found or not assigned to this portaria device';
  end if;

  update public.calls
    set status = 'ANSWERED',
        answered_by = auth.uid(),
        answered_at = now(),
        ended_at = now()
  where id = p_call_id
  returning * into v_call;

  perform public.log_call_event(
    v_call.id,
    'CALL_ANSWERED',
    auth.uid(),
    'PORTARIA',
    jsonb_build_object('portaria_device_id', v_portaria.id)
  );

  return v_call;
end;
$$;

create or replace function public.process_call_timeout(p_call_id uuid)
returns public.calls
language plpgsql
security definer
set search_path = public
as $$
declare
  v_call public.calls;
  v_attempt public.call_attempts;
  v_next_member public.unit_members;
  v_new_attempt public.call_attempts;
begin
  select *
    into v_call
  from public.calls
  where id = p_call_id
    and status = 'RINGING'
  for update skip locked;

  if not found then
    return null;
  end if;

  if v_call.target_type = 'PORTARIA' then
    return v_call;
  end if;

  select *
    into v_attempt
  from public.call_attempts
  where call_id = p_call_id
    and status = 'RINGING'
  order by started_at desc
  limit 1
  for update;

  if not found then
    return v_call;
  end if;

  if v_attempt.started_at > now() - interval '20 seconds' then
    return v_call;
  end if;

  update public.call_attempts
    set status = 'NO_ANSWER',
        ended_at = now()
  where id = v_attempt.id;

  perform public.log_call_event(
    v_call.id,
    'ATTEMPT_NO_ANSWER',
    null,
    'SYSTEM',
    jsonb_build_object('attempt_id', v_attempt.id, 'unit_member_id', v_attempt.unit_member_id)
  );

  select *
    into v_next_member
  from public.unit_members
  where unit_id = v_call.unit_id
    and active_for_calls = true
    and can_receive_calls = true
    and call_order > v_attempt.attempt_order
  order by call_order asc, created_at asc
  limit 1;

  if found then
    insert into public.call_attempts (call_id, unit_member_id, attempt_order, status)
    values (v_call.id, v_next_member.id, v_next_member.call_order, 'RINGING')
    returning * into v_new_attempt;

    perform public.log_call_event(
      v_call.id,
      'ATTEMPT_CREATED',
      null,
      'SYSTEM',
      jsonb_build_object(
        'attempt_id', v_new_attempt.id,
        'unit_member_id', v_new_attempt.unit_member_id,
        'attempt_order', v_new_attempt.attempt_order
      )
    );
  else
    update public.calls
      set status = 'MISSED',
          ended_at = now()
    where id = v_call.id
    returning * into v_call;

    perform public.log_call_event(v_call.id, 'CALL_MISSED', null, 'SYSTEM', '{}'::jsonb);
  end if;

  return v_call;
end;
$$;

create or replace function public.cancel_call(p_call_id uuid, p_reason text default null)
returns public.calls
language plpgsql
security definer
set search_path = public
as $$
declare
  v_call public.calls;
  v_actor_type text;
  v_can_cancel boolean := false;
begin
  select *
    into v_call
  from public.calls
  where id = p_call_id
    and status = 'RINGING'
  for update;

  if not found then
    raise exception 'Call not found or not cancellable';
  end if;

  if v_call.origin_type = 'UNIT' then
    select exists (
      select 1
      from public.unit_members um
      where um.unit_id = v_call.origin_unit_id
        and um.user_id = auth.uid()
    ) into v_can_cancel;

    v_actor_type := 'UNIT';
  elsif v_call.origin_type = 'PORTARIA' then
    select exists (
      select 1
      from public.portaria_devices pd
      where pd.id = v_call.origin_portaria_device_id
        and pd.user_id = auth.uid()
        and pd.is_active = true
    ) into v_can_cancel;

    v_actor_type := 'PORTARIA';
  end if;

  if not v_can_cancel then
    raise exception 'User cannot cancel this call';
  end if;

  update public.call_attempts
    set status = 'FAILED',
        ended_at = now()
  where call_id = p_call_id
    and status = 'RINGING';

  update public.calls
    set status = 'CANCELLED',
        ended_at = now()
  where id = p_call_id
  returning * into v_call;

  perform public.log_call_event(
    v_call.id,
    'CALL_CANCELLED',
    auth.uid(),
    v_actor_type,
    jsonb_build_object('reason', p_reason)
  );

  return v_call;
end;
$$;

create or replace function public.end_call(p_call_id uuid, p_reason text default null)
returns public.calls
language plpgsql
security definer
set search_path = public
as $$
declare
  v_call public.calls;
  v_actor_type text;
  v_can_end boolean := false;
begin
  select *
    into v_call
  from public.calls
  where id = p_call_id
    and status in ('ANSWERED', 'RINGING')
  for update;

  if not found then
    raise exception 'Call not found or not endable';
  end if;

  select exists (
    select 1
    from public.unit_members um
    where um.unit_id = v_call.unit_id
      and um.user_id = auth.uid()
  ) into v_can_end;

  if v_can_end then
    v_actor_type := 'UNIT';
  else
    select exists (
      select 1
      from public.portaria_devices pd
      where pd.user_id = auth.uid()
        and pd.condominium_id = v_call.condominium_id
        and pd.is_active = true
    ) into v_can_end;

    v_actor_type := 'PORTARIA';
  end if;

  if not v_can_end then
    raise exception 'User cannot end this call';
  end if;

  update public.call_attempts
    set status = case when status = 'RINGING' then 'FAILED' else status end,
        ended_at = coalesce(ended_at, now())
  where call_id = p_call_id;

  update public.calls
    set status = case when status = 'RINGING' then 'CANCELLED' else status end,
        ended_at = coalesce(ended_at, now())
  where id = p_call_id
  returning * into v_call;

  perform public.log_call_event(
    v_call.id,
    'CALL_ENDED',
    auth.uid(),
    v_actor_type,
    jsonb_build_object('reason', p_reason)
  );

  return v_call;
end;
$$;

create or replace function public.process_expired_calls()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_call record;
  v_processed integer := 0;
begin
  for v_call in
    select c.id
    from public.calls c
    join public.call_attempts ca on ca.call_id = c.id
    where c.status = 'RINGING'
      and c.target_type = 'UNIT'
      and ca.status = 'RINGING'
      and ca.started_at <= now() - interval '20 seconds'
  loop
    perform public.process_call_timeout(v_call.id);
    v_processed := v_processed + 1;
  end loop;

  return jsonb_build_object('processed', v_processed);
end;
$$;

revoke execute on function public.log_call_event(uuid, text, uuid, text, jsonb) from public;
revoke execute on function public.cancel_call(uuid, text) from public;
revoke execute on function public.end_call(uuid, text) from public;

grant execute on function public.log_call_event(uuid, text, uuid, text, jsonb) to service_role;
grant execute on function public.cancel_call(uuid, text) to authenticated;
grant execute on function public.end_call(uuid, text) to authenticated;
