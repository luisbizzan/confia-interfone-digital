create index if not exists idx_deliveries_due_notifications
on public.deliveries(next_notification_at, status)
where next_notification_at is not null
  and status in ('RECEIVED', 'NOTIFIED');

create or replace function public.list_due_delivery_notifications(p_limit integer default 25)
returns table (
  delivery_id uuid,
  condominium_id uuid,
  next_notification_at timestamptz,
  notification_count integer
)
language sql
security definer
set search_path = public
as $$
  select
    d.id as delivery_id,
    d.condominium_id,
    d.next_notification_at,
    d.notification_count
  from public.deliveries d
  join public.condominium_delivery_settings cds
    on cds.condominium_id = d.condominium_id
  where d.status in ('RECEIVED', 'NOTIFIED')
    and d.next_notification_at is not null
    and d.next_notification_at <= now()
    and cds.enabled = true
    and cds.notify_only_once = false
  order by d.next_notification_at asc
  limit greatest(1, least(coalesce(p_limit, 25), 100));
$$;

create or replace function public.mark_delivery_notification_attempt(
  p_delivery_id uuid,
  p_user_ids uuid[] default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_notify_only_once boolean := true;
  v_interval_minutes integer := 60;
begin
  select
    coalesce(cds.notify_only_once, true),
    greatest(5, least(coalesce(cds.reminder_interval_minutes, 60), 1440))
    into v_notify_only_once,
         v_interval_minutes
  from public.deliveries d
  left join public.condominium_delivery_settings cds
    on cds.condominium_id = d.condominium_id
  where d.id = p_delivery_id
  limit 1;

  update public.deliveries
     set first_notified_at = coalesce(first_notified_at, v_now),
         last_notified_at = v_now,
         next_notification_at = case
           when v_notify_only_once then null
           else v_now + make_interval(mins => v_interval_minutes)
         end,
         notification_count = notification_count + 1,
         status = case
           when status = 'RECEIVED' then 'NOTIFIED'
           else status
         end,
         updated_at = v_now
   where id = p_delivery_id
     and status in ('RECEIVED', 'NOTIFIED');

  update public.delivery_recipients
     set notified_at = coalesce(notified_at, v_now),
         notification_count = notification_count + 1
   where delivery_id = p_delivery_id
     and (
       p_user_ids is null
       or user_id = any(p_user_ids)
     );
end;
$$;

revoke execute on function public.list_due_delivery_notifications(integer) from public;
revoke execute on function public.mark_delivery_notification_attempt(uuid, uuid[]) from public;

grant execute on function public.list_due_delivery_notifications(integer) to service_role;
grant execute on function public.mark_delivery_notification_attempt(uuid, uuid[]) to service_role;
