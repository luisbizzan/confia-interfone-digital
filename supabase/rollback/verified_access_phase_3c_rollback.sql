revoke verified_access_phase3c_maintenance_executor from service_role;

revoke execute on function public.verified_access_expire_invitations(integer, boolean, text)
from verified_access_phase3c_maintenance_executor;
revoke execute on function public.verified_access_expire_public_sessions(integer, boolean, text)
from verified_access_phase3c_maintenance_executor;
revoke execute on function public.verified_access_purge_public_commands(integer, boolean, text)
from verified_access_phase3c_maintenance_executor;
revoke execute on function public.verified_access_purge_rate_limit_buckets(integer, boolean, text)
from verified_access_phase3c_maintenance_executor;
revoke execute on function public.verified_access_reconcile_public_registration_state(integer, boolean, text)
from verified_access_phase3c_maintenance_executor;
revoke execute on function public.verified_access_process_outbox(integer, boolean, text)
from verified_access_phase3c_maintenance_executor;
revoke execute on function public.verified_access_apply_retention_policy(integer, boolean, text)
from verified_access_phase3c_maintenance_executor;

drop function public.verified_access_apply_retention_policy(integer, boolean, text);
drop function public.verified_access_process_outbox(integer, boolean, text);
drop function public.verified_access_reconcile_public_registration_state(integer, boolean, text);
drop function public.verified_access_purge_rate_limit_buckets(integer, boolean, text);
drop function public.verified_access_purge_public_commands(integer, boolean, text);
drop function public.verified_access_expire_public_sessions(integer, boolean, text);
drop function public.verified_access_expire_invitations(integer, boolean, text);

drop function public.verified_access_phase3c_result(
  text,
  boolean,
  integer,
  integer,
  integer,
  integer
);
drop function public.verified_access_phase3c_record_finding(
  uuid,
  text,
  uuid,
  uuid,
  text,
  text
);
drop function public.verified_access_phase3c_assert_job_input(integer, boolean, text);

drop role verified_access_phase3c_maintenance_executor;

drop index public.idx_verified_access_outbox_processing_lease;
drop index public.idx_verified_access_outbox_processed_retention;
drop index public.idx_verified_access_public_commands_processing_age;
drop index public.idx_verified_access_public_commands_completed_retention;
drop index public.idx_verified_access_public_sessions_terminal_retention;
drop index public.idx_verified_access_invitations_terminal_retention;

drop table public.verified_access_maintenance_findings;
