alter table public.verified_access_network_subjects enable row level security;
alter table public.verified_access_network_subject_identifiers enable row level security;
alter table public.verified_access_network_subject_links enable row level security;
alter table public.verified_access_network_security_cases enable row level security;
alter table public.verified_access_network_signals enable row level security;
alter table public.verified_access_network_signal_reviews enable row level security;
alter table public.verified_access_network_appeals enable row level security;

revoke all on table public.verified_access_network_subjects from public, anon, authenticated, service_role;
revoke all on table public.verified_access_network_subject_identifiers from public, anon, authenticated, service_role;
revoke all on table public.verified_access_network_subject_links from public, anon, authenticated, service_role;
revoke all on table public.verified_access_network_security_cases from public, anon, authenticated, service_role;
revoke all on table public.verified_access_network_signals from public, anon, authenticated, service_role;
revoke all on table public.verified_access_network_signal_reviews from public, anon, authenticated, service_role;
revoke all on table public.verified_access_network_appeals from public, anon, authenticated, service_role;
