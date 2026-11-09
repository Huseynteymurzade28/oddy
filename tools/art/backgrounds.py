"""Draws each world's parallax backdrop: five 480x270 layers, every one of
them wrapping seamlessly left to right.

  0 sky      a banded gradient and the sun, fixed behind everything
  1 clouds   drifting slowly on their own
  2 far      mountains, towers or volcanoes on the horizon
  3 mid      rolling hills with trees, ruins or dark ridges
  4 near     the closest silhouettes, at the bottom of the screen

Every shape is built from sums of sines with whole-number periods across the
width, which is what makes the wrap seamless.
"""

import math

import numpy as np
from PIL import Image

from palette import ZONES

W, H = 480, 270
TAU = 2 * math.pi


def canvas():
    return np.zeros((H, W, 4), dtype=np.uint8)


def wave(x, terms, phase=0.0):
    """A height that repeats every W pixels: terms are (period count, size)."""
    return sum(a * math.sin(TAU * k * x / W + phase * (i + 1)) for i, (k, a) in enumerate(terms))


def disc(img, cx, cy, r, c, ry=None):
    ry = r if ry is None else ry
    for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
        if y < 0 or y >= H:
            continue
        for x in range(int(cx - r) - 1, int(cx + r) + 2):
            if ((x - cx) / r) ** 2 + ((y - cy) / ry) ** 2 <= 1:
                img[y, x % W] = c


def ridge(img, base, terms, colour, phase=0.0, rim=None):
    """Fills everything below a wrapping line, with an optional lighter rim."""
    for x in range(W):
        top = int(base + wave(x, terms, phase))
        img[max(top, 0):, x] = colour
        if rim is not None and 0 <= top < H:
            img[top, x] = rim


def dither_gradient(img, stops, top, bottom):
    """Bands of the stop colours from `top` to `bottom`, with a checkered
    dither where two bands meet: the pixel-art way to paint a sky."""
    n = len(stops) - 1
    for y in range(top, bottom):
        t = (y - top) / max(bottom - top - 1, 1) * n
        i = min(int(t), n - 1)
        f = t - i
        for x in range(W):
            use_next = f > 0.5 + (0.25 if (x + y) % 2 else -0.25)
            img[y, x] = stops[i + 1] if use_next else stops[i]


def cloud(img, cx, cy, size, cols, rng):
    """A puffy cloud: a flat bottom, a row of bumps, and its shadow side."""
    puffs = []
    n = int(size / 6) + 2
    for i in range(n):
        px = cx - size / 2 + size * i / max(n - 1, 1)
        r = size * (0.22 + 0.18 * math.sin(i / max(n - 1, 1) * math.pi)) + rng.random() * 3
        puffs.append((px, cy - r * 0.35, r))
    for px, py, r in puffs:  # shadow first, a little lower
        disc(img, px, py + 2, r, cols[2])
    for px, py, r in puffs:
        disc(img, px, py, r, cols[1])
    for px, py, r in puffs:
        disc(img, px - r * 0.2, py - r * 0.25, r * 0.65, cols[0])
    bottom = int(cy + 2)
    img[bottom:bottom + 6, :] = img[bottom:bottom + 6, :]  # flat underside left as drawn


