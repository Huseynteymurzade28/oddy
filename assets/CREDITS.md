# Credits

The art, fonts and audio under `assets/` come from third-party packs and are not
this project's work. Files have been renamed and pruned to match the code layout;
the pixels are unchanged.

| Folder | Pack | Author | Licence |
|---|---|---|---|
| `sprites/skins/` (Virtual Guy, Ninja Frog, Pink Man, Mask Dude), `sprites/player/` (the puffs you appear and vanish in), `sprites/fruit/` | [Pixel Adventure 1](https://opengameart.org/content/pixel-adventure-1) | Pixel Frog | CC-BY 4.0 |
| `sprites/enemies/` (pig, slime, rhino, bat, ghost, bee, rocks) | [Pixel Adventure 2](https://opengameart.org/content/pixel-adventure-2) | Pixel Frog | CC-BY 4.0 |
| `sprites/traps/` (saw, spikes, trampoline, platforms, fan, fire, balloon, spiked head), `sprites/objects/checkpoint/` | [Pixel Adventure 1](https://opengameart.org/content/pixel-adventure-1) | Pixel Frog | CC-BY 4.0 |
| `sounds/` | [The Essential Retro Video Game Sound Effects Collection](https://opengameart.org/content/512-sound-effects-8-bit-style) | Juhani Junkala | CC0 |
| `fonts/pixel_operator_bold.ttf` | PixelOperator | Jayvee Enaguas (HarvettFox96) | CC0 |
| `ui/` (menu buttons and boards) | [Pixel UI pack](https://opengameart.org/content/pixel-ui-pack-750-assets) | Kenney (kenney.nl) | CC0 — `ui/LICENSE_kenney_pixel_ui.txt` |

`enemies/rock/*_hit.png`, `big_break.png`, `small_death.png` and `slam.png` are
the pack's one-frame hit poses repeated with a pixel or two of sideways shake,
so they can play as animations. The sounds are
renamed for what they do in the game (`jump.wav` was `sfx_movement_jump1.wav`).

| `music/` (menu, moss, drowned and ember: [Chiptune Adventures](https://opengameart.org/content/4-chiptunes-adventure); boss: [Epic Boss Battle](https://opengameart.org/content/boss-battle-music)) | Chiptune Adventures, Epic Boss Battle | Juhani Junkala | CC0 |

Every asset in the game now has a known source and licence.

## Drawn for this game

`sprites/terrain/` (the ground, grass, flowers, bridges, water, lava and
crates of each world), `sprites/background/` (the skies, clouds, mountains,
ruins, volcanoes, hills and trees) and `sprites/fx/` (the gem, butterflies and
birds) are this project's own, drawn pixel by pixel by
`tools/art/make_art.py` from the palettes in `tools/art/palette.py`.

`sounds/light_on.wav`, `sounds/light_off.wav` and `sounds/room.wav` are this
project's own too, made by `tools/audio/make_sfx.py`.

## Not under `assets/`

- **raylib** 6.0, linked statically from `libs/raylib/` — Ramon Santamaria
  (raysan5), zlib/libpng licence (`libs/raylib/LICENSE`). The `.odin` files in
  that folder are Odin's `vendor:raylib` bindings (Odin is BSD-3-Clause), copied
  with only the library paths changed.
- The torches, roots, stalactites, crystals, mushrooms, drifting motes, the
  lighting, sun shafts, the arrow shooters and arrows, the fan's air, the
  geysers, the bosses' ripples and rocks, and the touch controls are drawn in
  code for this project. The Android launcher icon is drawn by
  `tools/art/icon.py` from the game's own backdrop and its hero sprite.
