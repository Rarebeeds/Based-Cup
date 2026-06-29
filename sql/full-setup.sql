-- ============================================================
--  BASED CUP — FULL SCHEMA (everything in one go)
--  Paste the whole file into the Supabase SQL editor and Run.
--  Idempotent + safe to re-run: tables use IF NOT EXISTS, policies are
--  dropped-then-created, functions use CREATE OR REPLACE, and the realtime
--  publication adds are guarded. Equivalent to running
--  social-schema.sql + add.sql + add2..add5 in order.
-- ============================================================

create extension if not exists citext;   -- case-insensitive usernames

-- ============================================================
--  PROFILES (one row per player)
-- ============================================================
create table if not exists profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  username   citext unique not null,
  wallet     text,
  created_at timestamptz not null default now()
);
-- columns added by later add-ons (safe whether or not they ran before)
alter table profiles add column if not exists avatar text;
alter table profiles add column if not exists wins   int  not null default 0;
alter table profiles add column if not exists losses int  not null default 0;
alter table profiles add column if not exists xp     int  not null default 0;
alter table profiles add column if not exists coins  int  not null default 1000;

alter table profiles enable row level security;
drop policy if exists "own profile read"   on profiles;
drop policy if exists "own profile insert" on profiles;
drop policy if exists "own profile update" on profiles;
create policy "own profile read"   on profiles for select using (auth.uid() = id);
create policy "own profile insert" on profiles for insert with check (auth.uid() = id);
create policy "own profile update" on profiles for update using (auth.uid() = id);

-- ============================================================
--  FRIENDSHIPS
-- ============================================================
create table if not exists friendships (
  id         bigint generated always as identity primary key,
  requester  uuid not null references profiles(id) on delete cascade,
  addressee  uuid not null references profiles(id) on delete cascade,
  status     text not null default 'pending' check (status in ('pending','accepted')),
  created_at timestamptz not null default now(),
  unique (requester, addressee)
);
alter table friendships enable row level security;
drop policy if exists "see my friendships"  on friendships;
drop policy if exists "send friend request" on friendships;
drop policy if exists "respond to request"  on friendships;
create policy "see my friendships"  on friendships for select using (auth.uid() = requester or auth.uid() = addressee);
create policy "send friend request" on friendships for insert with check (auth.uid() = requester);
create policy "respond to request"  on friendships for update using (auth.uid() = addressee);

-- ============================================================
--  MESSAGES (direct chat)
-- ============================================================
create table if not exists messages (
  id         bigint generated always as identity primary key,
  sender     uuid not null references profiles(id) on delete cascade,
  recipient  uuid not null references profiles(id) on delete cascade,
  body       text not null check (char_length(body) between 1 and 500),
  created_at timestamptz not null default now()
);
alter table messages enable row level security;
drop policy if exists "see my messages"  on messages;
drop policy if exists "send my messages" on messages;
create policy "see my messages"  on messages for select using (auth.uid() = sender or auth.uid() = recipient);
create policy "send my messages"  on messages for insert with check (auth.uid() = sender);
create index if not exists idx_messages_pair on messages (sender, recipient, created_at);

