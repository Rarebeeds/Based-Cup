-- ===== Based Cup: add-on for profile pictures + inbox/leaderboard lookups =====
-- Safe to run once. Run the whole thing (nothing selected) in Supabase SQL editor.

-- 1) store a small profile picture (a compressed data URL) on each profile
alter table profiles add column if not exists avatar text;

-- 2) look up usernames for a set of user ids (used by the Messages/inbox screen).
--    SECURITY DEFINER so it can read usernames only -- wallets are never exposed.
create or replace function names_for(ids uuid[])
returns table(id uuid, username citext)
language sql security definer set search_path = public as $$
  select id, username from profiles where id = any(ids);
$$;
grant execute on function names_for(uuid[]) to authenticated;

-- 3) look up profile pictures for a set of usernames (used by the leaderboard).
--    Returns only username + avatar -- again, no wallet.
create or replace function avatars_for(p_names text[])
returns table(username citext, avatar text)
language sql security definer set search_path = public as $$
  select username, avatar from profiles where username = any(p_names);
$$;
grant execute on function avatars_for(text[]) to authenticated;
