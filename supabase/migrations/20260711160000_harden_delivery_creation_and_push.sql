alter table public.deliveries
  add column if not exists client_request_id text;

create unique index if not exists ux_deliveries_client_request
  on public.deliveries (condominium_id, received_by_user_id, client_request_id)
  where client_request_id is not null;

drop function if exists public.create_delivery(uuid, uuid[], text, text, text, jsonb);

create or replace function public.create_delivery(
  p_unit_id uuid,
  p_recipient_unit_member_ids uuid[],
  p_package_description text,
  p_package_source text default null,
  p_tracking_code text default null,
  p_attachments jsonb default '[]'::jsonb,
  p_client_request_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_condominium_id uuid := public.current_user_condominium_id();
  v_device_id uuid;
  v_settings public.condominium_delivery_settings;
  v_delivery public.deliveries;
  v_member_id uuid;
  v_attachment jsonb;
  v_object_path text;
  v_file_name text;
  v_mime_type text;
  v_size_bytes integer;
  v_kind text;
  v_client_request_id text := nullif(trim(coalesce(p_client_request_id, '')), '');
begin
  if v_condominium_id is null then
    raise exception 'Usuario sem condominio vinculado';
  end if;

  if v_client_request_id is not null then
    select d.*
      into v_delivery
    from public.deliveries d
    where d.condominium_id = v_condominium_id
      and d.received_by_user_id = auth.uid()
      and d.client_request_id = v_client_request_id
    order by d.created_at desc
    limit 1;

    if found then
      return public.delivery_to_json(v_delivery);
    end if;
  end if;

  if not public.condominium_feature_enabled(v_condominium_id, 'DELIVERIES') then
    raise exception 'Entregas nao habilitadas para este condominio';
  end if;

  if not public.user_is_active_portaria(v_condominium_id) then
    raise exception 'Apenas a portaria pode cadastrar entregas';
  end if;

  select *
    into v_settings
  from public.condominium_delivery_settings cds
  where cds.condominium_id = v_condominium_id;

  if coalesce(v_settings.enabled, true) is false then
    raise exception 'Entregas desativadas para este condominio';
  end if;

  select pd.id
    into v_device_id
  from public.portaria_devices pd
  where pd.condominium_id = v_condominium_id
    and pd.user_id = auth.uid()
    and pd.is_active = true
  order by pd.priority_order, pd.created_at
  limit 1;

  if not exists (
    select 1
    from public.units u
    where u.id = p_unit_id
      and u.condominium_id = v_condominium_id
  ) then
    raise exception 'Unidade nao encontrada';
  end if;

  if coalesce(array_length(p_recipient_unit_member_ids, 1), 0) = 0 then
    raise exception 'Selecione pelo menos um morador destinatario';
  end if;

  insert into public.deliveries (
    client_request_id,
    condominium_id,
    unit_id,
    package_source,
    package_description,
    tracking_code,
    received_by_user_id,
    received_by_portaria_device_id,
    next_notification_at
  )
  values (
    v_client_request_id,
    v_condominium_id,
    p_unit_id,
    nullif(trim(coalesce(p_package_source, '')), ''),
    nullif(trim(coalesce(p_package_description, '')), ''),
    nullif(trim(coalesce(p_tracking_code, '')), ''),
    auth.uid(),
    v_device_id,
    now()
  )
  on conflict (condominium_id, received_by_user_id, client_request_id)
    where client_request_id is not null
  do update set updated_at = public.deliveries.updated_at
  returning * into v_delivery;

  foreach v_member_id in array p_recipient_unit_member_ids loop
    insert into public.delivery_recipients (delivery_id, unit_member_id, user_id)
    select v_delivery.id, um.id, um.user_id
    from public.unit_members um
    where um.id = v_member_id
      and um.unit_id = p_unit_id
      and um.member_type = 'RESIDENT'
      and um.active_for_calls = true
    on conflict do nothing;
  end loop;

  if not exists (select 1 from public.delivery_recipients dr where dr.delivery_id = v_delivery.id) then
    raise exception 'Nenhum destinatario valido encontrado';
  end if;

  for v_attachment in select * from jsonb_array_elements(coalesce(p_attachments, '[]'::jsonb)) loop
    v_kind := upper(coalesce(v_attachment ->> 'kind', 'RECEIVED_PHOTO'));
    v_object_path := v_attachment ->> 'object_path';
    v_file_name := coalesce(v_attachment ->> 'file_name', 'anexo');
    v_mime_type := coalesce(v_attachment ->> 'mime_type', 'application/octet-stream');
    v_size_bytes := coalesce((v_attachment ->> 'size_bytes')::integer, 0);

    if v_kind not in ('RECEIVED_PHOTO', 'DELIVERY_PHOTO', 'SIGNATURE') then
      raise exception 'Tipo de anexo invalido';
    end if;

    if v_object_path is null or not starts_with(v_object_path, v_condominium_id::text || '/' || auth.uid()::text || '/') then
      raise exception 'Caminho de anexo invalido';
    end if;

    insert into public.delivery_attachments (
      delivery_id,
      kind,
      object_path,
      file_name,
      mime_type,
      size_bytes,
      created_by_user_id,
      expires_at
    )
    values (
      v_delivery.id,
      v_kind,
      v_object_path,
      v_file_name,
      v_mime_type,
      v_size_bytes,
      auth.uid(),
      now() + make_interval(days => coalesce(v_settings.attachment_retention_days, 90))
    )
    on conflict (bucket_id, object_path) do nothing;
  end loop;

  insert into public.delivery_audit_events (delivery_id, condominium_id, actor_user_id, event_type, metadata)
  values (
    v_delivery.id,
    v_condominium_id,
    auth.uid(),
    'CREATED',
    jsonb_build_object(
      'client_request_id', v_client_request_id,
      'recipient_count', (select count(*) from public.delivery_recipients dr where dr.delivery_id = v_delivery.id)
    )
  )
  on conflict do nothing;

  return public.delivery_to_json(v_delivery);
end;
$$;

revoke execute on function public.create_delivery(uuid, uuid[], text, text, text, jsonb, text) from public;
grant execute on function public.create_delivery(uuid, uuid[], text, text, text, jsonb, text) to authenticated;
