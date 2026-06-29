-- ===== Based Cup add-on #5: $BASED coins + match wagering =====
-- Run this whole file ONCE in the Supabase SQL editor (nothing selected).
-- Safe to re-run (idempotent). Depends on add.sql..add3.sql (profiles + xp/avatar).
--
-- What it does:
--   1) adds a `coins` balance to profiles (everyone starts at 1000 $BASED)
--   2) LOCKS the coins column so a client (anon key) can NEVER write it directly —
--      coins only ever move through the security-definer settle_match() RPC below.
--      (xp/wins/avatar/wallet stay client-writable exactly as before.)
--   3) settle_match(): both players confirm a finished online match; coins (the small
--      per-match faucet + any wager) are paid ONLY when both sides confirm the same
--      match — a single cheating client can neither rob the other nor farm coins off a
--      fake match, because nothing pays out without the opponent's matching report.

-- ---------- 0) make sure every column we reference below exists ----------
-- (self-sufficient: works even if add.sql/add2/add3 were never applied to this project)
alter table profiles add column if not exists avatar text;
alter table profiles add column if not exists wins   int not null default 0;
alter table profiles add column if not exists losses int not null default 0;
alter table profiles add column if not exists xp     int not null default 0;

-- ---------- 1) the balance ----------
alter table profiles add column if not exists coins int not null default 1000;

-- ---------- 2) lock the coins column (clients keep writing everything else) ----------
-- Drop the broad table-level write grants and re-grant every column EXCEPT coins, so
-- `update({xp})` / `update({wins})` / the registration upsert all still work, but
-- `update({coins})` from the client silently changes nothing it's allowed to.
revoke insert, update on profiles from anon, authenticated;
grant  insert (id, username, wallet, avatar, wins, losses, xp) on profiles to authenticated;
grant  update (username, wallet, avatar, wins, losses, xp)     on profiles to authenticated;

-- ---------- 3) per-match confirmations (both players write one row each) ----------
create table if not exists wager_matches (
  match_id   text  not null,                 -- agreed id: lobby code + a shared nonce
  reporter   uuid  not null references profiles(id) on delete cascade,
  opponent   uuid  not null,
  amount     int   not null default 0,        -- the stake this reporter understood
  winner     uuid,                            -- who the reporter says won (null = draw)
  settled    boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (match_id, reporter)            -- one report per player per match
);
alter table wager_matches enable row level security;   -- no policies => no direct client access;
                                                       -- settle_match() is SECURITY DEFINER and bypasses RLS.

-- settle_match: idempotent, pays out only on the SECOND (matching) confirmation.
-- returns jsonb: { status:'pending' | 'settled' | 'done', wager, amount, coins, delta }
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

  -- record my confirmation (can't report the same match twice)
  insert into wager_matches(match_id, reporter, opponent, amount, winner)
  values (p_match, me, p_opponent, amt, p_winner)
  on conflict (match_id, reporter) do nothing;

  -- lock both sides' rows so two concurrent calls serialize on the payout
  select * into mine   from wager_matches
    where match_id=p_match and reporter=me        and opponent=p_opponent for update;
  select * into theirs from wager_matches
    where match_id=p_match and reporter=p_opponent and opponent=me        for update;

  if theirs.reporter is null then
    return jsonb_build_object('status','pending');           -- opponent hasn't confirmed yet
  end if;
  if mine.settled or theirs.settled then
    select coins into my_new from profiles where id=me;
    return jsonb_build_object('status','done','coins',my_new); -- already paid out
  end if;

  -- both confirmed and unsettled -> settle exactly once
  update wager_matches set settled=true
    where match_id=p_match and reporter in (me, p_opponent);

  -- wager moves only if BOTH agree on the amount AND on a single winner
  if mine.amount = theirs.amount and amt > 0
     and mine.winner is not null and mine.winner = theirs.winner then
    win_id  := mine.winner;
    lose_id := case when win_id = me then p_opponent else me end;
    update profiles set coins = coins + amt                where id = win_id;
    update profiles set coins = greatest(0, coins - amt)   where id = lose_id;
    wager_out := case when win_id = me then 'won' else 'lost' end;
  elsif amt > 0 then
    wager_out := 'void';                                    -- disagreement / draw -> no coins move
  end if;

  -- small participation faucet, paid once both confirmed they played
  -- +10 to the (agreed) winner, +5 otherwise
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
