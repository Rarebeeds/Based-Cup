-- social-schema-add4.sql
-- Global counters (used for the "goy<N>" guest numbering + "X players have
-- jumped in as guests" line on the login screen). Run this once in the
-- Supabase SQL editor. Safe to re-run.

create table if not exists public.counters (
  name text primary key,
  n    bigint not null default 0
);

-- atomically increment a named counter and return the new value
create or replace function public.bump_counter(p_name text)
returns bigint
language sql
security definer
set search_path = public
as $$
  insert into public.counters(name, n) values (p_name, 1)
  on conflict (name) do update set n = public.counters.n + 1
  returning n;
$$;

-- read a counter without changing it (for display)
create or replace function public.get_counter(p_name text)
returns bigint
language sql
security definer
set search_path = public
as $$
  select coalesce((select n from public.counters where name = p_name), 0);
$$;

-- guests bump the counter while still anonymous (before they sign up),
-- so anon must be allowed to execute these.
grant execute on function public.bump_counter(text) to anon, authenticated;
grant execute on function public.get_counter(text)  to anon, authenticated;
