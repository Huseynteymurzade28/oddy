"""Draws the terrain sheet of each world: autotiled ground, its trimmings,
one-way platforms and animated liquid. One 256x144 sheet per world, laid out
as `src/tilemap.odin` reads it:

  rows 0-5   the ground: column = which neighbours are ground (bit 1 up,
             2 right, 4 down, 8 left), row = one of six variants
  row 6      cols 0-3 inner corners (top-left, top-right, bottom-left,
             bottom-right), cols 4-7 the fringe of grass that stands above an
             exposed top, cols 8-15 flowers and tufts that grow on tops
  row 7      platform: left end, two middles, right end, a lone one
  row 8      liquid: cols 0-3 the surface, cols 4-7 the body, four frames;
             col 8 a breakable crate, cols 9-12 the chips it breaks into
"""

VARIANTS = 6

import numpy as np
from PIL import Image

from palette import ZONES

T = 16
UP, RIGHT, DOWN, LEFT = 1, 2, 4, 8
CLEAR = (0, 0, 0, 0)


def blank():
    return np.zeros((T, T, 4), dtype=np.uint8)


def put(img, x, y, c):
    if 0 <= x < img.shape[1] and 0 <= y < img.shape[0]:
        img[y, x] = c


def smooth_noise(rng, size=T, cells=3):
    """Value noise that wraps at the tile edges, so neighbouring tiles of the
    same variant meet without a seam."""
    grid = rng.random((cells, cells))
    out = np.zeros((size, size))
    for y in range(size):
        for x in range(size):
            gx, gy = x / size * cells, y / size * cells
            x0, y0 = int(gx) % cells, int(gy) % cells
            x1, y1 = (x0 + 1) % cells, (y0 + 1) % cells
            fx, fy = gx - int(gx), gy - int(gy)
            fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
            top = grid[y0, x0] * (1 - fx) + grid[y0, x1] * fx
            bot = grid[y1, x0] * (1 - fx) + grid[y1, x1] * fx
            out[y, x] = top * (1 - fy) + bot * fy
    return out


def pebble(img, z, x, y, w, h):
    s = z['stone']
    o = z['earth'][3]
    for dy in range(h):
        for dx in range(w):
            corner = (dx in (0, w - 1)) and (dy in (0, h - 1))
            if corner and w > 2 and h > 1:
                continue
            put(img, x + dx, y + dy, s[0] if dy == 0 else (s[2] if dy == h - 1 else s[1]))
    for dx in range(1, w - 1):
        put(img, x + dx, y + h, o)  # a shadow under it


def ground_fill(z, rng):
    """The inside of the ground: earth in two soft shades, a seam of root or
    darker soil, a couple of pebbles and a few bright grains."""
    e = z['earth']
    img = blank()
    n = smooth_noise(rng)
    for y in range(T):
        for x in range(T):
            v = n[y, x]
            # Mostly the one earth colour; the darker shade only in soft,
            # dithered patches, so tiles do not show their own edges.
            dark = v > 0.72 or (v > 0.62 and (x + y) % 2 == 0)
            img[y, x] = e[2] if dark else e[1]
    for _ in range(int(rng.integers(3, 6))):
        x, y = rng.integers(0, T, 2)
        put(img, x, y, e[0])
        if rng.random() < 0.5:
            put(img, x + 1, y, e[0])
    if rng.random() < 0.15:  # a root wandering through
        x, y = int(rng.integers(2, T - 2)), int(rng.integers(7, 11))
        for _ in range(int(rng.integers(5, 9))):
            put(img, x, y, e[3])
            x += 1
            y += int(rng.integers(-1, 2)) if rng.random() < 0.4 else 0
    if rng.random() < 0.55:
        w, h = int(rng.integers(3, 5)), int(rng.integers(2, 4))
        pebble(img, z, int(rng.integers(1, T - w)), int(rng.integers(7, T - h - 1)), w, h)
    return img


