alter table public.condominium_delivery_settings
  add column if not exists source_options jsonb not null default '["iFood","Rappi","Mercado Livre","Shopee","Amazon","Correios","Sedex","Transportadora","Loggi","Jadlog","Total Express","Uber Flash","Farmacia","Mercado","Morador/Terceiro"]'::jsonb,
  add column if not exists description_options jsonb not null default '["Comida","Documento","Envelope","Pacote pequeno","Pacote medio","Caixa","Presente","Produto refrigerado"]'::jsonb,
  add column if not exists require_received_photo boolean not null default true,
  add column if not exists require_delivery_photo boolean not null default false,
  add column if not exists require_signature boolean not null default false;

update public.condominium_delivery_settings
set
  source_options = case
    when jsonb_array_length(coalesce(source_options, '[]'::jsonb)) = 0 then '["iFood","Rappi","Mercado Livre","Shopee","Amazon","Correios","Sedex","Transportadora","Loggi","Jadlog","Total Express","Uber Flash","Farmacia","Mercado","Morador/Terceiro"]'::jsonb
    else source_options
  end,
  description_options = case
    when jsonb_array_length(coalesce(description_options, '[]'::jsonb)) = 0 then '["Comida","Documento","Envelope","Pacote pequeno","Pacote medio","Caixa","Presente","Produto refrigerado"]'::jsonb
    else description_options
  end;

create or replace function public.delivery_to_json(p_delivery public.deliveries)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', p_delivery.id,
    'condominium_id', p_delivery.condominium_id,
    'unit_id', p_delivery.unit_id,
    'unit_label', coalesce(public.unit_display_label(p_delivery.unit_id), 'Unidade'),
    'status', p_delivery.status,
    'package_source', p_delivery.package_source,
    'package_description', p_delivery.package_description,
    'tracking_code', p_delivery.tracking_code,
    'received_by_user_id', p_delivery.received_by_user_id,
    'received_by_email', received_user.email,
    'received_by_portaria_device_id', p_delivery.received_by_portaria_device_id,
    'received_at', p_delivery.received_at,
    'first_notified_at', p_delivery.first_notified_at,
    'last_notified_at', p_delivery.last_notified_at,
    'next_notification_at', p_delivery.next_notification_at,
    'notification_count', p_delivery.notification_count,
    'delivered_by_user_id', p_delivery.delivered_by_user_id,
    'delivered_by_email', delivered_user.email,
    'delivered_to_unit_member_id', p_delivery.delivered_to_unit_member_id,
    'delivered_to_name', p_delivery.delivered_to_name,
    'delivered_at', p_delivery.delivered_at,
    'delivery_observations', p_delivery.delivery_observations,
    'created_at', p_delivery.created_at,
    'recipients', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', dr.id,
          'unit_member_id', dr.unit_member_id,
          'user_id', dr.user_id,
          'display_name', coalesce(
            nullif(trim(recipient_user.raw_user_meta_data ->> 'full_name'), ''),
            nullif(trim(recipient_user.raw_user_meta_data ->> 'name'), ''),
            nullif(split_part(recipient_user.email, '@', 1), ''),
            recipient_user.email
          ),
          'email', recipient_user.email,
          'notified_at', dr.notified_at,
          'notification_count', dr.notification_count,
          'acknowledged_at', dr.acknowledged_at
        )
        order by coalesce(
          nullif(trim(recipient_user.raw_user_meta_data ->> 'full_name'), ''),
          nullif(trim(recipient_user.raw_user_meta_data ->> 'name'), ''),
          nullif(split_part(recipient_user.email, '@', 1), ''),
          recipient_user.email
        ), recipient_user.email
      )
      from public.delivery_recipients dr
      join public.unit_members um on um.id = dr.unit_member_id
      left join auth.users recipient_user on recipient_user.id = dr.user_id
      where dr.delivery_id = p_delivery.id
    ), '[]'::jsonb),
    'attachments', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', da.id,
          'kind', da.kind,
          'bucket_id', da.bucket_id,
          'object_path', da.object_path,
          'file_name', da.file_name,
          'mime_type', da.mime_type,
          'size_bytes', da.size_bytes,
          'expires_at', da.expires_at
        )
        order by da.created_at
      )
      from public.delivery_attachments da
      where da.delivery_id = p_delivery.id
        and da.deleted_at is null
    ), '[]'::jsonb)
  )
  from auth.users received_user
  left join auth.users delivered_user on delivered_user.id = p_delivery.delivered_by_user_id
  where received_user.id = p_delivery.received_by_user_id
$$;

