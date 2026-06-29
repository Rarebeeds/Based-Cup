#!/usr/bin/env python3
"""
Turn raw character portraits into clean, transparent, FACE-ALIGNED head sprites so every
character is "molded" to the same size and position in the game.

1. Drop each raw portrait into this folder as <key>.png (e.g. boomer.png, chad.png, pepe.png).
2. Run:  python process_sprites.py
   -> writes <key>_cut.png (pepe/trumpe -> pepe_cut_s.png / trumpe_cut_s.png) for build.py.
3. Run:  python build.py

How alignment works:
- Background removal is a FLOOD-FILL from the border with a TIGHT threshold (THRESH3) that stops
  at the character's skin, so pale/white wojak faces are NOT erased (they used to go invisible).
- Each face is measured: the widest head row (cheeks/ears) gives FACE WIDTH and centre; the row
  below it where the silhouette narrows to the neck gives the CHIN.
- Every character is then SCALED so its face width is identical, the CHIN is anchored to the same
  line, and the face is horizontally centred — all on one fixed canvas. So in-game (where drawPlayer
  height-locks the sprite) every face is the same size, with chins and eye-lines lined up. Hair/ears
  extend naturally above; the body below the chin is dropped.
"""
from PIL import Image
from collections import deque
import pathlib

root = pathlib.Path(__file__).parent
NAMES = ['boomer', 'chad', 'grandpa', 'elon', 'obampe', 'okeyjak', 'oldwoj',
         'pdidpe', 'pepe', 'sadjak', 'soyjak', 'trumpe', 'wojak', 'doomer']
OUT = {'pepe': 'pepe_cut_s.png', 'trumpe': 'trumpe_cut_s.png'}   # build reads these two names
THRESH3 = 110       # bg colour distance; BELOW pale-skin distance so faces survive (not invisible)
ALPHA = 40          # alpha above this counts as opaque when measuring the silhouette

# --- fixed output frame: FACE normalised into this so every FACE reads the same SIZE in-game ---
CANVAS_W = 360      # frame width
CANVAS_H = 450      # frame height
CHIN_FRAC = 0.84    # the chin sits this far down the frame for EVERY character
# b58: normalise by FACE WIDTH (cheek-to-cheek) — the size the eye actually reads — NOT total bbox height.
# Hair/ears then extend naturally above, so overall silhouette HEIGHT varies by hairstyle (correct & natural).
FACE_W      = 240   # every character's cheek/face width scaled to this many px (the perceived size)
TOP_MARGIN  = 10    # min clear px above the hair — vertical-fit safety so tall hair can't clip the frame top
SIDE_MARGIN = 14    # min clear px each side
# per-char chin fraction (of silhouette top..bot) where the auto jaw-detect misreads (3/4 views) — KEEP (b57 fix):
CHIN_OVERRIDE = {'okeyjak': 0.88}   # okeyjak's bald cranium fools the jaw-narrowing test -> chin was cut at the mouth
# face-width misread nudges (bald cranium / 3-4 view over- or under-measure the cheek row): >1 bigger, <1 smaller
ADJUST = {'boomer': 0.85, 'okeyjak': 1.20, 'pdidpe': 0.88}

