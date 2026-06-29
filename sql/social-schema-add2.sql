-- ===== Based Cup add-on #2: public profiles, win/loss on profile, comments =====
-- Safe to run once (whole thing, nothing selected) in the Supabase SQL editor.

-- 1) keep a public win/loss tally on the profile
alter table profiles add column if not exists wins   int not null default 0;
alter table profiles add column if not exists losses int not null default 0;

-- 2) read another player's PUBLIC profile (never the wallet)
create or replace function public_profile(p_username citext)
returns table(id uuid, username citext, avatar text, wins int, losses int)
language sql security definer set search_path = public as $$
  select id, username, avatar, wins, losses from profiles where username = p_username limit 1;
$$;
grant execute on function public_profile(citext) to authenticated;

-- 3) comments left on a player's profile
create table if not exists comments (
  id          bigint generated always as identity primary key,
  profile_id  uuid not null references profiles(id) on delete cascade,
  author_id   uuid not null references profiles(id) on delete cascade,
  author_name citext not null,
  body        text not null check (char_length(body) between 1 and 280),
  created_at  timestamptz not null default now()
);
alter table comments enable row level security;
drop policy if exists "write comments" on comments;
create policy "write comments" on comments for insert with check (auth.uid() = author_id);

-- read a profile's comments (SECURITY DEFINER so any signed-in player can view them)
create or replace function comments_for(p_profile uuid, p_limit int default 50)
returns table(author_name citext, body text, created_at timestamptz)
language sql security definer set search_path = public as $$
  select author_name, body, created_at from comments
  where profile_id = p_profile order by created_at desc limit p_limit;
$$;
grant execute on function comments_for(uuid, int) to authenticated;
