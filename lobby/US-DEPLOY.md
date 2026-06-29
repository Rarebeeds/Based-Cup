# Add a US server (third relay)

Adds a US relay alongside Sydney (+ Singapore). Run these in the SAME lobby folder, in PowerShell.

1) Create the third app:
       fly apps create basedcup-lobby-us

2) Deploy it using the US config (note the -c flag):
       fly deploy -c fly-us.toml

3) Test it — open in a browser:
       https://basedcup-lobby-us.fly.dev
   You should see:  lobby ok

That's it. The game's US button already points at wss://basedcup-lobby-us.fly.dev,
so once this is live the picker just works.

---- Region ----
- fly-us.toml uses primary_region = "iad" (US-East, Ashburn VA). To put it elsewhere,
  edit that line before step 2:
      ord = Chicago (central)   dfw = Dallas (central)
      sjc = San Jose (west)     lax = Los Angeles (west)   sea = Seattle (west)
  Central (ord/dfw) gives the most even latency across both US coasts.

---- Notes ----
- Another always-on shared-cpu-1x machine ≈ US$2–4/month.
- Status / logs:   fly status -a basedcup-lobby-us   ·   fly logs -a basedcup-lobby-us
- Make sure exactly ONE machine runs (the match queue is in-memory):
      fly scale count 1 -a basedcup-lobby-us
- To save money, set auto_stop_machines = true and min_machines_running = 0 in
  fly-us.toml, then redeploy (trades ~1–2s first-connect wake for near-zero cost).
- If you used a different app name, tell Claude so the game's US button can be repointed.
