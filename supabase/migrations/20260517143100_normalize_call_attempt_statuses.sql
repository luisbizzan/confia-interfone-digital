update public.call_attempts
set status = 'NO_ANSWER'
where status = 'TIMEOUT';