def remove_bg(im):
    px = im.load(); w, h = im.size
    def patch(x0, y0):
        cols = [px[x, y] for y in range(y0, y0+8) for x in range(x0, x0+8)]
        n = len(cols); return tuple(sum(c[i] for c in cols)//n for i in range(3))
    tl, tr = patch(2, 2), patch(w-10, 2)
    bg = tuple((tl[i] + tr[i]) // 2 for i in range(3))
    def is_bg(x, y):
        r, g, b, a = px[x, y]
        return a != 0 and abs(r-bg[0]) + abs(g-bg[1]) + abs(b-bg[2]) < THRESH3
    q = deque()
    for x in range(w):
        for y in (0, h-1):
            if is_bg(x, y): q.append((x, y))
    for y in range(h):
        for x in (0, w-1):
            if is_bg(x, y): q.append((x, y))
    while q:
        x, y = q.popleft()
        r, g, b, a = px[x, y]
        if a == 0: continue
        px[x, y] = (r, g, b, 0)
        if x > 0   and is_bg(x-1, y): q.append((x-1, y))
        if x < w-1 and is_bg(x+1, y): q.append((x+1, y))
        if y > 0   and is_bg(x, y-1): q.append((x, y-1))
        if y < h-1 and is_bg(x, y+1): q.append((x, y+1))
    return bg

def face_metrics(im):
    """Measure top (hair), chin, face width and horizontal centre from the silhouette."""
    px = im.load(); w, h = im.size
    widths = [sum(1 for x in range(w) if px[x, y][3] > ALPHA) for y in range(h)]
    nz = [y for y in range(h) if widths[y] > 0]
    if not nz: return None
    top, bot = nz[0], nz[-1]; H = bot - top + 1
    # widest head row (cheeks/cranium), searched in the upper 60% so shoulders don't win
    ymax = max(range(top, top + max(1, int(H*0.60))), key=lambda y: widths[y])
    faceW = widths[ymax]
    row = [x for x in range(w) if px[x, ymax][3] > ALPHA]
    cx = (row[0] + row[-1]) // 2 if row else w // 2
    # chin = first row below the widest where the jaw narrows toward the neck (<66% of face width)
    chin = bot
    for y in range(ymax + 1, bot + 1):
        if widths[y] < faceW * 0.66:
            chin = min(bot, y + int(faceW * 0.04)); break   # small fixed margin past the jaw
    return dict(top=top, chin=chin, cx=cx, faceW=faceW, bot=bot, widths=widths)

def cut(name):
    src = root / (name + '.png')
    if not src.exists():
        print('skip', name, '— no', src.name); return
    im = Image.open(src).convert('RGBA')
    remove_bg(im)
    bb = im.getbbox()
    if bb: im = im.crop(bb)
    m = face_metrics(im)
    if not m:
        print('skip', name, '— empty after bg removal'); return
    top, bot, widths, faceW = m['top'], m['bot'], m['widths'], m['faceW']
    # chin: per-char fraction override where the auto jaw-detect misreads, else the detected jaw (KEEP b57 fix)
    chin = round(top + (bot-top)*CHIN_OVERRIDE[name]) if name in CHIN_OVERRIDE else m['chin']
    chin = max(top+1, min(bot, chin))
    # scale so the FACE WIDTH is uniform -> consistent PERCEIVED size (hair height then varies, which is fine)
    s = (FACE_W * ADJUST.get(name, 1.0)) / max(1, faceW)
    chinY = int(CANVAS_H * CHIN_FRAC)
    if (chin - top) * s > chinY - TOP_MARGIN:                   # vertical-fit safety: tall hair can't clip the top
        s = (chinY - TOP_MARGIN) / (chin - top)
    scaled = im.resize((max(1, round(im.width*s)), max(1, round(im.height*s))), Image.LANCZOS)
    top_s, chin_s = round(top*s), round(chin*s)
    face = scaled.crop((0, top_s, scaled.width, chin_s))        # hair-top down to the chin, full width
    fb = face.getbbox()
    if fb: face = face.crop((fb[0], 0, fb[2], face.height))     # tighten horizontally (keep full top..chin)
    if face.width > CANVAS_W - 2*SIDE_MARGIN:                   # side-fit safety (rarely triggers; width is normalised)
        f2 = (CANVAS_W - 2*SIDE_MARGIN) / face.width
        face = face.resize((CANVAS_W - 2*SIDE_MARGIN, max(1, round(face.height*f2))), Image.LANCZOS)
    canvas = Image.new('RGBA', (CANVAS_W, CANVAS_H), (0, 0, 0, 0))
    canvas.alpha_composite(face, ((CANVAS_W - face.width)//2, chinY - face.height))   # centre face, chin on the line
    out = root / OUT.get(name, name + '_cut.png')
    canvas.save(out, optimize=True)
    print('cut', name, '->', out.name, f'faceW {faceW}->{round(faceW*s)}', f'headH={face.height}', f'{out.stat().st_size//1024}KB')

for n in NAMES:
    cut(n)
print('done — now run: python build.py')