create or replace function public.get_delivery_settings()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select jsonb_build_object(
        'enabled', cds.enabled,
        'reminder_interval_minutes', cds.reminder_interval_minutes,
        'notify_only_once', cds.notify_only_once,
        'attachment_retention_days', cds.attachment_retention_days,
        'source_options', cds.source_options,
        'description_options', cds.description_options,
        'require_received_photo', cds.require_received_photo,
        'require_delivery_photo', cds.require_delivery_photo,
        'require_signature', cds.require_signature
      )
      from public.condominium_delivery_settings cds
      where cds.condominium_id = public.current_user_condominium_id()
      limit 1
    ),
    jsonb_build_object(
      'enabled', true,
      'reminder_interval_minutes', 60,
      'notify_only_once', false,
      'attachment_retention_days', 90,
      'source_options', '["iFood","Rappi","Mercado Livre","Shopee","Amazon","Correios","Sedex","Transportadora","Loggi","Jadlog","Total Express","Uber Flash","Farmacia","Mercado","Morador/Terceiro"]'::jsonb,
      'description_options', '["Comida","Documento","Envelope","Pacote pequeno","Pacote medio","Caixa","Presente","Produto refrigerado"]'::jsonb,
      'require_received_photo', true,
      'require_delivery_photo', false,
      'require_signature', false
    )
  )
$$;

create or replace function public.list_delivery_recipients(p_unit_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_condominium_id uuid := public.current_user_condominium_id();
begin
  if v_condominium_id is null then
    raise exception 'Usuario sem condominio vinculado';
  end if;

  if not public.user_is_active_portaria(v_condominium_id) then
    raise exception 'Apenas a portaria pode listar destinatarios de entregas';
  end if;

  if not exists (
    select 1
    from public.units u
    where u.id = p_unit_id
      and u.condominium_id = v_condominium_id
  ) then
    raise exception 'Unidade nao encontrada';
  end if;

  return (
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'unit_member_id', um.id,
        'user_id', um.user_id,
        'display_name', coalesce(
          nullif(trim(au.raw_user_meta_data ->> 'full_name'), ''),
          nullif(trim(au.raw_user_meta_data ->> 'name'), ''),
          nullif(split_part(au.email, '@', 1), ''),
          au.email
        ),
        'email', au.email,
        'unit_id', um.unit_id,
        'unit_label', public.unit_display_label(um.unit_id)
      )
      order by coalesce(
        nullif(trim(au.raw_user_meta_data ->> 'full_name'), ''),
        nullif(trim(au.raw_user_meta_data ->> 'name'), ''),
        nullif(split_part(au.email, '@', 1), ''),
        au.email
      ), au.email
    ), '[]'::jsonb)
    from public.unit_members um
    join auth.users au on au.id = um.user_id
    where um.unit_id = p_unit_id
      and um.member_type = 'RESIDENT'
      and um.active_for_calls = true
  );
end;
$$;

create or replace function public.list_pending_deliveries(
  p_status_filter text default 'pending',
  p_limit integer default 80
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select case
    when not public.user_is_active_portaria(public.current_user_condominium_id()) then
      '[]'::jsonb
    else coalesce(jsonb_agg(public.delivery_to_json(filtered_delivery) order by filtered_delivery.received_at desc), '[]'::jsonb)
  end
  from (
    select d.*
    from public.deliveries d
    where d.condominium_id = public.current_user_condominium_id()
      and (
        (coalesce(p_status_filter, 'pending') = 'delivered' and d.status = 'DELIVERED')
        or (coalesce(p_status_filter, 'pending') <> 'delivered' and d.status in ('RECEIVED', 'NOTIFIED'))
      )
    order by d.received_at desc
    limit greatest(1, least(coalesce(p_limit, 80), 200))
  ) filtered_delivery
$$;

create or replace function public.count_my_pending_deliveries()
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::integer
  from public.deliveries d
  where d.condominium_id = public.current_user_condominium_id()
    and d.status in ('RECEIVED', 'NOTIFIED')
    and public.user_can_access_delivery(d.id)
$$;

revoke execute on function public.get_delivery_settings() from public;
revoke execute on function public.list_pending_deliveries(text, integer) from public;
revoke execute on function public.count_my_pending_deliveries() from public;

grant execute on function public.get_delivery_settings() to authenticated;
grant execute on function public.list_pending_deliveries(text, integer) to authenticated;
grant execute on function public.count_my_pending_deliveries() to authenticated;
grant execute on function public.delivery_to_json(public.deliveries) to authenticated, service_role;
grant execute on function public.list_delivery_recipients(uuid) to authenticated;
