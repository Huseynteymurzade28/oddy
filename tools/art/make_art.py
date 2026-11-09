#!/usr/bin/env python3
"""Draws all of Oddy's own environment art into assets/sprites/:

    terrain/<world>.png          the ground, platforms, liquid, crates (terrain.py)
    background/<world>_<n>.png   the five parallax layers (backgrounds.py)
    fx/gem.png, fx/critters.png  gems, butterflies and birds (sprites.py)

    python3 tools/art/make_art.py

Run it again after changing a palette or a drawing; the output is the same
every time for the same code.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import backgrounds  # noqa: E402
import sprites  # noqa: E402
import terrain  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
OUT = os.path.join(ROOT, 'assets', 'sprites')

for world in ('mossy', 'drowned', 'ember'):
    os.makedirs(os.path.join(OUT, 'terrain'), exist_ok=True)
    os.makedirs(os.path.join(OUT, 'background'), exist_ok=True)
    terrain.sheet(world).save(os.path.join(OUT, 'terrain', f'{world}.png'), optimize=True)
    for i, layer in enumerate(backgrounds.make(world)):
        layer.save(os.path.join(OUT, 'background', f'{world}_{i}.png'), optimize=True)
    print('drew', world)

os.makedirs(os.path.join(OUT, 'fx'), exist_ok=True)
sprites.gem().save(os.path.join(OUT, 'fx', 'gem.png'), optimize=True)
sprites.critters().save(os.path.join(OUT, 'fx', 'critters.png'), optimize=True)
print('drew the gem and the critters')
