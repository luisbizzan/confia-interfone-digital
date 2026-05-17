insert into public.roles (name)
values ('ADMIN'), ('MANAGER'), ('MORADOR'), ('PORTARIA')
on conflict (name) do nothing;
