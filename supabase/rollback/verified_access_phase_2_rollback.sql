revoke execute on function public.verified_access_list_resident_service_types(uuid) from public, anon, authenticated, service_role;
revoke execute on function public.verified_access_create_resident_request(uuid, text, text, text, timestamptz, timestamptz, text, text, integer, text, text) from public, anon, authenticated, service_role;
revoke execute on function public.verified_access_list_resident_requests(text, text, timestamptz, timestamptz, timestamptz, uuid, integer) from public, anon, authenticated, service_role;
revoke execute on function public.verified_access_get_resident_request(uuid) from public, anon, authenticated, service_role;
revoke execute on function public.verified_access_cancel_resident_request(uuid, text, text, text) from public, anon, authenticated, service_role;

revoke verified_access_phase2_resident_executor from authenticated;
revoke execute on function public.verified_access_list_resident_service_types(uuid) from verified_access_phase2_resident_executor;
revoke execute on function public.verified_access_create_resident_request(uuid, text, text, text, timestamptz, timestamptz, text, text, integer, text, text) from verified_access_phase2_resident_executor;
revoke execute on function public.verified_access_list_resident_requests(text, text, timestamptz, timestamptz, timestamptz, uuid, integer) from verified_access_phase2_resident_executor;
revoke execute on function public.verified_access_get_resident_request(uuid) from verified_access_phase2_resident_executor;
revoke execute on function public.verified_access_cancel_resident_request(uuid, text, text, text) from verified_access_phase2_resident_executor;

drop function if exists public.verified_access_cancel_resident_request(uuid, text, text, text);
drop function if exists public.verified_access_get_resident_request(uuid);
drop function if exists public.verified_access_list_resident_requests(text, text, timestamptz, timestamptz, timestamptz, uuid, integer);
drop function if exists public.verified_access_create_resident_request(uuid, text, text, text, timestamptz, timestamptz, text, text, integer, text, text);
drop function if exists public.verified_access_list_resident_service_types(uuid);

drop function if exists public.verified_access_phase2_fingerprint(jsonb);
drop function if exists public.verified_access_phase2_normalize_text(text, integer);
drop function if exists public.verified_access_phase2_assert_resident_unit(uuid, uuid, uuid);
drop function if exists public.verified_access_phase2_assert_feature(uuid);
drop function if exists public.verified_access_phase2_context();

drop table if exists public.verified_access_request_commands;

drop role if exists verified_access_phase2_resident_executor;
