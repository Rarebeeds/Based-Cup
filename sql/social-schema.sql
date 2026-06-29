-- ============================================================
--  PEPE vs TRUMPE — Social (profiles, friends, chat)
--  Run this whole file in the Supabase SQL editor.
-- ============================================================

create extension if not exists citext;   -- case-insensitive usernames

-- ---------- PROFILES (one row per player) ----------
create table if not exists profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  username   citext unique not null,
  wallet     text,                       -- saved privately, for your giveaways
  created_at timestamptz not null default now()
);
alter table profiles enable row level security;

-- you can read/edit ONLY your own profile, so wallets stay private
create policy "own profile read"   on profiles for select using (auth.uid() = id);
create policy "own profile insert" on profiles for insert with check (auth.uid() = id);
create policy "own profile update" on profiles for update using (auth.uid() = id);

-- username search that returns id + username only (never wallets)
create or replace function find_profile(p_username citext)
returns table(id uuid, username citext)
language sql security definer set search_path = public as $$
  select id, username from profiles where username = p_username limit 1;
$$;
grant execute on function find_profile(citext) to authenticated;

-- ---------- FRIENDSHIPS ----------
create table if not exists friendships (
  id         bigint generated always as identity primary key,
  requester  uuid not null references profiles(id) on delete cascade,
  addressee  uuid not null references profiles(id) on delete cascade,
  status     text not null default 'pending' check (status in ('pending','accepted')),
  created_at timestamptz not null default now(),
  unique (requester, addressee)
);
alter table friendships enable row level security;

create policy "see my friendships"   on friendships for select using (auth.uid() = requester or auth.uid() = addressee);
create policy "send friend request"  on friendships for insert with check (auth.uid() = requester);
create policy "respond to request"   on friendships for update using (auth.uid() = addressee);

-- list my friends + pending requests, resolving the other person's username
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

-- ---------- MESSAGES (direct chat) ----------
create table if not exists messages (
  id         bigint generated always as identity primary key,
  sender     uuid not null references profiles(id) on delete cascade,
  recipient  uuid not null references profiles(id) on delete cascade,
  body       text not null check (char_length(body) between 1 and 500),
  created_at timestamptz not null default now()
);
alter table messages enable row level security;

create policy "see my messages" on messages for select using (auth.uid() = sender or auth.uid() = recipient);
create policy "send my messages" on messages for insert with check (auth.uid() = sender);

create index if not exists idx_messages_pair on messages (sender, recipient, created_at);

-- recent chat history with one friend
create or replace function chat_with(p_other uuid, p_limit int default 50)
returns table(sender uuid, body text, created_at timestamptz)
language sql security definer set search_path = public as $$
  select sender, body, created_at from messages
  where (sender = auth.uid() and recipient = p_other)
     or (sender = p_other and recipient = auth.uid())
  order by created_at desc limit p_limit;
$$;
grant execute on function chat_with(uuid, int) to authenticated;

-- ---------- enable live updates ----------
alter publication supabase_realtime add table messages;
alter publication supabase_realtime add table friendships;
