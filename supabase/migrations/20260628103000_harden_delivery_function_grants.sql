revoke execute on function public.cleanup_expired_delivery_attachments() from anon, public;
revoke execute on function public.complete_delivery(uuid, uuid, text, text, jsonb) from anon, public;
revoke execute on function public.count_my_pending_deliveries() from anon, public;
revoke execute on function public.create_delivery(uuid, uuid[], text, text, text, jsonb) from anon, public;
revoke execute on function public.delivery_to_json(public.deliveries) from anon, public;
revoke execute on function public.get_delivery_settings() from anon, public;
revoke execute on function public.list_delivery_recipients(uuid) from anon, public;
revoke execute on function public.list_my_deliveries() from anon, public;
revoke execute on function public.list_pending_deliveries() from anon, public;
revoke execute on function public.list_pending_deliveries(text, integer) from anon, public;
revoke execute on function public.user_can_access_delivery(uuid) from anon, public;

grant execute on function public.complete_delivery(uuid, uuid, text, text, jsonb) to authenticated;
grant execute on function public.count_my_pending_deliveries() to authenticated;
grant execute on function public.create_delivery(uuid, uuid[], text, text, text, jsonb) to authenticated;
grant execute on function public.get_delivery_settings() to authenticated;
grant execute on function public.list_delivery_recipients(uuid) to authenticated;
grant execute on function public.list_my_deliveries() to authenticated;
grant execute on function public.list_pending_deliveries() to authenticated;
grant execute on function public.list_pending_deliveries(text, integer) to authenticated;

grant execute on function public.cleanup_expired_delivery_attachments() to service_role;
grant execute on function public.delivery_to_json(public.deliveries) to authenticated, service_role;
grant execute on function public.user_can_access_delivery(uuid) to authenticated, service_role;
