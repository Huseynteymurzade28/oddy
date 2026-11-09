# Credits

The art, fonts and audio under `assets/` come from third-party packs and are not
this project's work. Files have been renamed and pruned to match the code layout;
the pixels are unchanged.

| Folder | Pack | Author | Licence |
|---|---|---|---|
| `sprites/player/` (Virtual Guy) | [Pixel Adventure 1](https://opengameart.org/content/pixel-adventure-1) | Pixel Frog | CC-BY 4.0 |
| `sprites/enemies/` (pig, slime, rhino, bat, ghost, bee, rocks) | [Pixel Adventure 2](https://opengameart.org/content/pixel-adventure-2) | Pixel Frog | CC-BY 4.0 |
| `sprites/tileset.png` rows 12-23 (the earth, brick and wooden platforms), `sprites/objects/animated/flag.png` | [Pixel Adventure 1](https://opengameart.org/content/pixel-adventure-1) | Pixel Frog | CC-BY 4.0 |

`enemies/rock/*_hit.png`, `big_break.png`, `small_death.png` and `slam.png` are
the pack's one-frame hit poses repeated with a pixel or two of sideways shake,
so they can play as animations. The tileset rows were rearranged from the
pack's terrain sheet into the 6x6 blocks `tilemap.odin` reads.

**TODO — fill in before publishing:**

| Folder | Pack | Author | Licence |
|---|---|---|---|
| `sprites/tileset.png` rows 0-11 (the water), `sprites/objects/` (except the flag), `sprites/background/` | | | |
| `sounds/`, `music/` | | | |
| `fonts/pixel_operator_bold.ttf` | PixelOperator | Jayvee Enaguas (HarvettFox96) | CC0 |
| `ui/` (menu buttons and boards) | [Pixel UI pack](https://opengameart.org/content/pixel-ui-pack-750-assets) | Kenney (kenney.nl) | CC0 — `ui/LICENSE_kenney_pixel_ui.txt` |

## Not under `assets/`

- **raylib** 6.0, linked statically from `libs/raylib/` — Ramon Santamaria
  (raysan5), zlib/libpng licence (`libs/raylib/LICENSE`). The `.odin` files in
  that folder are Odin's `vendor:raylib` bindings (Odin is BSD-3-Clause), copied
  with only the library paths changed.
- The torches, roots, stalactites, crystals, mushrooms, drifting motes, the
  lighting, sun shafts, the spikes, the touch controls and the Android
  launcher icon (Virtual Guy on a drawn sky) are drawn in code for this
  project; no third-party art was added for them.
