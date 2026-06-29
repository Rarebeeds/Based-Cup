# Add a Singapore server (second relay)

You already have Sydney running. This adds a Singapore one so players can pick.
Run these in the SAME lobby-fly folder, in PowerShell.

1) Create the second app:
       fly apps create basedcup-lobby-sin

2) Deploy it using the Singapore config (note the -c flag):
       fly deploy -c fly-singapore.toml

3) Test it — open in a browser:
       https://basedcup-lobby-sin.fly.dev
   You should see:  lobby ok

That's it. The game's Singapore button already points at
wss://basedcup-lobby-sin.fly.dev , so once this is live the picker just works.

---- Notes ----
- This is a SECOND always-on machine, so it's another ~US$2/month. If you and your
  mate are both in Australia you may not need Singapore at all — it's mainly useful
  if you play with friends in Asia. You can skip it and the Sydney button is enough.
- To check status / region:   fly status -a basedcup-lobby-sin
- To save money, you can set the Singapore one to sleep when idle: in
  fly-singapore.toml set  auto_stop_machines = true  and  min_machines_running = 0,
  then  fly deploy -c fly-singapore.toml  again.
- If the app name was taken and you used a different one, tell Claude so the game's
  Singapore button can be repointed.