def grass_band(img, z, rng, mask):
    """The living top of an exposed surface: a thick, rounded cap of grass
    whose lower edge hangs into the earth in drips."""
    g = z['top']
    phase = rng.random() * 6.28
    for x in range(T):
        drip = 1 + int(round(1.2 + 1.2 * np.sin(x * 0.9 + phase))) + (1 if rng.random() < 0.15 else 0)
        depth = 6 + drip
        for y in range(depth):
            if y == 0:
                c = g[0]
            elif y == 1:
                c = g[0] if rng.random() < 0.35 else g[1]
            elif y < 4:
                c = g[1]
            elif y < 6:
                c = g[2]
            else:
                c = g[3]
            img[y, x] = c
        put(img, x, depth, z['earth'][3])
    # Highlights catching the sun on the cap.
    for _ in range(3):
        x = int(rng.integers(1, T - 2))
        put(img, x, 2, g[0])
        put(img, x + 1, 2, g[0])


def brick_fill(z, rng):
    """Ruin stone: two courses of blocks a tile, the joints of the second
    course offset by half, which repeats cleanly from tile to tile."""
    e = z['earth']
    img = blank()
    for y in range(T):
        course = y // 8
        yy = y % 8
        for x in range(T):
            xx = (x + (8 if course else 0) + (4 if course else 0)) % T
            if yy == 7 or xx % 12 == 0:
                img[y, x] = e[3]  # mortar
            elif yy == 0 or xx % 12 == 1:
                img[y, x] = e[0]  # the lit top and left of a block
            elif yy == 6:
                img[y, x] = e[2]
            else:
                img[y, x] = e[1]
    # Weathering: chips, a darker block, and a little sea moss in the joints.
    for _ in range(int(rng.integers(2, 4))):
        x, y = rng.integers(1, T - 1), rng.integers(1, T - 1)
        put(img, x, y, e[2])
    if rng.random() < 0.6:
        x = int(rng.integers(0, T - 3))
        y = 7 if rng.random() < 0.5 else 15
        for dx in range(int(rng.integers(2, 4))):
            put(img, x + dx, y, z['top'][2])
            put(img, x + dx, y - 1, z['top'][3]) if rng.random() < 0.4 else None
    return img


def basalt_fill(z, rng):
    """Dark volcanic rock, cracked, with the glow of what is under it showing
    through the cracks."""
    img = ground_fill(z, rng)
    g = z['top']
    if rng.random() < 0.8:
        x, y = int(rng.integers(1, T - 1)), int(rng.integers(6, 9))
        for _ in range(int(rng.integers(5, 10))):
            put(img, x, y, g[1])
            put(img, x, y + 1, z['earth'][4])
            if rng.random() < 0.3:
                put(img, x, y - 1, g[2])
            x += int(rng.integers(-1, 2))
            y += 1 if rng.random() < 0.5 else 0
            if y >= T - 1:
                break
    for _ in range(int(rng.integers(1, 3))):
        put(img, int(rng.integers(0, T)), int(rng.integers(5, T)), g[0])
    return img


def ground_tile(z, mask, variant, seed):
    rng = np.random.default_rng(seed)
    style = z.get('style', 'earth')
    img = {'earth': ground_fill, 'bricks': brick_fill, 'basalt': basalt_fill}[style](z, rng)
    o = z['outline']
    e = z['earth']
    open_up = not mask & UP
    open_down = not mask & DOWN
    open_left = not mask & LEFT
    open_right = not mask & RIGHT

    if open_up:
        grass_band(img, z, rng, mask)
    if open_down:
        img[T - 1, :] = o
        for x in range(T):
            if img[T - 2, x][3] and rng.random() < 0.85:
                img[T - 2, x] = e[3]
            # Little teeth of earth under the outline, so the underside is
            # not a ruler-straight line.
        for x in range(1, T - 1, 3 + int(rng.integers(0, 2))):
            put(img, x, T - 3, e[3])
    # Where the top is grass, the grass hangs a little way down the open sides
    # like a lip, and the earth starts below it.
    lip = int(rng.integers(7, 11)) if open_up else 0
    if open_left:
        for y in range(T):
            if y < lip:
                img[y, 0] = z['top'][3]
                img[y, 1] = z['top'][2] if y > 5 else img[y, 1]
            else:
                img[y, 0] = o
                if y < T - 1:
                    img[y, 1] = e[0]  # light falls from the left
    if open_right:
        for y in range(T):
            if y < lip:
                img[y, T - 1] = z['top'][3]
                img[y, T - 2] = z['top'][2] if y > 5 else img[y, T - 2]
            else:
                img[y, T - 1] = o
                if y < T - 1:
                    img[y, T - 2] = e[3]

    # Rounded outer corners: two pixels off each corner where two open sides
    # meet, with the outline turned in.
    def round_corner(cx, cy, dx, dy, edge):
        img[cy, cx] = CLEAR
        img[cy, cx + dx] = CLEAR
        img[cy + dy, cx] = CLEAR
        img[cy + dy, cx + dx] = edge
    if open_up and open_left:
        round_corner(0, 0, 1, 1, z['top'][3])
    if open_up and open_right:
        round_corner(T - 1, 0, -1, 1, z['top'][3])
    if open_down and open_left:
        round_corner(0, T - 1, 1, -1, o)
    if open_down and open_right:
        round_corner(T - 1, T - 1, -1, -1, o)
    return img


