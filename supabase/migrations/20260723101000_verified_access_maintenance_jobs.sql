create or replace function public.verified_access_phase3c_assert_job_input(
  p_batch_size integer,
  p_dry_run boolean,
  p_correlation_id text
)
returns void
language plpgsql
immutable
security invoker
set search_path = public, pg_temp
as $$
begin
  if p_batch_size is null or p_batch_size < 1 or p_batch_size > 500 then
    raise exception 'MAINTENANCE_BATCH_SIZE_INVALID' using errcode = '22023';
  end if;

  if p_dry_run is null then
    raise exception 'MAINTENANCE_DRY_RUN_INVALID' using errcode = '22023';
  end if;

  if p_correlation_id is not null and (
    p_correlation_id <> trim(p_correlation_id)
    or char_length(p_correlation_id) not between 8 and 128
    or p_correlation_id ~ '[[:cntrl:]]'
  ) then
    raise exception 'MAINTENANCE_CORRELATION_ID_INVALID' using errcode = '22023';
  end if;
end;
$$;

create or replace function public.verified_access_phase3c_record_finding(
  p_condominium_id uuid,
  p_aggregate_type text,
  p_aggregate_id uuid,
  p_related_id uuid,
  p_finding_code text,
  p_correlation_id text
)
returns void
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
begin
  insert into public.verified_access_maintenance_findings (
    condominium_id,
    aggregate_type,
    aggregate_id,
    related_id,
    finding_code,
    correlation_id
  )
  values (
    p_condominium_id,
    p_aggregate_type,
    p_aggregate_id,
    p_related_id,
    p_finding_code,
    p_correlation_id
  )
  on conflict (condominium_id, finding_code, aggregate_id)
  do update set
    related_id = excluded.related_id,
    status = 'OPEN',
    occurrence_count = public.verified_access_maintenance_findings.occurrence_count + 1,
    resolution_code = null,
    correlation_id = excluded.correlation_id,
    last_seen_at = now(),
    resolved_at = null;
end;
$$;

create or replace function public.verified_access_phase3c_result(
  p_job text,
  p_dry_run boolean,
  p_processed integer,
  p_skipped integer,
  p_failed integer,
  p_remaining integer
)
returns jsonb
language sql
immutable
security invoker
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'job', p_job,
    'dryRun', p_dry_run,
    'processed', p_processed,
    'skipped', p_skipped,
    'failed', p_failed,
    'remaining', p_remaining
  );
$$;

