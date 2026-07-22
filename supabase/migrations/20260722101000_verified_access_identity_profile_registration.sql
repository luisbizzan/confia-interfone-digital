alter table public.verified_access_identity_profiles
  add column is_minor boolean,
  add column guardian_name_ciphertext bytea,
  add column guardian_relationship_ciphertext bytea,
  add column privacy_notice_version text,
  add column terms_version text,
  add column acknowledged_at timestamptz,
  add column submitted_at timestamptz;

alter table public.verified_access_identity_profiles
  add constraint verified_access_identity_profiles_registration_bundle_check
  check (
    (
      is_minor is null
      and guardian_name_ciphertext is null
      and guardian_relationship_ciphertext is null
      and privacy_notice_version is null
      and terms_version is null
      and acknowledged_at is null
      and submitted_at is null
    )
    or (
      is_minor is not null
      and nullif(trim(privacy_notice_version), '') is not null
      and char_length(privacy_notice_version) <= 64
      and nullif(trim(terms_version), '') is not null
      and char_length(terms_version) <= 64
      and acknowledged_at is not null
      and submitted_at is not null
      and acknowledged_at <= submitted_at
      and (
        (is_minor and guardian_name_ciphertext is not null and guardian_relationship_ciphertext is not null)
        or (not is_minor and guardian_name_ciphertext is null and guardian_relationship_ciphertext is null)
      )
    )
  ),
  add constraint verified_access_identity_profiles_guardian_key_check
  check (
    (guardian_name_ciphertext is null and guardian_relationship_ciphertext is null)
    or encryption_key_version is not null
  );

comment on column public.verified_access_identity_profiles.is_minor is
  'Server-calculated age category at Phase 3B submission; null for legacy profiles.';
comment on column public.verified_access_identity_profiles.guardian_name_ciphertext is
  'Reversible encrypted guardian name for a minor registration. Never decrypted in SQL.';
comment on column public.verified_access_identity_profiles.guardian_relationship_ciphertext is
  'Reversible encrypted guardian relationship for a minor registration. Never decrypted in SQL.';
comment on column public.verified_access_identity_profiles.privacy_notice_version is
  'Version of the provisional or approved privacy notice acknowledged at submission.';
comment on column public.verified_access_identity_profiles.terms_version is
  'Version of the provisional or approved terms accepted at submission.';
