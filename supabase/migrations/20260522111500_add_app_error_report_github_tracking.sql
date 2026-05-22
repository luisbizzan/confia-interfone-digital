alter table public.app_error_reports
  add column if not exists signature text,
  add column if not exists occurrence_count integer not null default 1,
  add column if not exists last_seen_at timestamptz not null default now(),
  add column if not exists github_issue_number integer,
  add column if not exists github_issue_url text;

create index if not exists idx_app_error_reports_signature
on public.app_error_reports(signature)
where signature is not null;

create index if not exists idx_app_error_reports_github_issue_number
on public.app_error_reports(github_issue_number)
where github_issue_number is not null;