def inner_corner(z, which):
    """A concave corner: the two neighbours are ground but the diagonal is
    not. Drawn over the tile as a dark notch."""
    img = blank()
    o, e3 = z['outline'], z['earth'][3]
    pts = {'tl': (0, 0, 1, 1), 'tr': (T - 1, 0, -1, 1), 'bl': (0, T - 1, 1, -1), 'br': (T - 1, T - 1, -1, -1)}
    x, y, dx, dy = pts[which]
    img[y, x] = o
    img[y, x + dx] = e3
    img[y + dy, x] = e3
    return img


def fringe(z, seed):
    """Clumps of blades standing above an exposed top: drawn in the bottom
    rows of the air cell over the ground."""
    rng = np.random.default_rng(seed)
    g = z['top']
    img = blank()
    # The cap's own rounded top edge, then clumps of three blades on it.
    for x in range(T):
        put(img, x, T - 1, g[1] if rng.random() < 0.7 else g[0])
    x = int(rng.integers(0, 3))
    while x < T:
        h = int(rng.integers(2, 6))
        for k in range(h):
            put(img, x, T - 2 - k, g[0] if k >= h - 2 else g[1])
        for side in (-1, 1):
            hh = max(1, h - 2)
            for k in range(hh):
                put(img, x + side * (1 if k >= hh - 1 else 0), T - 2 - k, g[1] if k < hh - 1 else g[0])
        x += int(rng.integers(3, 6))
    return img


def disc(img, cx, cy, rx, ry, c):
    for y in range(int(cy - ry - 1), int(cy + ry + 2)):
        for x in range(int(cx - rx - 1), int(cx + rx + 2)):
            if ((x - cx) / max(rx, 0.1)) ** 2 + ((y - cy) / max(ry, 0.1)) ** 2 <= 1:
                put(img, x, y, c)


