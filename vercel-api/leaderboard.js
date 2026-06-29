// Vercel serverless function — GET /api/leaderboard?hours=12&limit=20
//                              GET /api/leaderboard?rankFor=USERNAME&hours=12
import { createClient } from '@supabase/supabase-js';

const supa = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  if (req.method === 'OPTIONS') return res.status(204).end();

  const hours = Math.min(168, Math.max(1, Number(req.query.hours) || 12));

  // single-player rank
  if (req.query.rankFor) {
    const { data, error } = await supa.rpc('player_rank',
      { p_username: String(req.query.rankFor), window_hours: hours });
    if (error) return res.status(500).json({ error: error.message });
    const row = (data && data[0]) || null;
    return res.status(200).json(row
      ? { rank: Number(row.rank), of: Number(row.of), wins: Number(row.wins), losses: Number(row.losses) }
      : { rank: null, of: 0, wins: 0, losses: 0 });
  }

  // top board
  const limit = Math.min(100, Math.max(1, Number(req.query.limit) || 20));
  const { data, error } = await supa.rpc('leaderboard', { window_hours: hours, max_rows: limit });
  if (error) return res.status(500).json({ error: error.message });
  return res.status(200).json({ windowHours: hours, players: data.length, leaderboard: data });
}
