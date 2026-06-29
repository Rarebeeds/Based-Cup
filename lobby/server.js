// Based Cup — lobby relay + quick-match matchmaking
// 1) Friend lobbies: pair two players by a 4-letter code (create/join).
// 2) Quick match: a FIFO queue pairs any two waiting players automatically.
// It does NOT run the game; the HOST's browser simulates and the GUEST streams
// input / renders snapshots. Deploy on Fly/Render/Railway (a long-running process).

const http = require('http');
const { WebSocketServer } = require('ws');

const PORT = process.env.PORT || 8080;
const rooms = new Map();          // code -> { host, guest }
let quickQueue = [];              // sockets waiting for a quick match

function makeCode(){
  const A = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let c = ''; for (let i=0;i<4;i++) c += A[Math.floor(Math.random()*A.length)];
  return c;
}
function send(ws, obj){ if (ws && ws.readyState === 1) ws.send(JSON.stringify(obj)); }
function dropFromQueue(ws){ quickQueue = quickQueue.filter(s => s !== ws); }

const server = http.createServer((req,res)=>{ res.writeHead(200,{'Content-Type':'text/plain'}); res.end('lobby ok'); });
// perMessageDeflate:false — don't compress the tiny, frequent snapshot frames; the
// CPU + buffering cost of deflate adds latency that hurts a 50Hz real-time stream.
const wss = new WebSocketServer({ server, perMessageDeflate: false });

wss.on('connection', (ws)=>{
  ws.room = null; ws.role = null; ws.alive = true;
  try { ws._socket && ws._socket.setNoDelay(true); } catch {}   // disable Nagle: send each frame immediately
  ws.on('pong', ()=>{ ws.alive = true; });

  ws.on('message', (raw)=>{
    let m; try { m = JSON.parse(raw); } catch { return; }

    if (m.t === 'create') {
      let c = makeCode(); while (rooms.has(c)) c = makeCode();
      rooms.set(c, { host: ws, guest: null });
      ws.room = c; ws.role = 'host';
      send(ws, { t:'created', code:c });

    } else if (m.t === 'join') {
      const c = String(m.code||'').toUpperCase().trim();
      const r = rooms.get(c);
      if (!r)            return send(ws, { t:'error', msg:'No lobby with that code.' });
      if (r.guest)       return send(ws, { t:'error', msg:'That lobby is full.' });
      r.guest = ws; ws.room = c; ws.role = 'guest';
      send(ws,    { t:'joined', code:c });
      send(r.host,{ t:'peer-joined' });
      send(ws,    { t:'peer-here'   });

    } else if (m.t === 'quick') {
      // matchmaking: pair with the next live waiter, else wait in the queue
      dropFromQueue(ws);
      let partner = null;
      while (quickQueue.length){ const c = quickQueue.shift(); if (c.readyState === 1 && c !== ws){ partner = c; break; } }
      if (partner){
        let c = makeCode(); while (rooms.has(c)) c = makeCode();
        rooms.set(c, { host: partner, guest: ws });
        partner.room = c; partner.role = 'host'; ws.room = c; ws.role = 'guest';
        send(partner, { t:'matched', role:'host',  code:c });
        send(ws,      { t:'matched', role:'guest', code:c });
      } else {
        quickQueue.push(ws);
        send(ws, { t:'searching' });
      }

    } else if (m.t === 'cancel') {
      dropFromQueue(ws);

    } else if (m.t === 'relay') {
      const r = rooms.get(ws.room); if (!r) return;
      const other = ws.role === 'host' ? r.guest : r.host;
      send(other, { t:'relay', d:m.d });

    } else if (m.t === 'rejoin') {
      // a peer that dropped mid-match comes back — re-bind it into its still-pending slot
      const c = String(m.code||'').toUpperCase().trim();
      const r = rooms.get(c);
      if (!r || !r.pending || r.pending.role !== m.role){ send(ws, { t:'error', msg:'reconnect failed' }); return; }
      if (m.role === 'host') r.host = ws; else r.guest = ws;
      ws.room = c; ws.role = m.role; ws.left = false;
      r.pending = null; if (r.graceTimer){ clearTimeout(r.graceTimer); r.graceTimer = null; }
      send(ws, { t:'resumed' });
      send(m.role === 'host' ? r.guest : r.host, { t:'peer-back' });

    } else if (m.t === 'leave') {
      ws.left = true; hardCleanup(ws);     // intentional exit -> tear down immediately
    }
  });

  ws.on('close', ()=>{ if (ws.left) return; gracefulDrop(ws); });   // unexpected drop -> grace window
});

// intentional leave: drop the peer and delete the room now
function hardCleanup(ws){
  dropFromQueue(ws);
  const r = ws.room && rooms.get(ws.room);
  if (r && (r.host === ws || r.guest === ws)){
    if (r.graceTimer){ clearTimeout(r.graceTimer); r.graceTimer = null; }
    send(ws.role === 'host' ? r.guest : r.host, { t:'peer-left' });
    rooms.delete(ws.room);
  }
  ws.room = null;
}

// unexpected drop mid-match: keep the room ~8s so the player can rejoin; only then forfeit
function gracefulDrop(ws){
  dropFromQueue(ws);
  const code = ws.room, r = code && rooms.get(code);
  if (!r || (r.host !== ws && r.guest !== ws)) return;     // stale socket already replaced
  const other = ws.role === 'host' ? r.guest : r.host;
  if (!other){ rooms.delete(code); return; }               // was waiting alone in a lobby — just drop it
  r.pending = { role: ws.role, since: Date.now() };
  send(other, { t:'peer-dropped' });
  if (r.graceTimer) clearTimeout(r.graceTimer);
  r.graceTimer = setTimeout(()=>{
    const rr = rooms.get(code);
    if (rr && rr.pending){
      send(rr.pending.role === 'host' ? rr.guest : rr.host, { t:'peer-left' });
      rooms.delete(code);
    }
  }, 8000);
}

setInterval(()=>{
  wss.clients.forEach(ws=>{ if (!ws.alive) return ws.terminate(); ws.alive=false; ws.ping(); });
}, 10000);   // ~10s so a half-open mobile/NAT connection is reaped in 10-20s, not 30-60s

server.listen(PORT, ()=> console.log('Lobby relay + matchmaking listening on', PORT));
