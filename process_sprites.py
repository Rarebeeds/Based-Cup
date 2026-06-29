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

# --- fixed output frame: HEAD normalised into this so every head is the same VISIBLE size in-game ---
CANVAS_W = 360      # frame width  (room for ears/wide hair)
CANVAS_H = 450      # frame height
CHIN_FRAC = 0.84    # the chin sits this far down the frame for EVERY character
# b57: normalise by VISIBLE HEAD HEIGHT (hair-top -> chin), not cheek width, so all heads render the same
# height in-game (drawPlayer scales the whole frame uniformly). ~= the old median so the group barely moves.
TARGET_HEAD_H = 268     # every character's hair-top -> chin scaled to this many px
SIDE_MARGIN   = 16      # keep this many px clear each side so a wide head never clips the frame
# per-char chin fraction (of the silhouette top..bot) where the auto jaw-detect misreads (3/4 views):
CHIN_OVERRIDE = {'okeyjak': 0.88}   # okeyjak's bald cranium fools the jaw-narrowing test -> chin cut at the mouth
# fine size nudges if a char still renders off-height after normalisation (>1 bigger, <1 smaller):
ADJUST = {}

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
    top, bot, widths = m['top'], m['bot'], m['widths']
    # chin: per-char fraction override where the auto jaw-detect misreads, else the detected jaw
    chin = round(top + (bot-top)*CHIN_OVERRIDE[name]) if name in CHIN_OVERRIDE else m['chin']
    chin = max(top+1, min(bot, chin))
    headH = chin - top                                          # the VISIBLE head we normalise
    s = (TARGET_HEAD_H * ADJUST.get(name, 1.0)) / headH         # scale so head height -> TARGET_HEAD_H
    maxW = max(widths[top:chin+1])                              # widest row within the head
    if maxW * s > (CANVAS_W - 2*SIDE_MARGIN):                   # width-contain so a wide head never clips
        s = (CANVAS_W - 2*SIDE_MARGIN) / maxW
    scaled = im.resize((max(1, round(im.width*s)), max(1, round(im.height*s))), Image.LANCZOS)
    top_s, chin_s = round(top*s), round(chin*s)
    face = scaled.crop((0, top_s, scaled.width, chin_s))        # hair-top down to the chin, full width
    fb = face.getbbox()
    if fb: face = face.crop((fb[0], 0, fb[2], face.height))     # tighten horizontally (keep full top..chin)
    chinY = int(CANVAS_H * CHIN_FRAC)
    canvas = Image.new('RGBA', (CANVAS_W, CANVAS_H), (0, 0, 0, 0))
    canvas.alpha_composite(face, ((CANVAS_W - face.width)//2, chinY - face.height))   # centre head, chin on the line
    out = root / OUT.get(name, name + '_cut.png')
    canvas.save(out, optimize=True)
    print('cut', name, '->', out.name, f'headH {headH}->{face.height}', f'w={face.width}', f'{out.stat().st_size//1024}KB')

for n in NAMES:
    cut(n)
print('done — now run: python build.py')
