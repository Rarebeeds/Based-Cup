# Deploy the Based Cup lobby to Fly.io — Sydney region

This puts your relay ~15–25 ms from you and your mate (you're both near Brisbane),
instead of ~180 ms to the US. Biggest single thing you can do for online smoothness.

You only do this once. ~10 minutes.

----------------------------------------------------------------
WHAT'S IN THIS FOLDER
----------------------------------------------------------------
  server.js      <- your lobby relay (unchanged)
  package.json   <- unchanged
  Dockerfile     <- tells Fly how to build it
  fly.toml       <- Fly settings: Sydney region, always-on

Put all four files together in one folder on your computer.

----------------------------------------------------------------
STEP 1 — Install the Fly CLI ("flyctl")
----------------------------------------------------------------
Windows (PowerShell):
    pwr -Command "iwr https://fly.io/install.ps1 -useb | iex"
  (if that errors, use:)
    powershell -Command "iwr https://fly.io/install.ps1 -useb | iex"

macOS / Linux (Terminal):
    curl -L https://fly.io/install.sh | sh

Then close and reopen your terminal so `fly` is on your PATH.
Check it works:
    fly version

----------------------------------------------------------------
STEP 2 — Make a Fly account + log in
----------------------------------------------------------------
    fly auth signup       (opens browser; or `fly auth login` if you already have one)

Note: Fly is not free anymore — it's pay-as-you-go. One always-on
shared-cpu-1x / 256 MB machine like this is roughly US$2–4 / month.
A card is required at signup. (If you'd rather it cost ~nothing and don't
mind a ~1–2 s wake on the first connect, see "CHEAPER" at the bottom.)

----------------------------------------------------------------
STEP 3 — Deploy (run these IN this folder)
----------------------------------------------------------------
Open a terminal and `cd` into the folder with the four files, then:

    fly apps create basedcup-lobby-syd
    fly deploy

- If `apps create` says the name is taken, pick another, e.g.
  `basedcup-lobby-syd2`, then edit the `app = "..."` line in fly.toml to match,
  and TELL CLAUDE the name you used so the game points at the right URL.
- `fly deploy` builds the Docker image and starts it in Sydney. Wait for
  "deployed successfully".

----------------------------------------------------------------
STEP 4 — Test it
----------------------------------------------------------------
Your URL is:   https://basedcup-lobby-syd.fly.dev
Open that in a browser — you should see:  lobby ok

The game connects to the wss:// version:
    wss://basedcup-lobby-syd.fly.dev

----------------------------------------------------------------
STEP 5 — Point the game at it
----------------------------------------------------------------
The game's built-in default is already set to:
    wss://basedcup-lobby-syd.fly.dev
So if you used the name `basedcup-lobby-syd`, you're done — just upload the
latest index.html (build b10) and both of you do ONE thing the first time:
open "Play a Friend", clear the URL box if it shows the old Render URL, and
let it refill with the new default (or paste the wss URL above).

If you used a DIFFERENT app name, tell Claude and I'll rebuild index.html with
your URL baked in.

----------------------------------------------------------------
HANDY FLY COMMANDS
----------------------------------------------------------------
    fly logs                 # live server logs
    fly status               # is it running? which region?
    fly apps open            # open the URL
    fly scale count 1        # ensure exactly one machine
    fly deploy               # redeploy after any change

----------------------------------------------------------------
CHEAPER (optional) — let it sleep to save money
----------------------------------------------------------------
In fly.toml set:
    auto_stop_machines = true
    min_machines_running = 0
Redeploy. Now Fly suspends the machine when idle and resumes it in ~1–2 s on
the first connect (much faster than Render's 30–60 s). Trade a tiny first-
connect delay for near-zero cost.