-- ============================================================
--  COMMENTS (left on a player's profile)
-- ============================================================
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

-- ============================================================
--  COUNTERS (guest "goy<N>" numbering)
-- ============================================================
create table if not exists public.counters (
  name text primary key,
  n    bigint not null default 0
);

-- ============================================================
--  WAGER CONFIRMATIONS (one row per player per match)
-- ============================================================
create table if not exists wager_matches (
  match_id   text  not null,
  reporter   uuid  not null references profiles(id) on delete cascade,
  opponent   uuid  not null,
  amount     int   not null default 0,
  winner     uuid,
  settled    boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (match_id, reporter)
);
alter table wager_matches enable row level security;   -- no policies => settle_match() (definer) is the only writer

-- ============================================================
--  FUNCTIONS (all SECURITY DEFINER; never expose wallets)
-- ============================================================
create or replace function find_profile(p_username citext)
returns table(id uuid, username citext)
language sql security definer set search_path = public as $$
  select id, username from profiles where username = p_username limit 1;
$$;
grant execute on function find_profile(citext) to authenticated;

create or replace function my_friends()
returns table(friend_id uuid, username citext, status text, incoming boolean)
language sql security definer set search_path = public as $$
  select case when f.requester = auth.uid() then f.addressee else f.requester end,
         p.username, f.status,
         (f.addressee = auth.uid() and f.status = 'pending')
  from friendships f
  join profiles p on p.id = (case when f.requester = auth.uid() then f.addressee else f.requester end)
  where f.requester = auth.uid() or f.addressee = auth.uid();
$$;
grant execute on function my_friends() to authenticated;

create or replace function chat_with(p_other uuid, p_limit int default 50)
returns table(sender uuid, body text, created_at timestamptz)
language sql security definer set search_path = public as $$
  select sender, body, created_at from messages
  where (sender = auth.uid() and recipient = p_other)
     or (sender = p_other and recipient = auth.uid())
  order by created_at desc limit p_limit;
$$;
grant execute on function chat_with(uuid, int) to authenticated;

create or replace function names_for(ids uuid[])
returns table(id uuid, username citext)
language sql security definer set search_path = public as $$
  select id, username from profiles where id = any(ids);
$$;
grant execute on function names_for(uuid[]) to authenticated;

create or replace function avatars_for(p_names text[])
returns table(username citext, avatar text)
language sql security definer set search_path = public as $$
  select username, avatar from profiles where username = any(p_names);
$$;
grant execute on function avatars_for(text[]) to authenticated;

-- public_profile changed shape across add-ons (gained xp) -> drop then recreate
drop function if exists public_profile(citext);
create or replace function public_profile(p_username citext)
returns table(id uuid, username citext, avatar text, wins int, losses int, xp int)
language sql security definer set search_path = public as $$
  select id, username, avatar, wins, losses, xp from profiles where username = p_username limit 1;
$$;
grant execute on function public_profile(citext) to authenticated;

create or replace function comments_for(p_profile uuid, p_limit int default 50)
returns table(author_name citext, body text, created_at timestamptz)
language sql security definer set search_path = public as $$
  select author_name, body, created_at from comments
  where profile_id = p_profile order by created_at desc limit p_limit;
$$;
grant execute on function comments_for(uuid, int) to authenticated;

create or replace function remove_friend(p_other uuid)
returns void language sql security definer set search_path = public as $$
  delete from friendships
  where (requester = auth.uid() and addressee = p_other)
     or (requester = p_other     and addressee = auth.uid());
$$;
grant execute on function remove_friend(uuid) to authenticated;

create or replace function public.bump_counter(p_name text)
returns bigint language sql security definer set search_path = public as $$
  insert into public.counters(name, n) values (p_name, 1)
  on conflict (name) do update set n = public.counters.n + 1
  returning n;
$$;
create or replace function public.get_counter(p_name text)
returns bigint language sql security definer set search_path = public as $$
  select coalesce((select n from public.counters where name = p_name), 0);
$$;
grant execute on function public.bump_counter(text) to anon, authenticated;
grant execute on function public.get_counter(text)  to anon, authenticated;

-- settle_match: pays out (faucet + any wager) only on the SECOND matching confirmation
create or replace function settle_match(
    p_match text, p_opponent uuid, p_amount int, p_winner uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me        uuid := auth.uid();
  amt       int  := greatest(0, least(coalesce(p_amount,0), 1000000));
  mine      wager_matches;
  theirs    wager_matches;
  win_id    uuid;
  lose_id   uuid;
  wager_out text := 'none';
  my_new    int;
begin
  if me is null then return jsonb_build_object('status','error','msg','not signed in'); end if;
  if p_opponent is null or p_opponent = me then
    return jsonb_build_object('status','error','msg','bad opponent'); end if;
  if p_winner is not null and p_winner <> me and p_winner <> p_opponent then
    return jsonb_build_object('status','error','msg','bad winner'); end if;

  insert into wager_matches(match_id, reporter, opponent, amount, winner)
  values (p_match, me, p_opponent, amt, p_winner)
  on conflict (match_id, reporter) do nothing;

  select * into mine   from wager_matches
    where match_id=p_match and reporter=me        and opponent=p_opponent for update;
  select * into theirs from wager_matches
    where match_id=p_match and reporter=p_opponent and opponent=me        for update;

  if theirs.reporter is null then
    return jsonb_build_object('status','pending');
  end if;
  if mine.settled or theirs.settled then
    select coins into my_new from profiles where id=me;
    return jsonb_build_object('status','done','coins',my_new);
  end if;

  update wager_matches set settled=true
    where match_id=p_match and reporter in (me, p_opponent);

  if mine.amount = theirs.amount and amt > 0
     and mine.winner is not null and mine.winner = theirs.winner then
    win_id  := mine.winner;
    lose_id := case when win_id = me then p_opponent else me end;
    update profiles set coins = coins + amt              where id = win_id;
    update profiles set coins = greatest(0, coins - amt) where id = lose_id;
    wager_out := case when win_id = me then 'won' else 'lost' end;
  elsif amt > 0 then
    wager_out := 'void';
  end if;

  update profiles set coins = coins +
    (case when mine.winner is not null and mine.winner = theirs.winner and mine.winner = me
          then 10 else 5 end)
    where id = me;
  update profiles set coins = coins +
    (case when mine.winner is not null and mine.winner = theirs.winner and mine.winner = p_opponent
          then 10 else 5 end)
    where id = p_opponent;

  select coins into my_new from profiles where id = me;
  return jsonb_build_object('status','settled','wager',wager_out,'amount',amt,'coins',my_new);
end;
$$;
grant execute on function settle_match(text, uuid, int, uuid) to authenticated;

-- ============================================================
--  LOCK the coins column: clients keep writing everything else,
--  but coins can ONLY change via settle_match() above.
-- ============================================================
revoke insert, update on profiles from anon, authenticated;
grant  insert (id, username, wallet, avatar, wins, losses, xp) on profiles to authenticated;
grant  update (username, wallet, avatar, wins, losses, xp)     on profiles to authenticated;

-- ============================================================
--  REALTIME (guarded so re-runs don't error if already added)
-- ============================================================
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and tablename='messages') then
    alter publication supabase_realtime add table messages;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and tablename='friendships') then
    alter publication supabase_realtime add table friendships;
  end if;
end $$;