def flower(z, kind, seed):
    """Things that grow on top of the ground, big enough to read at a glance."""
    f = z['flowers']
    g = z['top']
    o = z['outline']
    img = blank()
    stem = g[3]
    if kind == 0:  # a white daisy
        for y in range(9, 16):
            put(img, 7, y, stem)
        put(img, 6, 13, g[2]); put(img, 5, 12, g[1]); put(img, 8, 14, g[2])
        for dx, dy in [(0, -2), (2, 0), (0, 2), (-2, 0), (1, -1), (1, 1), (-1, 1), (-1, -1)]:
            put(img, 7 + dx, 7 + dy, f[2])
        put(img, 7, 7, f[1]); put(img, 7, 8, f[4])
    elif kind == 1:  # a red tulip
        for y in range(9, 16):
            put(img, 8, y, stem)
        put(img, 9, 12, g[2]); put(img, 10, 11, g[1]); put(img, 7, 14, g[2]); put(img, 6, 13, g[1])
        c = f[0]
        for x in range(6, 11):
            for y in range(5, 9):
                if not (y == 5 and x in (6, 8, 10)):
                    put(img, x, y, c)
        put(img, 7, 6, f[2]); put(img, 9, 8, f[4])
    elif kind == 2:  # a tall tuft
        for x, h in [(4, 5), (5, 8), (6, 4), (7, 9), (8, 6), (9, 8), (10, 5), (11, 3)]:
            for k in range(h):
                put(img, x, 15 - k, g[1] if k < h - 2 else g[0])
    elif kind == 3:  # a round bush with berries
        disc(img, 8, 12, 5.5, 3.6, g[3])
        disc(img, 8, 11.5, 4.8, 3, g[2])
        disc(img, 7, 10.5, 3.2, 1.8, g[1])
        put(img, 6, 9, g[0]); put(img, 7, 9, g[0])
        for x, y in [(4, 12), (9, 10), (11, 12), (6, 13)]:
            put(img, x, y, f[0])
    elif kind == 4:  # a spotted mushroom
        for y in range(11, 16):
            put(img, 7, y, f[2]); put(img, 8, y, f[2])
        disc(img, 7.5, 10, 4.5, 2.6, f[4])
        for x in range(3, 13):
            if img[10, x][3]:
                pass
        put(img, 6, 9, f[2]); put(img, 9, 10, f[2]); put(img, 5, 10, f[2])
        for x in range(4, 12):
            put(img, x, 12, o) if not img[12, x][3] else None
    elif kind == 5:  # a sunflower
        for y in range(6, 16):
            put(img, 8, y, stem)
        put(img, 9, 11, g[2]); put(img, 10, 10, g[1]); put(img, 7, 13, g[2]); put(img, 6, 12, g[1])
        disc(img, 8, 4, 3, 3, f[1])
        disc(img, 8, 4, 1.3, 1.3, f[4])
    elif kind == 6:  # a pair of bluebells
        for y in range(8, 16):
            put(img, 7, y, stem)
        put(img, 8, 8, stem); put(img, 9, 9, stem); put(img, 6, 10, stem)
        for x, y in [(9, 10), (5, 11)]:
            disc(img, x + 0.5, y + 0.5, 1.6, 1.4, f[3])
            put(img, x, y + 2, f[3]); put(img, x + 1, y + 2, f[2])
    else:  # a mossy stone
        s = z['stone']
        disc(img, 8, 13.5, 4, 2.5, s[2])
        disc(img, 8, 13, 3.5, 2, s[1])
        disc(img, 7, 12, 2, 1, s[0])
        put(img, 6, 11, g[1]); put(img, 7, 11, g[0]); put(img, 8, 11, g[1]); put(img, 9, 12, g[1])
    return img


def platform(z, part, seed):
    """A one-way bridge of boards at the top of its cell, with a shadow under
    it and posts lashed with rope at the ends."""
    rng = np.random.default_rng(seed)
    p = z['plank']
    o = z['outline']
    img = blank()
    for x in range(T):
        img[0, x] = o
        img[1, x] = p[0]
        img[2, x] = p[1]
        img[3, x] = p[1]
        img[4, x] = p[2]
        img[5, x] = p[2]
        img[6, x] = o
    # Board ends and the grain.
    seams = (0, 6, 11) if part in ('mid', 'mid2') else (8,)
    for x in seams:
        for y in range(1, 6):
            put(img, x, y, p[3])
        put(img, x + 1, 1, p[0])
    for x in range(T):
        if rng.random() < 0.25:
            put(img, x, 3, p[2])
    if part == 'mid2':
        put(img, 3, 2, p[3]); put(img, 14, 4, p[3])
    if part in ('left', 'single'):
        for y in range(0, 7):
            put(img, 0, y, o)
        for y in range(0, 14):  # a post through the end
            put(img, 2, y, o); put(img, 3, y, p[1]); put(img, 4, y, p[2]); put(img, 5, y, o)
        for y in (2, 4):
            put(img, 2, y, z['rope']); put(img, 3, y, z['rope']); put(img, 4, y, z['rope']); put(img, 5, y, z['rope'])
        put(img, 3, 14, o); put(img, 4, 14, o)
    if part in ('right', 'single'):
        for y in range(0, 7):
            put(img, T - 1, y, o)
        for y in range(0, 14):
            put(img, T - 3, y, o); put(img, T - 4, y, p[2]); put(img, T - 5, y, p[1]); put(img, T - 6, y, o)
        for y in (2, 4):
            for dx in range(3, 7):
                put(img, T - dx, y, z['rope'])
        put(img, T - 4, 14, o); put(img, T - 5, 14, o)
    return img


