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
- Each face is measured: the widest head row (cheeks/ears) gives FACE WIDTH and centre.
- Every character is SCALED so its face width is identical and the FACE CENTRE is anchored to the
  same line (FACE_CYF), horizontally centred — all on one fixed canvas. So in-game (drawPlayer /
  drawHero read the face at FACE_CYF and size by the face) every face is the same size and aligned.

b108 — CLEAN NECK/JAW CUT (source-level, applied everywhere):
- The head is cut at a fixed fraction of the (normalised) FACE WIDTH *below the widest face row*
  (JAW_K), NOT by the old jaw-narrowing detection. That detection failed on suit portraits
  (grandpa/elon/oldwoj/pdidpe/obampe) whose shoulders never narrow -> shoulders got baked in and the
  face was mis-sized. A fixed fraction lands the neck consistently and always sits ABOVE the
  shoulders, for round meme heads AND suit heads alike.
- The lower edge is FEATHERED (alpha ramped to 0 over the bottom FEATHER_FRAC of the head) so the cut
  is a soft neck fade, never a hard horizontal chop.
- JAW_K ~0.42 also places the neck near CHIN_FRAC and the face centre at FACE_CYF, matching the draw
  code, so this changes NO in-game hitbox/grab (those are separate from the sprite image) and keeps
  the face size/alignment the earlier builds established.
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
FACE_CYF = 0.62     # the FACE CENTRE sits this far down the frame for EVERY character (matches drawPlayer FACE_CYF)
CHIN_FRAC = 0.84    # reference chin line (drawHero anchors here); neck lands ~here at the default JAW_K
# b58: normalise by FACE WIDTH (cheek-to-cheek) — the size the eye actually reads — NOT total bbox height.
FACE_W      = 240   # every character's cheek/face width scaled to this many px (the perceived size) — UNCHANGED
TOP_MARGIN  = 10    # min clear px above the hair — vertical-fit safety so tall hair can't clip the frame top
SIDE_MARGIN = 14    # min clear px each side

# b108: NECK/JAW CUT — cut this many face-widths BELOW the widest face row, then feather. ~0.42 puts the
# neck at ~CHIN_FRAC with the face centre at FACE_CYF (self-consistent with the draw code) and always
# sits above the shoulders. Per-char overrides for portraits whose widest row isn't the cheeks (bald
# cranium reads high -> cut LOWER; wide hair reads low -> cut a touch higher). Tuned via the contact sheet.
JAW_K_DEFAULT = 0.42
JAW_K = {
    'okeyjak': 0.40,   # bald cranium reads WIDE (big faceW) -> a small fraction already reaches the jaw
    'boomer':  0.50,   # round bald pate reads high
    'grandpa': 0.50,
    'oldwoj':  0.50,
    'elon':    0.46,
    'soyjak':  0.37,   # keep the curly neckbeard (facial hair) but trim the bare shoulders below it
    'wojak':   0.46,
    'doomer':  0.40,   # deliberately scribbly dark-hood character (faithful to the source art)
    'pepe':    0.26,   # cut at the green jaw base, ABOVE the blue shirt (keeps the droopy mouth)
    'trumpe':  0.40,
}
FEATHER_FRAC = 0.14   # fraction of head height (hair-top..cut) faded to transparent at the neck (soft edge)

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
    """Measure top (hair), widest face row (ymax), face width and horizontal centre from the silhouette."""
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
    return dict(top=top, cx=cx, faceW=faceW, bot=bot, ymax=ymax, widths=widths)

def feather_edge(im, fpx):
    """Ramp alpha to 0 over the bottom `fpx` rows so the neck cut fades softly (no hard horizontal edge)."""
    if fpx <= 0: return
    px = im.load(); w, h = im.size; fpx = min(fpx, h)
    for i in range(fpx):
        y = h - 1 - i
        k = i / float(fpx)            # bottom row -> 0 (fully faded), top of the band -> ~1 (untouched)
        for x in range(w):
            r, g, b, a = px[x, y]
            if a: px[x, y] = (r, g, b, int(a * k))

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
    top, bot, faceW, ymax = m['top'], m['bot'], m['faceW'], m['ymax']
    # NECK/JAW CUT: a fixed fraction of the face width below the widest face row (excludes shoulders).
    jk = JAW_K.get(name, JAW_K_DEFAULT)
    cutRow = max(ymax + 2, min(bot, ymax + round(jk * faceW)))
    # scale so the FACE WIDTH is uniform -> consistent PERCEIVED size (unchanged normalisation)
    s = (FACE_W * ADJUST.get(name, 1.0)) / max(1, faceW)
    # vertical-fit safety: keep the hair-top within the frame above the FACE-CENTRE anchor
    max_above = CANVAS_H * FACE_CYF - TOP_MARGIN
    if (ymax - top) * s > max_above:
        s = max_above / max(1, (ymax - top))
    scaled = im.resize((max(1, round(im.width*s)), max(1, round(im.height*s))), Image.LANCZOS)
    top_s, cut_s, ymax_s = round(top*s), round(cutRow*s), round(ymax*s)
    face = scaled.crop((0, top_s, scaled.width, cut_s))          # hair-top down to the neck cut, full width
    fb = face.getbbox()
    if fb: face = face.crop((fb[0], 0, fb[2], face.height))      # tighten horizontally (keep full top..cut)
    face_cy = ymax_s - top_s                                     # face-centre row within the crop
    if face.width > CANVAS_W - 2*SIDE_MARGIN:                    # side-fit safety (rarely triggers now)
        f2 = (CANVAS_W - 2*SIDE_MARGIN) / face.width
        face = face.resize((CANVAS_W - 2*SIDE_MARGIN, max(1, round(face.height*f2))), Image.LANCZOS)
        face_cy = round(face_cy * f2)
    feather_edge(face, max(8, round(FEATHER_FRAC * face.height)))
    canvas = Image.new('RGBA', (CANVAS_W, CANVAS_H), (0, 0, 0, 0))
    yoff = round(CANVAS_H * FACE_CYF - face_cy)                  # anchor the FACE CENTRE at FACE_CYF
    canvas.alpha_composite(face, ((CANVAS_W - face.width)//2, yoff))
    out = root / OUT.get(name, name + '_cut.png')
    canvas.save(out, optimize=True)
    print('cut', name, '->', out.name, f'faceW {faceW}->{round(faceW*s)}',
          f'jaw@{jk:.2f}', f'headH={face.height}', f'yoff={yoff}', f'{out.stat().st_size//1024}KB')

for n in NAMES:
    cut(n)
print('done — now run: python build.py')
