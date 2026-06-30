
// Vercel serverless function — GET /api/leaderboard?hours=12&limit=20
//                              GET /api/leaderboard?rankFor=USERNAME&hours=12
import { createClient } from '@supabase/supabase-js';

const supa = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  if (req.method === 'OPTIONS') return res.status(204).end();

  const hours = Math.min(168, Math.max(1, Number(req.query.hours) || 12));
  // mode: 'hourly' = current AEST clock-hour (hard reset on the hour); 'alltime' = cumulative forever;
  // anything else = the legacy rolling N-hour window. hourly/alltime read the SAME match_results table,
  // just with a different time predicate (hourly) or none (alltime) — so the hourly reset never touches all-time.
  const mode = String(req.query.mode || '').toLowerCase();

  // single-player rank
  if (req.query.rankFor) {
    const u = String(req.query.rankFor);
    let rpc, args;
    if (mode === 'hourly')      { rpc = 'hourly_player_rank';  args = { p_username: u }; }
    else if (mode === 'alltime'){ rpc = 'alltime_player_rank'; args = { p_username: u }; }
    else                        { rpc = 'player_rank';         args = { p_username: u, window_hours: hours }; }
    const { data, error } = await supa.rpc(rpc, args);
    if (error) return res.status(500).json({ error: error.message });
    const row = (data && data[0]) || null;
    return res.status(200).json(row
      ? { rank: Number(row.rank), of: Number(row.of), wins: Number(row.wins), losses: Number(row.losses) }
      : { rank: null, of: 0, wins: 0, losses: 0 });
  }

  // top board
  const limit = Math.min(100, Math.max(1, Number(req.query.limit) || 20));
  let rpc, args;
  if (mode === 'hourly')      { rpc = 'hourly_leaderboard';  args = { max_rows: limit }; }
  else if (mode === 'alltime'){ rpc = 'alltime_leaderboard'; args = { max_rows: limit }; }
  else                        { rpc = 'leaderboard';         args = { window_hours: hours, max_rows: limit }; }
  const { data, error } = await supa.rpc(rpc, args);
  if (error) return res.status(500).json({ error: error.message });
  return res.status(200).json({ mode: mode || ('rolling-' + hours + 'h'), players: data.length, leaderboard: data });
}
