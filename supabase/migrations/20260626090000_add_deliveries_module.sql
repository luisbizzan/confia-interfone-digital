insert into public.condominium_features (condominium_id, feature_key, enabled)
select id, 'DELIVERIES', true
from public.condominiums
on conflict (condominium_id, feature_key) do nothing;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'delivery-attachments',
  'delivery-attachments',
  false,
  10485760,
  array[
    'image/jpeg',
    'image/png',
    'image/webp',
    'application/pdf'
  ]
)
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

create table if not exists public.condominium_delivery_settings (
  condominium_id uuid primary key references public.condominiums(id) on delete cascade,
  enabled boolean not null default true,
  reminder_interval_minutes integer not null default 60,
  notify_only_once boolean not null default false,
  attachment_retention_days integer not null default 90,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint condominium_delivery_reminder_check
    check (reminder_interval_minutes between 5 and 1440),
  constraint condominium_delivery_retention_check
    check (attachment_retention_days between 1 and 365)
);

insert into public.condominium_delivery_settings (condominium_id)
select id
from public.condominiums
on conflict (condominium_id) do nothing;

create table if not exists public.deliveries (
  id uuid primary key default gen_random_uuid(),
  condominium_id uuid not null references public.condominiums(id) on delete cascade,
  unit_id uuid not null references public.units(id) on delete cascade,
  status text not null default 'RECEIVED',
  package_source text,
  package_description text not null,
  tracking_code text,
  received_by_user_id uuid not null references auth.users(id),
  received_by_portaria_device_id uuid references public.portaria_devices(id),
  received_at timestamptz not null default now(),
  first_notified_at timestamptz,
  last_notified_at timestamptz,
  next_notification_at timestamptz,
  notification_count integer not null default 0,
  delivered_by_user_id uuid references auth.users(id),
  delivered_to_unit_member_id uuid references public.unit_members(id),
  delivered_to_name text,
  delivered_at timestamptz,
  delivery_observations text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint deliveries_status_check
    check (status in ('RECEIVED', 'NOTIFIED', 'DELIVERED', 'CANCELLED', 'RETURNED')),
  constraint deliveries_description_size_check
    check (char_length(package_description) between 1 and 500)
);

create index if not exists idx_deliveries_condominium_status
on public.deliveries(condominium_id, status, received_at desc);

create index if not exists idx_deliveries_unit_status
on public.deliveries(unit_id, status, received_at desc);

create table if not exists public.delivery_recipients (
  id uuid primary key default gen_random_uuid(),
  delivery_id uuid not null references public.deliveries(id) on delete cascade,
  unit_member_id uuid not null references public.unit_members(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  notified_at timestamptz,
  notification_count integer not null default 0,
  acknowledged_at timestamptz,
  created_at timestamptz not null default now(),
  unique (delivery_id, user_id)
);

create index if not exists idx_delivery_recipients_user
on public.delivery_recipients(user_id, created_at desc);

create table if not exists public.delivery_attachments (
  id uuid primary key default gen_random_uuid(),
  delivery_id uuid not null references public.deliveries(id) on delete cascade,
  kind text not null,
  bucket_id text not null default 'delivery-attachments',
  object_path text not null,
  file_name text not null,
  mime_type text not null,
  size_bytes integer not null,
  created_by_user_id uuid not null references auth.users(id),
  expires_at timestamptz not null default (now() + interval '90 days'),
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint delivery_attachments_bucket_check
    check (bucket_id = 'delivery-attachments'),
  constraint delivery_attachments_kind_check
    check (kind in ('RECEIVED_PHOTO', 'DELIVERY_PHOTO', 'SIGNATURE')),
  constraint delivery_attachments_size_check
    check (size_bytes > 0 and size_bytes <= 10485760)
);

create unique index if not exists ux_delivery_attachments_object_path
on public.delivery_attachments(bucket_id, object_path);

create index if not exists idx_delivery_attachments_expires
on public.delivery_attachments(expires_at)
where deleted_at is null;

create table if not exists public.delivery_audit_events (
  id uuid primary key default gen_random_uuid(),
  delivery_id uuid not null references public.deliveries(id) on delete cascade,
  condominium_id uuid not null references public.condominiums(id) on delete cascade,
  actor_user_id uuid references auth.users(id),
  event_type text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint delivery_audit_event_type_check
    check (event_type in ('CREATED', 'NOTIFIED', 'ACKNOWLEDGED', 'DELIVERED', 'CANCELLED', 'RETURNED', 'PHOTO_ADDED', 'SIGNATURE_ADDED'))
);

create index if not exists idx_delivery_audit_delivery
on public.delivery_audit_events(delivery_id, created_at desc);

alter table public.condominium_delivery_settings enable row level security;
alter table public.deliveries enable row level security;
alter table public.delivery_recipients enable row level security;
alter table public.delivery_attachments enable row level security;
alter table public.delivery_audit_events enable row level security;

create or replace function public.user_can_access_delivery(p_delivery_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.deliveries d
    where d.id = p_delivery_id
      and d.condominium_id = public.current_user_condominium_id()
      and (
        public.user_is_active_portaria(d.condominium_id)
        or exists (
          select 1
          from public.delivery_recipients dr
          where dr.delivery_id = d.id
            and dr.user_id = auth.uid()
        )
      )
  )
$$;

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
          'email', recipient_user.email,
          'notified_at', dr.notified_at,
          'notification_count', dr.notification_count,
          'acknowledged_at', dr.acknowledged_at
        )
        order by recipient_user.email
      )
      from public.delivery_recipients dr
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
        'email', au.email,
        'unit_id', um.unit_id,
        'unit_label', public.unit_display_label(um.unit_id)
      )
      order by au.email
    ), '[]'::jsonb)
    from public.unit_members um
    join auth.users au on au.id = um.user_id
    where um.unit_id = p_unit_id
      and um.member_type = 'RESIDENT'
      and um.active_for_calls = true
  );
