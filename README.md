# Oddy

A hard, precision platformer in Odin + raylib, for desktop and Android. Dash,
wall-jump and climb your way down through the layers of the Hollow: one touch
of anything sharp and you are back at the last checkpoint, the clock still
running.

```
tools/build_raylib.sh linux      # once: builds the raylib the game links
odin run src -out:oddy
```

Asset paths are relative to the working directory, so run it from the repo root.
For a phone, see [Android](#android).

## Where it is

Oddy used to be a procedural run-based shooter (that version is on `main`). The
`platformer` branch is rebuilding it as a hand-made world-map platformer: three
worlds of five levels each, the last of each a boss you beat without a gun.

1. **Movement** — done: no guns, no procedural rooms; coyote time, jump
   buffering, variable jump height, wall jumps, an 8-way dash, one-hit deaths
   with an instant respawn.
2. **LDtk levels** — done: `levels/oddy.ldtk`, with levels 1-1 and 1-2.
3. Traps, moving pieces and enemies you stomp.
4. The world map, saving, fruit, medals, secret exits, skins.
5. The fifteen levels and the three bosses.
6. Art, music and sound.

## Controls

| Desktop | Phone | |
|---|---|---|
| `A` `D` / arrows | left thumb, anywhere on the left half | move |
| `W` `S` / arrows | the same stick, up and down | aim the dash; down drops through a platform |
| `Space` (or `C`, `J`) | the green button | jump; against a wall, wall jump. Let go early for a short hop |
| `Shift` (or `X`, `K`) | the blue button | dash the way you are aiming, or the way you face |
| `P` / `Esc` | Back, or the pause button in the corner | pause |
| arrows + `Enter`, or click | tap | menu buttons |
| `F11` | | fullscreen |
| `F5` | | read the levels file again (see [Editing levels](#editing-levels)) |

The touch layout can be tried on a desktop with the mouse as one finger:
`odin run src -define:TOUCH=true -out:oddy`.

## Movement

- **The dash.** One per time in the air, back when you land; the body turns
  blue while it is spent and flashes when it comes back. Eight directions,
  about four tiles on its own, and the world stops for a beat when it starts.
- **Super and hyper jumps.** Jump while a sideways dash is still touching the
  ground and it becomes a long, fast jump; from a dash diagonally down it is a
  lower, longer one. Either gives the dash straight back.
- **Wall jumps.** Off any wall you are touching, or within three pixels of. A
  wall jump cancels a dash, so you can dash into a wall and kick off it.
- **Forgiving edges.** Coyote time and jump buffering forgive a press that is a
  little early or late, a jump that ends a few pixels under a ledge is lifted
  onto it, a head that clips a corner slides past it, and gravity eases off at
  the top of a held jump. Spikes only hurt in the half against their rock.
- **Numbers.** A jump clears four and a half tiles up and about six and a half
  across at a run; jump and dash at the top about nine; jump and dash straight
  up about eight high.

## Editing levels

The levels live in one [LDtk](https://ldtk.io) project, `levels/oddy.ldtk`,
and are played in the order LDtk lists them. Open it in LDtk 1.5, draw, save,
and press `F5` in the running game: it reads the file again and restarts the
level you are on.

- **Collision** (IntGrid, 16px): `1` rock, `2` one-way platform, `3` spikes
  (they point away from the rock beside them), `4` water. Only the shape is
  drawn; the game picks the grass, edges and corners itself from which
  neighbours are rock.
- **Entities**: `Player_Start` (one per level), `Checkpoint`, `Exit` (the flag
  that finishes the level), and `Hint`, a line of text floating in the level
  (its `Text` field).
- **Level fields**: `Name`, shown when the level starts and on the clear card,
  and `Zone` (`Mossy`, `Drowned`, `Ember`), which picks the colours, the light
  and what drifts through the air.

Anything else in the file is ignored by the game. If the file cannot be read,
the game starts in a bare room whose hint says why.

## Android

```
tools/build_raylib.sh android    # once: raylib for arm64, with the NDK
tools/build_android.sh           # build/oddy.apk
tools/build_android.sh run       # ...and install it on the connected phone and start it
```

Needs the Android SDK (build-tools, a platform, the NDK) under `ANDROID_HOME` or
`~/Android/Sdk`, and a JDK for `apksigner`. The APK is signed with the debug key
Android Studio makes, so it installs from `adb` or a file but is not a store
build. It is an arm64 NativeActivity with no Java: raylib's own Android glue
calls into the Odin library (see `src/main_android.odin`), and the assets ship
in the APK as they are in the repo.

## raylib

The game links raylib 6.0 statically, built from raylib's source by
`tools/build_raylib.sh` into `libs/raylib/<platform>/` (the libraries are not
checked in). `libs/raylib/` also holds a copy of Odin's raylib bindings with the
library paths pointed there, so a build does not depend on what the system's
Odin or raylib package happens to ship.

## Layout

Code is one Odin package in `src/`. Odin makes a directory a package, and this
game is small enough and cross-referential enough that splitting it would buy
nothing but import cycles, so files are grouped by prefix instead.

| File | |
|---|---|
| `main.odin` | window setup and the main loop |
| `main_android.odin` | the entry point raylib calls on Android |
| `game.odin` | the `Game` struct, update order, draw order |
| `input.odin` | keyboard and touch, read into one `Input` per frame |
| `player.odin` | movement, jumps, the dash, death and respawn |
| `physics.odin` | axis-separated AABB vs tiles, one-way platforms |
| `ldtk.odin` | reading `levels/oddy.ldtk` |
| `level.odin` | the level being played: checkpoints, the flag, hints, best clears |
| `tilemap.odin` | tile grid, spikes, materials, nine-slicing, drawing |
| `camera.odin` | virtual resolution, the following camera, parallax, vignette |
| `lighting.odin` | the light map and every light in it |
| `zone.odin` | the three worlds and how each one looks |
| `decor.odin` | torches, roots, stalactites, crystals, drifting motes |
| `atmosphere.odin` | sun shafts, the glow off water and lava |
| `fx.odin` | sparks: dust, dash puffs, death bursts |
| `lore.odin` | every line of prose in the game |
| `animation.odin` | sprite sheets and the animation player |
| `assets.odin` | every file the game loads, in one place |
| `hud.odin` | shared drawing helpers, the clock and the death count |
| `hud_touch.odin` | the on-screen stick and buttons |
| `hud_screens.odin` | title, how-to-play, pause and level-clear boards |
| `ui.odin` | menu buttons and boards: layout, press handling, nine-slicing |

## Assets

See `assets/CREDITS.md`. Everything under `assets/` is loaded by `assets.odin`
and nothing else opens a file, so moving or replacing art is a one-file change.

`assets/sprites/objects/` splits two ways: `animated/` holds the sprite sheets
that play (the flag), and the sibling folders are numbered still images kept
for scenery — `grass/`, `bushes/`, `stones/`, `ridges/`,
`fence/`, `boxes/`, `trees/`, `willows/`, `ladders/`, `pointers/`. They are not
loaded at the moment.
