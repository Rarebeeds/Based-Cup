-- ====== Supabase / Postgres schema for the leaderboard ======
-- Run this in the Supabase SQL editor.

create table if not exists match_results (
  id         bigint generated always as identity primary key,
  username   text not null check (char_length(username) between 3 and 24),
  address    text,
  won        boolean not null,
  created_at timestamptz not null default now()
);

create index if not exists idx_match_results_created on match_results (created_at desc);

-- Rolling-window leaderboard (default 12 hours).
create or replace function leaderboard(window_hours int default 12, max_rows int default 20)
returns table (rank bigint, username text, wins bigint, losses bigint)
language sql stable as $$
  with agg as (
    select username,
           sum((won)::int)     as wins,
           sum((not won)::int) as losses
    from match_results
    where created_at >= now() - make_interval(hours => window_hours)
    group by username
  )
  select row_number() over (order by wins desc, losses asc) as rank,
         username, wins, losses
  from agg
  order by wins desc, losses asc
  limit max_rows;
$$;

-- A single player's rank in the window.
create or replace function player_rank(p_username text, window_hours int default 12)
returns table (rank bigint, of bigint, wins bigint, losses bigint)
language sql stable as $$
  with agg as (
    select username,
           sum((won)::int)     as wins,
           sum((not won)::int) as losses
    from match_results
    where created_at >= now() - make_interval(hours => window_hours)
    group by username
  ),
  ranked as (
    select username, wins, losses,
           row_number() over (order by wins desc, losses asc) as rank
    from agg
  )
  select rank, (select count(*) from agg) as of, wins, losses
  from ranked
  where lower(username) = lower(p_username);
$$;

-- ====== Locker: equipped character (b70) — OPTIONAL (local persistence works without it;
-- this enables cross-device equip). Run once: ======
alter table profiles add column if not exists equipped text;
alter table profiles add column if not exists char_stats jsonb;

-- ====== Hourly + All-Time leaderboards (b69) ======
-- Both read the SAME match_results table. HOURLY filters to the current Brisbane/AEST
-- clock hour (UTC+10, no DST) and HARD-RESETS at the top of each hour because the
-- window boundary moves forward — NO rows are ever deleted/mutated. ALL-TIME applies
-- no time filter. The hourly reset therefore can NEVER affect all-time.

create or replace function hourly_leaderboard(max_rows int default 20)
returns table (rank bigint, username text, wins bigint, losses bigint)
language sql stable as $$
  with agg as (
    select username,
           sum((won)::int)     as wins,
           sum((not won)::int) as losses
    from match_results
    where created_at >= (date_trunc('hour', now() at time zone 'Australia/Brisbane') at time zone 'Australia/Brisbane')
    group by username
  )
  select row_number() over (order by wins desc, losses asc) as rank,
         username, wins, losses
  from agg
  order by wins desc, losses asc
  limit max_rows;
$$;

create or replace function hourly_player_rank(p_username text)
returns table (rank bigint, of bigint, wins bigint, losses bigint)
language sql stable as $$
  with agg as (
    select username,
           sum((won)::int)     as wins,
           sum((not won)::int) as losses
    from match_results
    where created_at >= (date_trunc('hour', now() at time zone 'Australia/Brisbane') at time zone 'Australia/Brisbane')
    group by username
  ),
  ranked as (
    select username, wins, losses,
           row_number() over (order by wins desc, losses asc) as rank
    from agg
  )
  select rank, (select count(*) from agg) as of, wins, losses
  from ranked
  where lower(username) = lower(p_username);
$$;

create or replace function alltime_leaderboard(max_rows int default 20)
returns table (rank bigint, username text, wins bigint, losses bigint)
language sql stable as $$
  with agg as (
    select username,
           sum((won)::int)     as wins,
           sum((not won)::int) as losses
    from match_results
    group by username
  )
  select row_number() over (order by wins desc, losses asc) as rank,
         username, wins, losses
  from agg
  order by wins desc, losses asc
  limit max_rows;
$$;

create or replace function alltime_player_rank(p_username text)
returns table (rank bigint, of bigint, wins bigint, losses bigint)
language sql stable as $$
  with agg as (
    select username,
           sum((won)::int)     as wins,
           sum((not won)::int) as losses
    from match_results
    group by username
  ),
  ranked as (
    select username, wins, losses,
           row_number() over (order by wins desc, losses asc) as rank
    from agg
  )
  select rank, (select count(*) from agg) as of, wins, losses
  from ranked
  where lower(username) = lower(p_username);
$$;

-- ====== Monotonic profile sync (b86) — fixes "player level randomly resets to 1" ======
-- The client now writes profile progress ONLY through this RPC, which raises xp/wins/losses with
-- GREATEST so a stale/empty (0) context can never lower real progress. Coins are intentionally
-- excluded (they move only through settle_match). security definer + where id = auth.uid() means a
-- caller can only ever update their OWN row. Run once in the Supabase SQL editor.
create or replace function merge_profile(p_xp int, p_wins int, p_losses int, p_wallet text, p_avatar text)
returns void language sql security definer as $$
  update profiles set
    xp     = greatest(coalesce(xp,0),     coalesce(p_xp,0)),
    wins   = greatest(coalesce(wins,0),   coalesce(p_wins,0)),
    losses = greatest(coalesce(losses,0), coalesce(p_losses,0)),
    wallet = coalesce(nullif(p_wallet,''), wallet),
    avatar = coalesce(nullif(p_avatar,''), avatar)
  where id = auth.uid();
$$;
grant execute on function merge_profile(int,int,int,text,text) to authenticated;

-- NOTE on security: writes should go through the Vercel function using the
-- SERVICE ROLE key (server-side only). Do NOT expose the service role key to
-- the browser. If you ever let the client write directly with the anon key,
-- add Row Level Security policies — but even then, scores are self-reported
-- and spoofable without server-authoritative match validation.