end;
$$;

create or replace function public.create_delivery(
  p_unit_id uuid,
  p_recipient_unit_member_ids uuid[],
  p_package_description text,
  p_package_source text default null,
  p_tracking_code text default null,
  p_attachments jsonb default '[]'::jsonb
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
begin
  if v_condominium_id is null then
    raise exception 'Usuario sem condominio vinculado';
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
    v_condominium_id,
    p_unit_id,
    nullif(trim(coalesce(p_package_source, '')), ''),
    nullif(trim(coalesce(p_package_description, '')), ''),
    nullif(trim(coalesce(p_tracking_code, '')), ''),
    auth.uid(),
    v_device_id,
    now()
  )
  returning * into v_delivery;

  foreach v_member_id in array p_recipient_unit_member_ids loop
    insert into public.delivery_recipients (delivery_id, unit_member_id, user_id)
    select v_delivery.id, um.id, um.user_id
    from public.unit_members um
    where um.id = v_member_id
      and um.unit_id = p_unit_id
      and um.member_type = 'RESIDENT'
      and um.active_for_calls = true;
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
    );
  end loop;

  insert into public.delivery_audit_events (delivery_id, condominium_id, actor_user_id, event_type, metadata)
  values (
    v_delivery.id,
    v_condominium_id,
    auth.uid(),
    'CREATED',
    jsonb_build_object('recipient_count', (select count(*) from public.delivery_recipients dr where dr.delivery_id = v_delivery.id))
  );

  return public.delivery_to_json(v_delivery);
end;
$$;

create or replace function public.list_pending_deliveries()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select case
    when not public.user_is_active_portaria(public.current_user_condominium_id()) then
      '[]'::jsonb
    else coalesce(jsonb_agg(public.delivery_to_json(d) order by d.received_at desc), '[]'::jsonb)
  end
  from public.deliveries d
  where d.condominium_id = public.current_user_condominium_id()
    and d.status in ('RECEIVED', 'NOTIFIED')
$$;

create or replace function public.list_my_deliveries()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(public.delivery_to_json(d) order by d.received_at desc), '[]'::jsonb)
  from public.deliveries d
  where d.condominium_id = public.current_user_condominium_id()
    and public.user_can_access_delivery(d.id)
$$;

