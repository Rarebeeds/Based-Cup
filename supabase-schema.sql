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

-- NOTE on security: writes should go through the Vercel function using the
-- SERVICE ROLE key (server-side only). Do NOT expose the service role key to
-- the browser. If you ever let the client write directly with the anon key,
-- add Row Level Security policies — but even then, scores are self-reported
-- and spoofable without server-authoritative match validation.
