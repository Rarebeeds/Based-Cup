#!/usr/bin/env python3
"""
Build index.html from game_template.html by embedding the two character sprites.

The source of truth is game_template.html, which contains the tokens __PEPE__ and
__TRUMPE__ where the base64 PNGs go. We keep them as tokens so the source file stays
small and editable instead of a 480KB blob. This script injects them and writes the
deployable index.html, then extracts the main <script> to check.js for a syntax pass.

Usage:
    python3 build.py
    node --check check.js     # syntax check
    node harness.cjs          # load-time + missing-element check (see HANDOFF.md)
"""
import base64, re, pathlib, json

root = pathlib.Path(__file__).parent
def b64(p): return base64.b64encode((root / p).read_bytes()).decode()

# 1x1 transparent PNG, used as a placeholder for any new-character sprite not yet supplied
TINY = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgAAIAAAUAAen63NgAAAAASUVORK5CYII='

sprites = {'pepe': b64('pepe_cut_s.png'), 'trumpe': b64('trumpe_cut_s.png')}
# read/write as UTF-8 explicitly — the template has emoji (✓ ❚❚ 🪙 …) and Windows
# Python otherwise defaults to cp1252 and fails to decode/encode them.
html = (root / 'game_template.html').read_text(encoding='utf-8')
html = html.replace('__PEPE__', sprites['pepe']).replace('__TRUMPE__', sprites['trumpe'])

# intro reveal image (shown once per session, behind the first START loading screen)
if (root / 'intro_reveal.jpg').exists():
    html = html.replace('__INTRO_REVEAL__', 'data:image/jpeg;base64,' + b64('intro_reveal.jpg'))
else:
    html = html.replace('__INTRO_REVEAL__', '')   # no image yet -> reveal step is skipped at runtime

# extra characters: inject <name>_cut.png if present, else a transparent placeholder.
# only characters with real art are added to the in-game picker (via __EXTRA_CHARS__).
EXTRA = ['doomer','boomer','grandpa','soyjak','elon',
         'obampe','okeyjak','oldwoj','pdidpe','sadjak','wojak','chad']
present = []
for c in EXTRA:
    token = '__' + c.upper() + '__'
    cut = c + '_cut.png'
    if (root / cut).exists():
        html = html.replace(token, b64(cut)); present.append(c)
    else:
        html = html.replace(token, TINY)
html = html.replace('__EXTRA_CHARS__', json.dumps(present))
missing = [c for c in EXTRA if c not in present]
if missing:
    print('NOTE: no sprite yet for', missing, '— staged but not selectable (add <name>_cut.png and rebuild).')
print('Extra characters live:', present or '(none yet)')

(root / 'index.html').write_text(html, encoding='utf-8')

# extract the LAST <script> (the main game script; the first is the Supabase CDN tag)
scripts = re.findall(r'<script>(.*?)</script>', html, re.S)
(root / 'check.js').write_text(scripts[-1], encoding='utf-8')

# also refresh ids.json for harness.cjs (list of element ids in the HTML)
import json
ids = sorted(set(re.findall(r'id="([^"]+)"', html)))
(root / 'ids.json').write_text(json.dumps(ids), encoding='utf-8')

print(f"Built index.html ({len(html):,} bytes).")
print("Next: node --check check.js   &&   node harness.cjs")