create or replace function public.complete_delivery(
  p_delivery_id uuid,
  p_delivered_to_unit_member_id uuid default null,
  p_delivered_to_name text default null,
  p_observations text default null,
  p_attachments jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_condominium_id uuid := public.current_user_condominium_id();
  v_delivery public.deliveries;
  v_settings public.condominium_delivery_settings;
  v_attachment jsonb;
  v_object_path text;
  v_file_name text;
  v_mime_type text;
  v_size_bytes integer;
  v_kind text;
begin
  select *
    into v_delivery
  from public.deliveries d
  where d.id = p_delivery_id
    and d.condominium_id = v_condominium_id
    and d.status in ('RECEIVED', 'NOTIFIED');

  if v_delivery.id is null then
    raise exception 'Entrega nao encontrada ou ja finalizada';
  end if;

  if not public.user_is_active_portaria(v_condominium_id) then
    raise exception 'Apenas a portaria pode finalizar entregas';
  end if;

  select *
    into v_settings
  from public.condominium_delivery_settings cds
  where cds.condominium_id = v_condominium_id;

  update public.deliveries
    set status = 'DELIVERED',
        delivered_by_user_id = auth.uid(),
        delivered_to_unit_member_id = p_delivered_to_unit_member_id,
        delivered_to_name = nullif(trim(coalesce(p_delivered_to_name, '')), ''),
        delivered_at = now(),
        delivery_observations = nullif(trim(coalesce(p_observations, '')), ''),
        updated_at = now()
  where id = p_delivery_id
  returning * into v_delivery;

  for v_attachment in select * from jsonb_array_elements(coalesce(p_attachments, '[]'::jsonb)) loop
    v_kind := upper(coalesce(v_attachment ->> 'kind', 'DELIVERY_PHOTO'));
    v_object_path := v_attachment ->> 'object_path';
    v_file_name := coalesce(v_attachment ->> 'file_name', 'anexo');
    v_mime_type := coalesce(v_attachment ->> 'mime_type', 'application/octet-stream');
    v_size_bytes := coalesce((v_attachment ->> 'size_bytes')::integer, 0);

    if v_kind not in ('DELIVERY_PHOTO', 'SIGNATURE') then
      raise exception 'Tipo de anexo invalido para entrega';
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
    );
  end loop;

  insert into public.delivery_audit_events (delivery_id, condominium_id, actor_user_id, event_type, metadata)
  values (
    v_delivery.id,
    v_condominium_id,
    auth.uid(),
    'DELIVERED',
    jsonb_build_object('delivered_to_unit_member_id', p_delivered_to_unit_member_id)
  );

  return public.delivery_to_json(v_delivery);
end;
$$;

create or replace function public.cleanup_expired_delivery_attachments()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  update public.delivery_attachments
    set deleted_at = now()
  where deleted_at is null
    and expires_at <= now();

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

create policy "delivery settings are visible to same condominium"
on public.condominium_delivery_settings
for select
to authenticated
using (condominium_id = public.current_user_condominium_id());

create policy "deliveries are visible to allowed users"
on public.deliveries
for select
to authenticated
using (public.user_can_access_delivery(id));

create policy "delivery recipients are visible to recipient or portaria"
on public.delivery_recipients
for select
to authenticated
using (
  user_id = auth.uid()
  or exists (
    select 1
    from public.deliveries d
    where d.id = delivery_recipients.delivery_id
      and public.user_is_active_portaria(d.condominium_id)
  )
);

create policy "delivery attachments are visible with delivery"
on public.delivery_attachments
for select
to authenticated
using (public.user_can_access_delivery(delivery_id));

create policy "delivery audit is visible with delivery"
on public.delivery_audit_events
for select
to authenticated
using (public.user_can_access_delivery(delivery_id));

create policy "delivery attachment upload path is scoped"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'delivery-attachments'
  and (storage.foldername(name))[1] = public.current_user_condominium_id()::text
  and (storage.foldername(name))[2] = auth.uid()::text
);

create policy "delivery attachment read path is scoped"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'delivery-attachments'
  and (storage.foldername(name))[1] = public.current_user_condominium_id()::text
);

revoke all on public.condominium_delivery_settings from public;
revoke all on public.deliveries from public;
revoke all on public.delivery_recipients from public;
revoke all on public.delivery_attachments from public;
revoke all on public.delivery_audit_events from public;

grant select on public.condominium_delivery_settings to authenticated;
grant select on public.deliveries to authenticated;
grant select on public.delivery_recipients to authenticated;
grant select on public.delivery_attachments to authenticated;
grant select on public.delivery_audit_events to authenticated;

revoke execute on function public.user_can_access_delivery(uuid) from public;
revoke execute on function public.delivery_to_json(public.deliveries) from public;
revoke execute on function public.list_delivery_recipients(uuid) from public;
revoke execute on function public.create_delivery(uuid, uuid[], text, text, text, jsonb) from public;
revoke execute on function public.list_pending_deliveries() from public;
revoke execute on function public.list_my_deliveries() from public;
revoke execute on function public.complete_delivery(uuid, uuid, text, text, jsonb) from public;
revoke execute on function public.cleanup_expired_delivery_attachments() from public;

grant execute on function public.user_can_access_delivery(uuid) to authenticated, service_role;
grant execute on function public.delivery_to_json(public.deliveries) to authenticated, service_role;
grant execute on function public.list_delivery_recipients(uuid) to authenticated;
grant execute on function public.create_delivery(uuid, uuid[], text, text, text, jsonb) to authenticated;
grant execute on function public.list_pending_deliveries() to authenticated;
grant execute on function public.list_my_deliveries() to authenticated;
grant execute on function public.complete_delivery(uuid, uuid, text, text, jsonb) to authenticated;
grant execute on function public.cleanup_expired_delivery_attachments() to service_role;
