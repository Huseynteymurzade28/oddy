"""Small sprites that are the same in every world:

  fx/gem.png        a gem, 6 frames of a glint passing over it (12x12)
  fx/critters.png   row 0 butterflies, three colours by two wing frames
                    (8x8); row 1 a bird, two frames (8x8)
"""

import numpy as np
from PIL import Image

from palette import hexc


def gem():
    W = 12
    out = np.zeros((W, W * 6, 4), dtype=np.uint8)
    o = hexc('#2a1a4a')
    body = [hexc('#7af3ff'), hexc('#3fc9f2'), hexc('#2a8fd8'), hexc('#1e5aa8')]
    shape = [
        "....oooo....",
        "...o0011o...",
        "..o001112o..",
        ".o0011112o..",
        "o001111223o.",
        "o011112233o.",
        ".o1112233o..",
        "..o12233o...",
        "...o233o....",
        "....o3o.....",
        ".....o......",
        "............",
    ]
    for f in range(6):
        for y, row in enumerate(shape):
            for x, ch in enumerate(row):
                if ch == 'o':
                    c = o
                elif ch in '0123':
                    c = body[int(ch)]
                else:
                    continue
                # The glint: a bright diagonal band sweeping across.
                if ch != 'o' and abs((x + y) - (f * 4 - 2)) <= 1:
                    c = (255, 255, 255, 255)
                out[y, f * W + x] = c
    return Image.fromarray(out, 'RGBA')


def critters():
    out = np.zeros((16, 8 * 6, 4), dtype=np.uint8)
    wings = [(hexc('#ff8fb8'), hexc('#ffd0e0')), (hexc('#ffd84a'), hexc('#fff3b0')), (hexc('#9fc8ff'), hexc('#e0efff'))]
    body = hexc('#3a2a3a')
    for i, (w, light) in enumerate(wings):
        for f in range(2):
            x0 = (i * 2 + f) * 8
            for y in range(2, 7):
                out[y, x0 + 3] = body
            if f == 0:  # wings open
                for (x, y) in [(0, 1), (1, 1), (2, 1), (0, 2), (1, 2), (2, 2), (1, 3), (2, 3),
                               (1, 4), (2, 4), (1, 5)]:
                    out[y, x0 + x] = w
                    out[y, x0 + 6 - x] = w
                out[2, x0 + 1] = light
                out[2, x0 + 5] = light
            else:  # wings up
                for (x, y) in [(2, 0), (2, 1), (2, 2), (1, 1), (2, 3), (2, 4)]:
                    out[y, x0 + x] = w
                    out[y, x0 + 6 - x] = w
    bird = hexc('#4a3a5a')
    for f in range(2):
        x0 = f * 8
        pts = [(0, 3), (1, 2), (2, 2), (3, 3), (4, 2), (5, 2), (6, 3)] if f == 0 else \
              [(0, 1), (1, 2), (2, 3), (3, 3), (4, 3), (5, 2), (6, 1)]
        for x, y in pts:
            out[8 + y, x0 + x] = bird
    return Image.fromarray(out, 'RGBA')
