"""The launcher icon: the hero dashing across the meadow of world 1.

Writes an adaptive icon (Android 8+: a background and a foreground layer, the
system masks them to its own shape) and a plain one for older phones:

    android/res/mipmap-anydpi-v26/ic_launcher.xml
    android/res/mipmap-xxxhdpi/ic_launcher_background.png   432x432
    android/res/mipmap-xxxhdpi/ic_launcher_foreground.png   432x432
    android/res/mipmap-xxxhdpi/ic_launcher.png              192x192
"""

import os

from PIL import Image, ImageDraw

import backgrounds

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
RES = os.path.join(ROOT, 'android', 'res')
SPRITES = os.path.join(ROOT, 'assets', 'sprites')


def background():
    """A square of the meadow backdrop around the sun, scaled 2x."""
    scene = Image.new('RGBA', (backgrounds.W, backgrounds.H))
    for layer in backgrounds.make('mossy'):
        scene.alpha_composite(layer)
    crop = scene.crop((262, 46, 262 + 216, 46 + 216))
    return crop.resize((432, 432), Image.NEAREST)


def foreground():
    """The hero mid-dash with a trail of blue afterimages and two gems,
    inside the 264px safe zone in the middle."""
    out = Image.new('RGBA', (432, 432), (0, 0, 0, 0))
    sheet = Image.open(os.path.join(SPRITES, 'skins', 'virtual_guy', 'run.png')).convert('RGBA')
    hero = sheet.crop((32 * 4, 0, 32 * 5, 32))  # a stride, legs out
    scale = 5
    big = hero.resize((32 * scale, 32 * scale), Image.NEAREST)
    cx, cy = 250, 216
    for k, alpha in [(3, 70), (2, 110), (1, 160)]:
        ghost = big.copy()
        r, g, b, a = ghost.split()
        tint = Image.new('RGBA', ghost.size, (120, 180, 255, 0))
        tint.putalpha(a.point(lambda v: v * alpha // 255))
        out.alpha_composite(tint, (cx - 80 - k * 34, cy - 80))
    out.alpha_composite(big, (cx - 80, cy - 80))
    gem = Image.open(os.path.join(SPRITES, 'fx', 'gem.png')).convert('RGBA').crop((24, 0, 36, 12))
    for (x, y, s) in [(318, 118, 4), (330, 286, 3)]:
        out.alpha_composite(gem.resize((12 * s, 12 * s), Image.NEAREST), (x, y))
    # Speed lines behind it.
    d = ImageDraw.Draw(out)
    for y, length in [(170, 70), (214, 96), (262, 60)]:
        d.rectangle((84 - length // 3, y, 84 + length // 2, y + 5), fill=(255, 255, 255, 170))
    return out


def legacy(bg, fg):
    """For phones before adaptive icons: both layers on a rounded square."""
    full = bg.copy()
    full.alpha_composite(fg)
    small = full.crop((54, 54, 378, 378)).resize((192, 192), Image.LANCZOS)
    mask = Image.new('L', (192, 192), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, 191, 191), radius=40, fill=255)
    small.putalpha(mask)
    return small


def make():
    bg, fg = background(), foreground()
    hd = os.path.join(RES, 'mipmap-xxxhdpi')
    os.makedirs(hd, exist_ok=True)
    bg.save(os.path.join(hd, 'ic_launcher_background.png'), optimize=True)
    fg.save(os.path.join(hd, 'ic_launcher_foreground.png'), optimize=True)
    legacy(bg, fg).save(os.path.join(hd, 'ic_launcher.png'), optimize=True)
    v26 = os.path.join(RES, 'mipmap-anydpi-v26')
    os.makedirs(v26, exist_ok=True)
    with open(os.path.join(v26, 'ic_launcher.xml'), 'w') as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n'
                '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
                '\t<background android:drawable="@mipmap/ic_launcher_background" />\n'
                '\t<foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
                '</adaptive-icon>\n')
