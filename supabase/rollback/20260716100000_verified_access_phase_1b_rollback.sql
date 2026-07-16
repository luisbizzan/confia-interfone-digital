drop trigger if exists verified_access_network_signals_validate_source_case on public.verified_access_network_signals;
drop function if exists public.verified_access_network_validate_signal_source_case();

drop table if exists public.verified_access_network_appeals;
drop table if exists public.verified_access_network_signal_reviews;
drop table if exists public.verified_access_network_signals;
drop table if exists public.verified_access_network_security_cases;
drop table if exists public.verified_access_network_subject_links;
drop table if exists public.verified_access_network_subject_identifiers;
drop table if exists public.verified_access_network_subjects;

delete from public.condominium_features
where feature_key in (
    'VERIFIED_ACCESS_NETWORK_IDENTITY',
    'VERIFIED_ACCESS_NETWORK_SIGNALS',
    'VERIFIED_ACCESS_NETWORK_HOLD'
  )
  and enabled = false;
