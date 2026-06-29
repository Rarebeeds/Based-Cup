-- ===== Based Cup add-on #3: remove friends + XP/level =====
-- Safe to run once (whole thing, nothing selected) in the Supabase SQL editor.

-- 1) remove a friendship (either direction). SECURITY DEFINER so it only ever
--    deletes rows that involve the caller.
create or replace function remove_friend(p_other uuid)
returns void language sql security definer set search_path = public as $$
  delete from friendships
  where (requester = auth.uid() and addressee = p_other)
     or (requester = p_other     and addressee = auth.uid());
$$;
grant execute on function remove_friend(uuid) to authenticated;

-- 2) XP on the profile (level is derived from this on the client)
alter table profiles add column if not exists xp int not null default 0;

-- update the public profile lookup to include xp (re-create with the new column)
create or replace function public_profile(p_username citext)
returns table(id uuid, username citext, avatar text, wins int, losses int, xp int)
language sql security definer set search_path = public as $$
  select id, username, avatar, wins, losses, xp from profiles where username = p_username limit 1;
$$;
grant execute on function public_profile(citext) to authenticated;
