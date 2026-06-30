// Vercel serverless function — GET /api/turn
// Mints SHORT-LIVED Cloudflare TURN credentials for the browser, so P2P can traverse
// symmetric NAT / CGNAT (which STUN alone cannot). The key secret never reaches the client.
//
// SETUP (one-time): create a Cloudflare Realtime/Calls TURN key, then set these in the
// Vercel project's Environment Variables and redeploy:
//   TURN_KEY_ID         = the key's id (the "uid" from List TURN Keys)
//   TURN_KEY_API_TOKEN  = the key's API token (shown once at creation)
// If either is missing, this returns iceServers:null and the client falls back to STUN-only
// (never breaks).

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Cache-Control', 'no-store');
  if (req.method === 'OPTIONS') return res.status(204).end();

  const keyId = process.env.TURN_KEY_ID;
  const token = process.env.TURN_KEY_API_TOKEN;
  // diagnostic: report PRESENCE of each env var (never the values) so misconfig is easy to pinpoint
  if (!keyId || !token) return res.status(200).json({ iceServers: null, note: 'TURN not configured', hasId: !!keyId, hasToken: !!token });

  try {
    const r = await fetch(
      `https://rtc.live.cloudflare.com/v1/turn/keys/${keyId}/credentials/generate-ice-servers`,
      { method: 'POST',
        headers: { 'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json' },
        body: JSON.stringify({ ttl: 86400 }) }   // 24h credential lifetime
    );
    if (!r.ok) {
      const t = await r.text();
      return res.status(200).json({ iceServers: null, error: 'cf ' + r.status + ' ' + t.slice(0, 160) });
    }
    const d = await r.json();
    // Cloudflare returns { iceServers: { urls:[...], username, credential } }
    return res.status(200).json({ iceServers: d.iceServers || null });
  } catch (e) {
    return res.status(200).json({ iceServers: null, error: String(e).slice(0, 160) });
  }
}
