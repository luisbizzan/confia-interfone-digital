alter table public.call_attempts
drop constraint if exists call_attempts_status_check;

update public.call_attempts
set status = 'NO_ANSWER'
where status = 'TIMEOUT';

alter table public.call_attempts
add constraint call_attempts_status_check
check (status in ('RINGING', 'ANSWERED', 'NO_ANSWER', 'FAILED'));