def layer_sky(z, name):
    img = canvas()
    dither_gradient(img, z['sky'], 0, H)
    # The sun: high and white-gold over the meadow, soft over the water,
    # low and huge in the volcanic dusk.
    sun = {'mossy': (360, 52, 18), 'drowned': (120, 60, 15), 'ember': (300, 150, 34)}[name]
    sx, sy, sr = sun
    glow = z['sky'][-1]
    for k, alpha in [(2.6, 50), (1.9, 90), (1.4, 140)]:
        layer = canvas()
        disc(layer, sx, sy, sr * k, (*glow[:3], alpha))
        mask = layer[:, :, 3] > 0
        for c in range(3):
            img[:, :, c][mask] = ((img[:, :, c][mask].astype(np.int32) * (255 - alpha) + glow[c] * alpha) // 255).astype(np.uint8)
    disc(img, sx, sy, sr, (255, 252, 230, 255))
    return img


def layer_clouds(z, name, rng):
    img = canvas()
    for i in range(7):
        cx = i * W / 7 + rng.random() * 30
        cy = 40 + rng.random() * 70 + (i % 2) * 20
        cloud(img, cx, cy, 30 + rng.random() * 40, z['clouds'], rng)
    return img


def layer_far(z, name, rng):
    img = canvas()
    f = z['far']
    if name == 'mossy':
        # Blue mountains with snow on the peaks.
        terms = [(2, 26), (5, 12), (9, 5)]
        ridge(img, 150, terms, f[0], 0.7)
        for x in range(W):
            top = int(150 + wave(x, terms, 0.7))
            if top < 140:
                depth = int((140 - top) * 0.6) + 2
                img[top:top + depth, x] = f[2]
        ridge(img, 182, [(3, 10), (7, 5)], f[1], 2.1)
    elif name == 'drowned':
        # A far shore of ruined towers and arches in the haze.
        ridge(img, 190, [(2, 6), (5, 3)], f[1], 1.3)
        for i in range(9):
            x0 = int(i * W / 9 + rng.random() * 20)
            w = int(10 + rng.random() * 12)
            h = int(40 + rng.random() * 60)
            for x in range(x0, x0 + w):
                img[190 - h:200, x % W] = f[0]
            for x in range(x0 - 1, x0 + w + 1):  # a broken crown
                if rng.random() < 0.6:
                    img[190 - h - 2:190 - h, x % W] = f[0]
            for y in range(190 - h + 6, 190, 10):  # windows
                img[y:y + 4, (x0 + w // 2) % W] = f[1]
    else:
        # Volcanoes on the skyline, smoke rising from the tallest.
        for i, (cx, h) in enumerate([(60, 70), (230, 110), (390, 60)]):
            for x in range(cx - 110, cx + 110):
                top = 190 - h + abs(x - cx) * h / 110 + 3 * math.sin(x * 0.3)
                img[int(max(top, 0)):, x % W] = f[0]
            img[190 - h:190 - h + 4, cx - 6:cx + 6] = f[2]
        for k in range(14):
            disc(img, 230 + math.sin(k) * 8 + k * 2, 75 - k * 6, 6 + k * 0.8, (*f[1][:3], 255))
        ridge(img, 196, [(4, 6), (9, 3)], f[1], 0.4)
    return img


def tree(img, x, base, h, cols, trunk, rng):
    """A round-topped tree: a trunk and three stacked blobs of leaves."""
    for y in range(base - h // 2, min(base, H)):
        img[y, int(x) % W] = trunk[1]
        img[y, int(x + 1) % W] = trunk[0]
    r = h * 0.38
    disc(img, x + 1, base - h * 0.6, r, cols[2])
    disc(img, x - r * 0.3, base - h * 0.62, r * 0.8, cols[1])
    disc(img, x + r * 0.2, base - h * 0.78, r * 0.7, cols[0])


def layer_mid(z, name, rng):
    img = canvas()
    m = z['mid']
    if name == 'mossy':
        terms = [(2, 14), (3, 8), (7, 3)]
        ridge(img, 205, terms, m[1], 1.9, rim=m[0])
        for i in range(16):
            x = i * W / 16 + rng.random() * 12
            base = int(205 + wave(x, terms, 1.9)) + 3
            tree(img, x, base, int(26 + rng.random() * 18), z['mid'][::-1][::-1], z['trunk'], rng)
        ridge(img, 232, [(3, 6), (8, 3)], m[2], 0.3)
    elif name == 'drowned':
        terms = [(2, 10), (5, 5)]
        ridge(img, 210, terms, m[1], 0.9, rim=m[0])
        for i in range(10):
            x = i * W / 10 + rng.random() * 20
            base = int(210 + wave(x, terms, 0.9))
            h = int(30 + rng.random() * 40)
            for xx in range(int(x), int(x) + 8):  # a column, its capital
                img[base - h:base, xx % W] = m[0] if xx == int(x) else m[1]
            for xx in range(int(x) - 2, int(x) + 10):
                img[base - h - 3:base - h, xx % W] = m[0]
        ridge(img, 236, [(4, 4), (9, 2)], m[2], 0.2)
    else:
        terms = [(2, 12), (4, 6)]
        ridge(img, 208, terms, m[1], 0.5, rim=m[0])
        # Rivers of lava glinting down the dark hills.
        lava = z['liquid'][1]
        for i in range(5):
            x = i * W / 5 + rng.random() * 30
            y = int(208 + wave(x, terms, 0.5)) + 2
            for k in range(26):
                cx = int(x + math.sin(k * 0.3) * 4)
                yy = min(y + k, H - 1)
                img[yy, (cx - 1) % W] = z['liquid'][2]
                img[yy, cx % W] = z['liquid'][0] if k % 5 == 0 else lava
                img[yy, (cx + 1) % W] = lava
                img[yy, (cx + 2) % W] = z['liquid'][2]
        ridge(img, 234, [(3, 5), (7, 3)], m[2], 1.1)
    return img


def layer_near(z, name, rng):
    img = canvas()
    n = z['near']
    if name == 'mossy':
        for i in range(11):
            x = i * W / 11 + rng.random() * 16
            tree(img, x, H + 14, int(46 + rng.random() * 26), n, z['trunk'], rng)
        ridge(img, 254, [(5, 4), (11, 2)], n[2], 0.8)
    elif name == 'drowned':
        # Kelp swaying up from the bottom, leaves out to either side.
        for i in range(13):
            x = i * W / 13 + rng.random() * 12
            h = int(45 + rng.random() * 55)
            for k in range(h):
                xx = int(x + math.sin(k * 0.08 + i) * 4)
                for dx in range(3):
                    img[H - k - 1, (xx + dx) % W] = n[2] if dx == 2 else n[1]
                if k % 9 == 4:
                    side = 1 if (k // 9) % 2 else -1
                    disc(img, xx + 1 + side * 4, H - k - 1, 3.5, n[0], 1.6)
        ridge(img, 254, [(4, 3), (9, 2)], n[2], 0.6)
    else:
        for i in range(7):
            x = i * W / 7 + rng.random() * 30
            h = int(30 + rng.random() * 30)
            disc(img, x, H - h * 0.3, h * 0.8, n[1], h * 0.5)
            disc(img, x - h * 0.2, H - h * 0.4, h * 0.4, n[0], h * 0.2)
        ridge(img, 250, [(5, 4), (12, 2)], n[2], 1.4)
    return img


def make(name):
    z = ZONES[name]
    rng = np.random.default_rng({'mossy': 1, 'drowned': 2, 'ember': 3}[name])
    layers = [
        layer_sky(z, name),
        layer_clouds(z, name, rng),
        layer_far(z, name, rng),
        layer_mid(z, name, rng),
        layer_near(z, name, rng),
    ]
    return [Image.fromarray(l, 'RGBA') for l in layers]
