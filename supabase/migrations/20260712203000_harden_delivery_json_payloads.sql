create or replace function public.delivery_to_json(p_delivery public.deliveries)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', delivery.id,
    'condominium_id', delivery.condominium_id,
    'unit_id', delivery.unit_id,
    'unit_label', coalesce(public.unit_display_label(delivery.unit_id), 'Unidade'),
    'status', delivery.status,
    'package_source', delivery.package_source,
    'package_description', delivery.package_description,
    'tracking_code', delivery.tracking_code,
    'received_by_user_id', delivery.received_by_user_id,
    'received_by_email', received_user.email,
    'received_by_portaria_device_id', delivery.received_by_portaria_device_id,
    'received_at', delivery.received_at,
    'first_notified_at', delivery.first_notified_at,
    'last_notified_at', delivery.last_notified_at,
    'next_notification_at', delivery.next_notification_at,
    'notification_count', delivery.notification_count,
    'delivered_by_user_id', delivery.delivered_by_user_id,
    'delivered_by_email', delivered_user.email,
    'delivered_to_unit_member_id', delivery.delivered_to_unit_member_id,
    'delivered_to_name', delivery.delivered_to_name,
    'delivered_at', delivery.delivered_at,
    'delivery_observations', delivery.delivery_observations,
    'created_at', delivery.created_at,
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
      left join auth.users recipient_user on recipient_user.id = dr.user_id
      where dr.delivery_id = delivery.id
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
      where da.delivery_id = delivery.id
        and da.deleted_at is null
    ), '[]'::jsonb)
  )
  from (select (p_delivery).*) delivery
  left join auth.users received_user on received_user.id = delivery.received_by_user_id
  left join auth.users delivered_user on delivered_user.id = delivery.delivered_by_user_id
$$;

