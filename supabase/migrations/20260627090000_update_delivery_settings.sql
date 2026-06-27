alter table public.condominium_delivery_settings
  add column if not exists require_received_photo boolean not null default false,
  add column if not exists require_delivery_photo boolean not null default false,
  add column if not exists require_signature boolean not null default false;

comment on column public.condominium_delivery_settings.require_received_photo is
  'Quando verdadeiro, o fluxo da portaria deve exigir foto da encomenda no recebimento.';

comment on column public.condominium_delivery_settings.require_delivery_photo is
  'Quando verdadeiro, o fluxo da portaria deve exigir foto no ato da retirada.';

comment on column public.condominium_delivery_settings.require_signature is
  'Quando verdadeiro, o fluxo da portaria deve exigir assinatura digital no ato da retirada.';
