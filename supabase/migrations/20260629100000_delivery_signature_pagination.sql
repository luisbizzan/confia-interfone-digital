update storage.buckets
set allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp', 'application/pdf', 'application/json']
where id = 'delivery-attachments';

create or replace function public.list_pending_deliveries(
  p_status_filter text default 'pending',
  p_limit integer default 20,
  p_offset integer default 0,
  p_delivered_from timestamptz default null,
  p_delivered_to timestamptz default null
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select case
    when not public.user_is_active_portaria(public.current_user_condominium_id()) then '[]'::jsonb
    else coalesce(jsonb_agg(public.delivery_to_json(filtered_delivery) order by coalesce(filtered_delivery.delivered_at, filtered_delivery.received_at) desc), '[]'::jsonb)
  end
  from (
    select d.*
    from public.deliveries d
    where d.condominium_id = public.current_user_condominium_id()
      and (
        (coalesce(p_status_filter, 'pending') = 'delivered' and d.status = 'DELIVERED')
        or (coalesce(p_status_filter, 'pending') <> 'delivered' and d.status in ('RECEIVED', 'NOTIFIED'))
      )
      and (
        coalesce(p_status_filter, 'pending') <> 'delivered'
        or p_delivered_from is null
        or d.delivered_at >= p_delivered_from
      )
      and (
        coalesce(p_status_filter, 'pending') <> 'delivered'
        or p_delivered_to is null
        or d.delivered_at < p_delivered_to
      )
    order by coalesce(d.delivered_at, d.received_at) desc
    limit greatest(1, least(coalesce(p_limit, 20), 100))
    offset greatest(0, coalesce(p_offset, 0))
  ) filtered_delivery
$$;

create or replace function public.list_my_deliveries(
  p_limit integer default 30,
  p_offset integer default 0
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(public.delivery_to_json(d) order by d.received_at desc), '[]'::jsonb)
  from (
    select d.*
    from public.deliveries d
    where d.condominium_id = public.current_user_condominium_id()
      and public.user_can_access_delivery(d.id)
    order by d.received_at desc
    limit greatest(1, least(coalesce(p_limit, 30), 100))
    offset greatest(0, coalesce(p_offset, 0))
  ) d
$$;

revoke execute on function public.list_pending_deliveries(text, integer, integer, timestamptz, timestamptz) from public;
revoke execute on function public.list_my_deliveries(integer, integer) from public;

grant execute on function public.list_pending_deliveries(text, integer, integer, timestamptz, timestamptz) to authenticated;
grant execute on function public.list_my_deliveries(integer, integer) to authenticated;