create or replace function public.verified_access_expire_invitations(
  p_batch_size integer default 100,
  p_dry_run boolean default true,
  p_correlation_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row record;
  v_processed integer := 0;
  v_failed integer := 0;
  v_remaining integer := 0;
begin
  perform public.verified_access_phase3c_assert_job_input(p_batch_size, p_dry_run, p_correlation_id);
  perform set_config('statement_timeout', '20000', true);

  if p_dry_run then
    select count(*) into v_processed
    from (
      select 1
      from public.verified_access_invitations
      where status in ('PENDING', 'SENT') and expires_at <= now()
      order by expires_at, id
      limit p_batch_size
    ) candidates;
  else
    for v_row in
      select id, condominium_id, request_id
      from public.verified_access_invitations
      where status in ('PENDING', 'SENT') and expires_at <= now()
      order by expires_at, id
      limit p_batch_size
      for update skip locked
    loop
      begin
        update public.verified_access_invitations
        set status = 'EXPIRED', updated_at = now()
        where id = v_row.id and status in ('PENDING', 'SENT');

        if found then
          perform public.verified_access_write_audit_event(
            v_row.condominium_id,
            'SYSTEM',
            null,
            'INVITATION',
            v_row.id,
            'VERIFIED_ACCESS_INVITATION_EXPIRED',
            'TTL_EXPIRED',
            p_correlation_id,
            jsonb_build_object('request_id', v_row.request_id, 'status', 'EXPIRED')
          );
          perform public.verified_access_enqueue_outbox_event(
            v_row.condominium_id,
            'INVITATION',
            v_row.id,
            'VERIFIED_ACCESS_INVITATION_EXPIRED',
            'verified-access:maintenance:invitation:' || v_row.id || ':expired:v1',
            jsonb_build_object(
              'condominium_id', v_row.condominium_id,
              'request_id', v_row.request_id,
              'invitation_id', v_row.id,
              'status', 'EXPIRED',
              'event_code', 'VERIFIED_ACCESS_INVITATION_EXPIRED'
            )
          );
          v_processed := v_processed + 1;
        end if;
      exception when others then
        v_failed := v_failed + 1;
      end;
    end loop;
  end if;

  select count(*) into v_remaining
  from (
    select 1
    from public.verified_access_invitations
    where status in ('PENDING', 'SENT') and expires_at <= now()
    limit p_batch_size + 1
  ) remaining;

  return public.verified_access_phase3c_result(
    'verified_access_expire_invitations',
    p_dry_run,
    v_processed,
    0,
    v_failed,
    v_remaining
  );
end;
$$;

create or replace function public.verified_access_expire_public_sessions(
  p_batch_size integer default 100,
  p_dry_run boolean default true,
  p_correlation_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row record;
  v_processed integer := 0;
  v_failed integer := 0;
  v_remaining integer := 0;
  v_target_status text;
  v_reason text;
begin
  perform public.verified_access_phase3c_assert_job_input(p_batch_size, p_dry_run, p_correlation_id);
  perform set_config('statement_timeout', '20000', true);

  if p_dry_run then
    select count(*) into v_processed
    from (
      select 1
      from public.verified_access_public_sessions s
      join public.verified_access_invitations i on i.id = s.invitation_id
      join public.verified_access_requests r on r.id = s.request_id
      where s.status = 'ACTIVE'
        and (
          s.expires_at <= now()
          or i.status <> 'OPENED'
          or r.status in ('CANCELLED', 'EXPIRED')
        )
      order by s.expires_at, s.id
      limit p_batch_size
    ) candidates;
  else
    for v_row in
      select
        s.id,
        s.condominium_id,
        s.request_id,
        s.invitation_id,
        s.expires_at,
        i.status as invitation_status,
        r.status as request_status
      from public.verified_access_public_sessions s
      join public.verified_access_invitations i on i.id = s.invitation_id
      join public.verified_access_requests r on r.id = s.request_id
      where s.status = 'ACTIVE'
        and (
          s.expires_at <= now()
          or i.status <> 'OPENED'
          or r.status in ('CANCELLED', 'EXPIRED')
        )
      order by s.expires_at, s.id
      limit p_batch_size
      for update of s skip locked
    loop
      begin
        if v_row.expires_at <= now() then
          v_target_status := 'EXPIRED';
          v_reason := 'TTL_EXPIRED';
          update public.verified_access_public_sessions
          set status = 'EXPIRED', updated_at = now()
          where id = v_row.id and status = 'ACTIVE';
        else
          v_target_status := 'REVOKED';
          v_reason := 'PARENT_STATE_INVALID';
          update public.verified_access_public_sessions
          set status = 'REVOKED', revoked_at = now(), updated_at = now()
          where id = v_row.id and status = 'ACTIVE';
        end if;

        if found then
          perform public.verified_access_write_audit_event(
            v_row.condominium_id,
            'SYSTEM',
            null,
            'PUBLIC_SESSION',
            v_row.id,
            'VERIFIED_ACCESS_PUBLIC_SESSION_' || v_target_status,
            v_reason,
            p_correlation_id,
            jsonb_build_object(
              'request_id', v_row.request_id,
              'invitation_id', v_row.invitation_id,
              'status', v_target_status
            )
          );
          perform public.verified_access_enqueue_outbox_event(
            v_row.condominium_id,
            'PUBLIC_SESSION',
            v_row.id,
            'VERIFIED_ACCESS_PUBLIC_SESSION_' || v_target_status,
            'verified-access:maintenance:public-session:' || v_row.id || ':' || lower(v_target_status) || ':v1',
            jsonb_build_object(
              'condominium_id', v_row.condominium_id,
              'request_id', v_row.request_id,
              'invitation_id', v_row.invitation_id,
              'session_id', v_row.id,
              'status', v_target_status,
              'event_code', 'VERIFIED_ACCESS_PUBLIC_SESSION_' || v_target_status
            )
          );
          v_processed := v_processed + 1;
        end if;
      exception when others then
        v_failed := v_failed + 1;
      end;
    end loop;
  end if;

  select count(*) into v_remaining
  from (
    select 1
    from public.verified_access_public_sessions s
    join public.verified_access_invitations i on i.id = s.invitation_id
    join public.verified_access_requests r on r.id = s.request_id
    where s.status = 'ACTIVE'
      and (
        s.expires_at <= now()
        or i.status <> 'OPENED'
        or r.status in ('CANCELLED', 'EXPIRED')
      )
    limit p_batch_size + 1
  ) remaining;

  return public.verified_access_phase3c_result(
    'verified_access_expire_public_sessions',
    p_dry_run,
    v_processed,
    0,
    v_failed,
    v_remaining
  );
end;
$$;

create or replace function public.verified_access_purge_public_commands(
  p_batch_size integer default 100,
  p_dry_run boolean default true,
  p_correlation_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row record;
  v_processed integer := 0;
  v_skipped integer := 0;
  v_failed integer := 0;
  v_remaining integer := 0;
begin
  perform public.verified_access_phase3c_assert_job_input(p_batch_size, p_dry_run, p_correlation_id);
  perform set_config('statement_timeout', '20000', true);

  if p_dry_run then
    select count(*) into v_processed
    from (
      select id
      from public.verified_access_public_registration_commands
      where status = 'COMPLETED'
        and completed_at < now() - interval '30 days'
      order by completed_at, id
      limit p_batch_size
    ) candidates;

    select count(*) into v_skipped
    from (
      select id
      from public.verified_access_public_registration_commands
      where status = 'PROCESSING'
        and created_at < now() - interval '7 days'
      order by created_at, id
      limit p_batch_size
    ) stuck;
  else
    for v_row in
      select id, condominium_id
      from public.verified_access_public_registration_commands
      where status = 'COMPLETED'
        and completed_at < now() - interval '30 days'
      order by completed_at, id
      limit p_batch_size
      for update skip locked
    loop
      begin
        perform public.verified_access_write_audit_event(
          v_row.condominium_id,
          'SYSTEM',
          null,
          'PUBLIC_COMMAND',
          v_row.id,
          'VERIFIED_ACCESS_PUBLIC_COMMAND_PURGED',
          'RETENTION_EXPIRED',
          p_correlation_id,
          jsonb_build_object('status', 'COMPLETED')
        );
        delete from public.verified_access_public_registration_commands
        where id = v_row.id and status = 'COMPLETED';
        if found then
          v_processed := v_processed + 1;
        end if;
      exception when others then
        v_failed := v_failed + 1;
      end;
    end loop;

    for v_row in
      select c.id, c.condominium_id, c.invitation_id
      from public.verified_access_public_registration_commands c
      where c.status = 'PROCESSING'
        and c.created_at < now() - interval '7 days'
      order by c.created_at, c.id
      limit greatest(p_batch_size - v_processed, 0)
      for update of c skip locked
    loop
      begin
        if exists (
          select 1
          from public.verified_access_maintenance_findings f
          where f.condominium_id = v_row.condominium_id
            and f.finding_code = 'COMMAND_PROCESSING_STUCK'
            and f.aggregate_id = v_row.id
            and f.status = 'OPEN'
            and f.first_seen_at < now() - interval '1 minute'
        ) then
          perform public.verified_access_write_audit_event(
            v_row.condominium_id,
            'SYSTEM',
            null,
            'PUBLIC_COMMAND',
            v_row.id,
            'VERIFIED_ACCESS_PUBLIC_COMMAND_PURGED',
            'STUCK_COMMAND_QUARANTINED',
            p_correlation_id,
            jsonb_build_object('status', 'PROCESSING')
          );
          delete from public.verified_access_public_registration_commands
          where id = v_row.id and status = 'PROCESSING';
          if found then
            update public.verified_access_maintenance_findings
            set
              status = 'RESOLVED',
              resolution_code = 'QUARANTINED_AND_PURGED',
              resolved_at = now(),
              last_seen_at = now()
            where condominium_id = v_row.condominium_id
              and finding_code = 'COMMAND_PROCESSING_STUCK'
              and aggregate_id = v_row.id
              and status = 'OPEN';
            v_processed := v_processed + 1;
          end if;
        else
          perform public.verified_access_phase3c_record_finding(
            v_row.condominium_id,
            'PUBLIC_COMMAND',
            v_row.id,
            v_row.invitation_id,
            'COMMAND_PROCESSING_STUCK',
            p_correlation_id
          );
          v_skipped := v_skipped + 1;
        end if;
      exception when others then
        v_failed := v_failed + 1;
      end;
    end loop;
  end if;

  select count(*) into v_remaining
  from (
    select 1
    from public.verified_access_public_registration_commands
    where (
      status = 'COMPLETED' and completed_at < now() - interval '30 days'
    ) or (
      status = 'PROCESSING' and created_at < now() - interval '7 days'
    )
    limit p_batch_size + 1
  ) remaining;

  return public.verified_access_phase3c_result(
    'verified_access_purge_public_commands',
    p_dry_run,
    v_processed,
    v_skipped,
    v_failed,
    v_remaining
  );
end;
$$;

create or replace function public.verified_access_purge_rate_limit_buckets(
  p_batch_size integer default 100,
  p_dry_run boolean default true,
  p_correlation_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row record;
  v_processed integer := 0;
  v_failed integer := 0;
  v_remaining integer := 0;
begin
  perform public.verified_access_phase3c_assert_job_input(p_batch_size, p_dry_run, p_correlation_id);
  perform set_config('statement_timeout', '20000', true);

  if p_dry_run then
    select count(*) into v_processed
    from (
      select id
      from public.verified_access_public_rate_limits
      where expires_at < now() - interval '1 hour'
      order by expires_at, id
      limit p_batch_size
    ) candidates;
  else
    for v_row in
      select id
      from public.verified_access_public_rate_limits
      where expires_at < now() - interval '1 hour'
      order by expires_at, id
      limit p_batch_size
      for update skip locked
    loop
      begin
        delete from public.verified_access_public_rate_limits
        where id = v_row.id and expires_at < now() - interval '1 hour';
        if found then
          v_processed := v_processed + 1;
        end if;
      exception when others then
        v_failed := v_failed + 1;
      end;
    end loop;
  end if;

  select count(*) into v_remaining
  from (
    select 1
    from public.verified_access_public_rate_limits
    where expires_at < now() - interval '1 hour'
    limit p_batch_size + 1
  ) remaining;

  return public.verified_access_phase3c_result(
    'verified_access_purge_rate_limit_buckets',
    p_dry_run,
    v_processed,
    0,
    v_failed,
    v_remaining
  );
end;
$$;

create or replace function public.verified_access_reconcile_public_registration_state(
  p_batch_size integer default 100,
  p_dry_run boolean default true,
  p_correlation_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row record;
  v_processed integer := 0;
  v_failed integer := 0;
begin
  perform public.verified_access_phase3c_assert_job_input(p_batch_size, p_dry_run, p_correlation_id);
  perform set_config('statement_timeout', '20000', true);

  for v_row in
    select *
    from (
      select
        i.condominium_id,
        'INVITATION'::text as aggregate_type,
        i.id as aggregate_id,
        i.participant_slot_id as related_id,
        'INVITATION_COMPLETED_WITHOUT_PARTICIPANT'::text as finding_code
      from public.verified_access_invitations i
      where i.status = 'COMPLETED'
        and not exists (
          select 1 from public.verified_access_participants p
          where p.slot_id = i.participant_slot_id
        )

      union all

      select
        s.condominium_id,
        'PARTICIPANT_SLOT',
        s.id,
        s.request_id,
        'SLOT_CLAIMED_WITHOUT_PARTICIPANT'
      from public.verified_access_participant_slots s
      where s.status = 'CLAIMED'
        and not exists (
          select 1 from public.verified_access_participants p
          where p.slot_id = s.id
        )

      union all

      select
        s.condominium_id,
        'PUBLIC_SESSION',
        s.id,
        s.invitation_id,
        'SESSION_COMPLETED_WITHOUT_INVITATION_COMPLETED'
      from public.verified_access_public_sessions s
      join public.verified_access_invitations i on i.id = s.invitation_id
      where s.status = 'COMPLETED' and i.status <> 'COMPLETED'

      union all

      select
        i.condominium_id,
        'INVITATION',
        i.id,
        i.request_id,
        'INVITATION_ACTIVE_REQUEST_CANCELLED'
      from public.verified_access_invitations i
      join public.verified_access_requests r on r.id = i.request_id
      where i.status in ('PENDING', 'SENT', 'OPENED')
        and r.status = 'CANCELLED'

      union all

      select
        s.condominium_id,
        'PUBLIC_SESSION',
        s.id,
        s.invitation_id,
        'SESSION_ACTIVE_INVITATION_INVALID'
      from public.verified_access_public_sessions s
      join public.verified_access_invitations i on i.id = s.invitation_id
      join public.verified_access_requests r on r.id = s.request_id
      where s.status = 'ACTIVE'
        and (i.status <> 'OPENED' or r.status in ('CANCELLED', 'EXPIRED'))

      union all

      select
        c.condominium_id,
        'PUBLIC_COMMAND',
        c.id,
        c.invitation_id,
        'COMMAND_PROCESSING_STUCK'
      from public.verified_access_public_registration_commands c
      where c.status = 'PROCESSING'
        and c.created_at < now() - interval '7 days'

      union all

      select
        o.condominium_id,
        'OUTBOX_EVENT',
        o.id,
        o.aggregate_id,
        'OUTBOX_PENDING_OVERDUE'
      from public.verified_access_outbox_events o
      where (
        o.status = 'PENDING' and o.created_at < now() - interval '15 minutes'
      ) or (
        o.status = 'PROCESSING' and o.locked_at < now() - interval '15 minutes'
      )
    ) anomalies
    order by condominium_id, finding_code, aggregate_id
    limit p_batch_size
  loop
    begin
      if not p_dry_run then
        perform public.verified_access_phase3c_record_finding(
          v_row.condominium_id,
          v_row.aggregate_type,
          v_row.aggregate_id,
          v_row.related_id,
          v_row.finding_code,
          p_correlation_id
        );

        if v_row.finding_code = 'OUTBOX_PENDING_OVERDUE' then
          update public.verified_access_outbox_events
          set
            status = 'FAILED',
            locked_at = null,
            locked_by = null,
            next_attempt_at = now(),
            last_error_code = 'LEASE_EXPIRED',
            updated_at = now()
          where id = v_row.aggregate_id
            and status = 'PROCESSING'
            and locked_at < now() - interval '15 minutes';
        end if;
      end if;
      v_processed := v_processed + 1;
    exception when others then
      v_failed := v_failed + 1;
    end;
  end loop;

  return public.verified_access_phase3c_result(
    'verified_access_reconcile_public_registration_state',
    p_dry_run,
    v_processed,
    0,
    v_failed,
    0
  );
end;
$$;

create or replace function public.verified_access_process_outbox(
  p_batch_size integer default 100,
  p_dry_run boolean default true,
  p_correlation_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row record;
  v_processed integer := 0;
  v_failed integer := 0;
  v_remaining integer := 0;
  v_worker text := 'phase3c-local-handler';
begin
  perform public.verified_access_phase3c_assert_job_input(p_batch_size, p_dry_run, p_correlation_id);
  perform set_config('statement_timeout', '20000', true);

  if p_dry_run then
    select count(*) into v_processed
    from (
      select 1
      from public.verified_access_outbox_events
      where status in ('PENDING', 'FAILED')
        and next_attempt_at <= now()
        and event_type in (
          'VERIFIED_ACCESS_INVITATION_EXPIRED',
          'VERIFIED_ACCESS_PUBLIC_SESSION_EXPIRED',
          'VERIFIED_ACCESS_PUBLIC_SESSION_REVOKED',
          'VERIFIED_ACCESS_PUBLIC_COMMAND_PURGED',
          'VERIFIED_ACCESS_PUBLIC_SESSION_PURGED',
          'VERIFIED_ACCESS_INVITATION_PURGED'
        )
      order by next_attempt_at, created_at, id
      limit p_batch_size
    ) candidates;
  else
    for v_row in
      select id
      from public.verified_access_outbox_events
      where status in ('PENDING', 'FAILED')
        and next_attempt_at <= now()
        and event_type in (
          'VERIFIED_ACCESS_INVITATION_EXPIRED',
          'VERIFIED_ACCESS_PUBLIC_SESSION_EXPIRED',
          'VERIFIED_ACCESS_PUBLIC_SESSION_REVOKED',
          'VERIFIED_ACCESS_PUBLIC_COMMAND_PURGED',
          'VERIFIED_ACCESS_PUBLIC_SESSION_PURGED',
          'VERIFIED_ACCESS_INVITATION_PURGED'
        )
      order by next_attempt_at, created_at, id
      limit p_batch_size
      for update skip locked
    loop
      begin
        update public.verified_access_outbox_events
        set
          status = 'PROCESSING',
          attempts = attempts + 1,
          locked_at = now(),
          locked_by = v_worker,
          last_error_code = null,
          updated_at = now()
        where id = v_row.id and status in ('PENDING', 'FAILED');

        if found then
          update public.verified_access_outbox_events
          set
            status = 'PROCESSED',
            locked_at = null,
            locked_by = null,
            updated_at = now()
          where id = v_row.id and status = 'PROCESSING' and locked_by = v_worker;
          v_processed := v_processed + 1;
        end if;
      exception when others then
        update public.verified_access_outbox_events
        set
          status = 'FAILED',
          locked_at = null,
          locked_by = null,
          next_attempt_at = now() + interval '5 minutes',
          last_error_code = 'LOCAL_HANDLER_FAILED',
          updated_at = now()
        where id = v_row.id;
        v_failed := v_failed + 1;
      end;
    end loop;
  end if;

  select count(*) into v_remaining
  from (
    select 1
    from public.verified_access_outbox_events
    where status in ('PENDING', 'FAILED')
      and next_attempt_at <= now()
      and event_type in (
        'VERIFIED_ACCESS_INVITATION_EXPIRED',
        'VERIFIED_ACCESS_PUBLIC_SESSION_EXPIRED',
        'VERIFIED_ACCESS_PUBLIC_SESSION_REVOKED',
        'VERIFIED_ACCESS_PUBLIC_COMMAND_PURGED',
        'VERIFIED_ACCESS_PUBLIC_SESSION_PURGED',
        'VERIFIED_ACCESS_INVITATION_PURGED'
      )
    limit p_batch_size + 1
  ) remaining;

  return public.verified_access_phase3c_result(
    'verified_access_process_outbox',
    p_dry_run,
    v_processed,
    0,
    v_failed,
    v_remaining
  );
end;
$$;

create or replace function public.verified_access_apply_retention_policy(
  p_batch_size integer default 100,
  p_dry_run boolean default true,
  p_correlation_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row record;
  v_processed integer := 0;
  v_skipped integer := 0;
  v_failed integer := 0;
  v_remaining integer := 0;
begin
  perform public.verified_access_phase3c_assert_job_input(p_batch_size, p_dry_run, p_correlation_id);
  perform set_config('statement_timeout', '20000', true);

  if p_dry_run then
    select count(*) into v_processed
    from (
      select id
      from public.verified_access_public_sessions s
      where s.status in ('COMPLETED', 'REVOKED', 'EXPIRED')
        and s.updated_at < now() - interval '7 days'
        and not exists (
          select 1 from public.verified_access_public_registration_commands c
          where c.session_id = s.id
        )
      order by s.updated_at, s.id
      limit p_batch_size
    ) sessions;
  else
    for v_row in
      select id, condominium_id, request_id, invitation_id
      from public.verified_access_public_sessions s
      where s.status in ('COMPLETED', 'REVOKED', 'EXPIRED')
        and s.updated_at < now() - interval '7 days'
        and not exists (
          select 1 from public.verified_access_public_registration_commands c
          where c.session_id = s.id
        )
      order by s.updated_at, s.id
      limit p_batch_size
      for update of s skip locked
    loop
      begin
        perform public.verified_access_write_audit_event(
          v_row.condominium_id,
          'SYSTEM',
          null,
          'PUBLIC_SESSION',
          v_row.id,
          'VERIFIED_ACCESS_PUBLIC_SESSION_PURGED',
          'RETENTION_EXPIRED',
          p_correlation_id,
          jsonb_build_object(
            'request_id', v_row.request_id,
            'invitation_id', v_row.invitation_id
          )
        );
        perform public.verified_access_enqueue_outbox_event(
          v_row.condominium_id,
          'PUBLIC_SESSION',
          v_row.id,
          'VERIFIED_ACCESS_PUBLIC_SESSION_PURGED',
          'verified-access:maintenance:public-session:' || v_row.id || ':purged:v1',
          jsonb_build_object(
            'condominium_id', v_row.condominium_id,
            'request_id', v_row.request_id,
            'invitation_id', v_row.invitation_id,
            'session_id', v_row.id,
            'event_code', 'VERIFIED_ACCESS_PUBLIC_SESSION_PURGED'
          )
        );
        delete from public.verified_access_public_sessions where id = v_row.id;
        if found then
          v_processed := v_processed + 1;
        end if;
      exception when others then
        v_failed := v_failed + 1;
      end;
    end loop;

    for v_row in
      select id
      from public.verified_access_outbox_events
      where status = 'PROCESSED'
        and updated_at < now() - interval '30 days'
      order by updated_at, id
      limit greatest(p_batch_size - v_processed, 0)
      for update skip locked
    loop
      begin
        delete from public.verified_access_outbox_events
        where id = v_row.id and status = 'PROCESSED';
        if found then
          v_processed := v_processed + 1;
        end if;
      exception when others then
        v_failed := v_failed + 1;
      end;
    end loop;

    for v_row in
      select id, condominium_id, request_id
      from public.verified_access_invitations i
      where i.status in ('COMPLETED', 'REVOKED', 'EXPIRED')
        and i.updated_at < now() - interval '90 days'
      order by i.updated_at, i.id
      limit greatest(p_batch_size - v_processed, 0)
      for update of i skip locked
    loop
      begin
        if exists (
          select 1 from public.verified_access_public_sessions s
          where s.invitation_id = v_row.id
        ) or exists (
          select 1 from public.verified_access_public_registration_commands c
          where c.invitation_id = v_row.id
        ) or exists (
          select 1 from public.verified_access_invitation_commands c
          where c.invitation_id = v_row.id
        ) then
          v_skipped := v_skipped + 1;
        else
          perform public.verified_access_write_audit_event(
            v_row.condominium_id,
            'SYSTEM',
            null,
            'INVITATION',
            v_row.id,
            'VERIFIED_ACCESS_INVITATION_PURGED',
            'RETENTION_EXPIRED',
            p_correlation_id,
            jsonb_build_object('request_id', v_row.request_id)
          );
          perform public.verified_access_enqueue_outbox_event(
            v_row.condominium_id,
            'INVITATION',
            v_row.id,
            'VERIFIED_ACCESS_INVITATION_PURGED',
            'verified-access:maintenance:invitation:' || v_row.id || ':purged:v1',
            jsonb_build_object(
              'condominium_id', v_row.condominium_id,
              'request_id', v_row.request_id,
              'invitation_id', v_row.id,
              'event_code', 'VERIFIED_ACCESS_INVITATION_PURGED'
            )
          );
          delete from public.verified_access_invitations where id = v_row.id;
          if found then
            v_processed := v_processed + 1;
          end if;
        end if;
      exception when others then
        v_failed := v_failed + 1;
      end;
    end loop;
  end if;

  select count(*) into v_remaining
  from (
    select 1
    from public.verified_access_public_sessions s
    where s.status in ('COMPLETED', 'REVOKED', 'EXPIRED')
      and s.updated_at < now() - interval '7 days'
    union all
    select 1
    from public.verified_access_outbox_events o
    where o.status = 'PROCESSED'
      and o.updated_at < now() - interval '30 days'
    union all
    select 1
    from public.verified_access_invitations i
    where i.status in ('COMPLETED', 'REVOKED', 'EXPIRED')
      and i.updated_at < now() - interval '90 days'
    limit p_batch_size + 1
  ) remaining;

  return public.verified_access_phase3c_result(
    'verified_access_apply_retention_policy',
    p_dry_run,
    v_processed,
    v_skipped,
    v_failed,
    v_remaining
  );
end;
$$;

do $$
begin
  if not exists (
    select 1 from pg_roles where rolname = 'verified_access_phase3c_maintenance_executor'
  ) then
    create role verified_access_phase3c_maintenance_executor nologin;
  end if;
end;
$$;

revoke all on function public.verified_access_phase3c_assert_job_input(integer, boolean, text)
from public, anon, authenticated, service_role;
revoke all on function public.verified_access_phase3c_record_finding(uuid, text, uuid, uuid, text, text)
from public, anon, authenticated, service_role;
revoke all on function public.verified_access_phase3c_result(text, boolean, integer, integer, integer, integer)
from public, anon, authenticated, service_role;

revoke all on function public.verified_access_expire_invitations(integer, boolean, text)
from public, anon, authenticated, service_role;
revoke all on function public.verified_access_expire_public_sessions(integer, boolean, text)
from public, anon, authenticated, service_role;
revoke all on function public.verified_access_purge_public_commands(integer, boolean, text)
from public, anon, authenticated, service_role;
revoke all on function public.verified_access_purge_rate_limit_buckets(integer, boolean, text)
from public, anon, authenticated, service_role;
revoke all on function public.verified_access_reconcile_public_registration_state(integer, boolean, text)
from public, anon, authenticated, service_role;
revoke all on function public.verified_access_process_outbox(integer, boolean, text)
from public, anon, authenticated, service_role;
revoke all on function public.verified_access_apply_retention_policy(integer, boolean, text)
from public, anon, authenticated, service_role;

grant execute on function public.verified_access_expire_invitations(integer, boolean, text)
to verified_access_phase3c_maintenance_executor;
grant execute on function public.verified_access_expire_public_sessions(integer, boolean, text)
to verified_access_phase3c_maintenance_executor;
grant execute on function public.verified_access_purge_public_commands(integer, boolean, text)
to verified_access_phase3c_maintenance_executor;
grant execute on function public.verified_access_purge_rate_limit_buckets(integer, boolean, text)
to verified_access_phase3c_maintenance_executor;
grant execute on function public.verified_access_reconcile_public_registration_state(integer, boolean, text)
to verified_access_phase3c_maintenance_executor;
grant execute on function public.verified_access_process_outbox(integer, boolean, text)
to verified_access_phase3c_maintenance_executor;
grant execute on function public.verified_access_apply_retention_policy(integer, boolean, text)
to verified_access_phase3c_maintenance_executor;

grant verified_access_phase3c_maintenance_executor to service_role;

comment on function public.verified_access_expire_invitations(integer, boolean, text) is
  'Phase 3C bounded invitation expiration job. No PII; exact executor-role grant only.';
comment on function public.verified_access_expire_public_sessions(integer, boolean, text) is
  'Phase 3C bounded public-session expiration and invalidation job.';
comment on function public.verified_access_purge_public_commands(integer, boolean, text) is
  'Phase 3C command retention job with finding-first quarantine for stuck commands.';
comment on function public.verified_access_purge_rate_limit_buckets(integer, boolean, text) is
  'Phase 3C rate-limit retention job with a one-hour safety margin.';
comment on function public.verified_access_reconcile_public_registration_state(integer, boolean, text) is
  'Phase 3C conservative reconciliation job. Records sanitized findings and never creates identity data.';
comment on function public.verified_access_process_outbox(integer, boolean, text) is
  'Phase 3C local-only outbox handler for an explicit maintenance event allowlist.';
comment on function public.verified_access_apply_retention_policy(integer, boolean, text) is
  'Phase 3C retention job. Deletes only bounded terminal operational records after dependency checks.';