def liquid(z, surface, frame):
    """Water (or lava): a surface row of foam riding a slow wave, and a body
    with glints that drift."""
    c = z['liquid']
    img = blank()
    for x in range(T):
        wave = np.sin((x / T + frame / 4) * 2 * np.pi)
        top = 2 + int(round(wave))
        for y in range(T):
            if surface and y < top:
                continue
            if surface and y == top:
                col = c[0]
            elif surface and y < top + 2:
                col = c[1]
            else:
                depth = (y + (0 if surface else T)) / (2 * T)
                col = c[2] if depth < 0.6 else c[3]
            img[y, x] = col
    rng = np.random.default_rng(frame * 31 + (7 if surface else 3))
    for _ in range(3):
        x, y = rng.integers(1, T - 2), rng.integers(6 if surface else 1, T - 1)
        put(img, x, y, c[1])
        put(img, x + 1, y, c[1])
    return img


def crate(z):
    """A breakable crate in the world's own wood: a frame, two boards and a
    brace across, bright enough to say 'hit me'."""
    p = z['plank']
    o = z['outline']
    img = blank()
    for y in range(T):
        for x in range(T):
            edge = x in (0, T - 1) or y in (0, T - 1)
            frame = x in (1, 2, T - 3, T - 2) or y in (1, 2, T - 3, T - 2)
            if edge:
                c = o
            elif frame:
                c = p[1] if (x in (1, 2) or y in (1, 2)) else p[2]
                if x in (1,) or y in (1,):
                    c = p[0]
            else:
                c = p[1] if (y // 4) % 2 == 0 else p[2]
            img[y, x] = c
    for i in range(3, T - 3):  # the brace, corner to corner
        img[i, i] = p[3]
        img[i, i - 1 if i > 3 else i] = p[0]
    for x, y in [(3, 3), (T - 4, 3), (3, T - 4), (T - 4, T - 4)]:  # nails
        img[y, x] = z['stone'][0]
    return img


def chip(z, k):
    """A splinter of crate flying off: drawn small in the middle of a tile."""
    p = z['plank']
    img = blank()
    shapes = [[(6, 7), (7, 7), (8, 7), (7, 8)], [(7, 6), (7, 7), (8, 8), (9, 8)],
              [(6, 8), (7, 8), (7, 7), (8, 7), (9, 7)], [(7, 7), (8, 7), (7, 8), (8, 8)]]
    for i, (x, y) in enumerate(shapes[k]):
        img[y, x] = p[i % 3]
    return img


def sheet(name):
    z = ZONES[name]
    out = np.zeros((T * (VARIANTS + 3), T * 16, 4), dtype=np.uint8)

    def place(col, row, tile):
        out[row * T:(row + 1) * T, col * T:(col + 1) * T] = tile

    for mask in range(16):
        for v in range(VARIANTS):
            place(mask, v, ground_tile(z, mask, v, seed=mask * 7 + v * 131 + {'mossy': 11, 'drowned': 22, 'ember': 33}[name] * 1000))
    for i, w in enumerate(['tl', 'tr', 'bl', 'br']):
        place(i, VARIANTS, inner_corner(z, w))
    for i in range(4):
        place(4 + i, VARIANTS, fringe(z, seed=900 + i))
    for i in range(8):
        place(8 + i, VARIANTS, flower(z, i, seed=500 + i))
    for i, part in enumerate(['left', 'mid', 'mid2', 'right', 'single']):
        place(i, VARIANTS + 1, platform(z, part, seed=40 + i))
    for f in range(4):
        place(f, VARIANTS + 2, liquid(z, True, f))
        place(4 + f, VARIANTS + 2, liquid(z, False, f))
    place(8, VARIANTS + 2, crate(z))
    for k in range(4):
        place(9 + k, VARIANTS + 2, chip(z, k))
    return Image.fromarray(out, 'RGBA')
