
// Vercel serverless function — POST /api/result   (serverless path, backed by Supabase)
import { createClient } from '@supabase/supabase-js';

const supa = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, X-Client-Token');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST')    return res.status(405).json({ error: 'method' });

  if (process.env.CLIENT_TOKEN && req.headers['x-client-token'] !== process.env.CLIENT_TOKEN)
    return res.status(401).json({ error: 'bad_token' });

  const { username, address, won } = req.body || {};
  const u = String(username || '').trim().slice(0, 24);
  if (u.length < 3) return res.status(400).json({ error: 'bad_username' });

  const { error } = await supa.from('match_results')
    .insert({ username: u, address: String(address || '').slice(0, 64), won: !!won });

  if (error) return res.status(500).json({ error: error.message });
  return res.status(200).json({ ok: true });
}
