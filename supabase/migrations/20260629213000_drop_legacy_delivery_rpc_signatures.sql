drop function if exists public.list_my_deliveries();

revoke execute on function public.list_my_deliveries(integer, integer) from public;
grant execute on function public.list_my_deliveries(integer, integer) to authenticated;
