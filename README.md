# Lumi & the Hollow

A cozy, hard little platformer for Android phones. Lumi is a small light, and
the Hollow under the town of Greyreach goes down in layers: a garden, a
drowned town, a warm heart of embers, each with something keeping the way
down. Dash, wall-jump, swim and bounce your way to the bottom; one touch of
anything sharp and you are back at the start of the room, or at the last
lantern, with the clock still running.

Her light is her dash, and the dash is a switch: light blocks are solid while
she shines, shadow blocks only while her dash is spent.

Built in [Odin](https://odin-lang.org) on [raylib](https://www.raylib.com), as
a NativeActivity with no Java.

| | |
|---|---|
| ![The title](media/title.png) | ![The world map](media/map.png) |
| ![A wall of light, solid while the dash is ready](media/light.png) | ![The same room mid-dash: the light is open air](media/light_spent.png) |
| ![Swimming in the Drowned Halls](media/swim.png) | ![The Ember Deep](media/ember.png) |

## Play it

Download `lumi-<version>.apk` from the [Releases](../../releases) page and
open it on the phone (Android 10 or newer, arm64); the phone will ask to allow
installs from wherever you opened it. Every push to `main` also builds an APK,
attached to its run on the [Actions](../../actions) page.

## Controls

| Phone | | Keyboard (development) |
|---|---|---|
| left thumb, anywhere on the left half | move | `A` `D` / arrows |
| the same stick, any of eight ways | aim the dash; pulled down, drop through a platform. A wedge on the rim shows where a dash would go | `W` `S` / arrows |
| the green button | jump, and off walls. On a phone every jump is full height | `Space` (or `C`, `J`); let go early for a short hop |
| the blue button | dash; dimmed while it is spent | `Shift` (or `X`, `K`) |
| Back, or the pause button in the corner | pause | `P` / `Esc` |

The phone buzzes on a dash, when you land on a creature, at a checkpoint, on
a death and at the end of a level.

**Settings** (on the title and the pause card): music and sound volume,
vibration, and two comforts for a gentler game: a slower game speed (down to
55%, the clock slows with it) and a dash that never runs out (not in levels
with light and shadow blocks, where the dash running out is the puzzle).

On the world map, tap a level to pick it and tap it again (or PLAY) to go;
the arrows by the title turn to the next world, HERO picks who you play as.
On a keyboard: left and right, `Q` `E` for worlds, `Enter`, `H`, `Esc`.

## The worlds

- **The Moss** (1-1 to 1-5): four levels of rooms, 22 in all, each a screen
  with one idea in it: the basics, walls, then light and shadow blocks, a
  climb, a gauntlet. At the end, the Ooze King.
- **The Drowned Halls** (2-1 to 2-5): water you can swim in. You sink
  slowly, jump strokes you upward, a stroke at the surface throws you out,
  and the water gives your dash back. Underwater tunnels, walls to dive
  under, spiked heads, a lift, and the Broodmother.
- **The Ember Deep** (3-1 to 3-5): the liquid is lava and kills. Geysers
  bubble, then erupt and throw you high; fire, saws over lava, a climb up a
  chimney of ash, a gauntlet of everything, and the Warden.

Worlds 2 and 3 are still the older, scrolling kind of level; they are next
in line to be rebuilt as rooms.

## Rooms and light

- **Rooms.** A level can be cut into rooms, each about a screen. The camera
  stays in the room you are in and slides across to the next; the world holds
  still while it does, and you arrive with your dash back. Die and you are
  back at that room's entrance, with everything in it as it was. The pips at
  the top of the screen count the rooms.
- **Light blocks** are solid while the dash is ready, and open air while it
  is spent. **Shadow blocks** are the other way round. So a dash opens the
  bright wall in front of you, takes the bright floor from behind you, and
  makes the dark ledge you are about to need; and anything that hands the
  dash back in mid-air (a refill, a trampoline, a creature's head) throws the
  switch back while you are still flying.
- **Two rules keep it fair.** Standing on a shadow block does not bring the
  dash back, or it would vanish under you. And nothing closes on you: a block
  that ought to turn solid where you are standing waits until you have left.

## Bosses

The last level of each world. No gun: every boss is beaten by landing on it
at the right moment, and every move it makes is telegraphed. The exit stays
shut until it is down; dying puts it back at full strength.

- **The Ooze King** (1-5). It squats, then hops at you, and every landing
  sends a ripple along the floor to jump. Just after it lands it sags, open:
  land on it. Three hits; each makes it smaller and quicker, and from the
  second on it sheds little slimes. A hit throws you clear.
- **The Broodmother** (2-5). She sweeps the top of the arena, screeches and
  flushes red as she picks her spot, then dives at where you are: step
  aside. Crashing into the floor stuns her. From the second hit she calls her
  young.
- **The Warden** (3-5). It paws the ground, then charges the length of the
  arena: jump it. It crashes into the wall behind you and is dazed for long
  enough to run the arena. Once hit, every crash shakes rocks loose, marked
  where they will land, and always behind you, so stepping out from under
  them takes you toward it.

While a boss is stunned, or recovering, bumping into it is harmless. Every
hit buys a breather: the rocks and ripples already on their way are called
off, you are thrown clear (away from the wall, if it has its back to one),
and it cannot hurt you until you have got off it. The last hit is final, even
if something gets you before it has finished falling over.

## Things to find and break

- **Gems.** Strung along good paths and spilling out of crates. Pick a run of
  them up quickly and each one rings a note higher. They stay picked up when
  you die; the clear card counts them, and the map keeps your best.
- **Crates.** Dash into one, dash down onto one, or jump into it from below
  and it bursts into three gems.
- **Combos.** Land on creature after creature, or a creature and a
  trampoline, without touching the ground: each bounce is called out (x2,
  x3...) and pitched higher.

## The map, fruit and medals

- **Worlds and levels.** A level opens when the one before it is cleared; a
  world opens when the last level of the world before it is. Your progress is
  saved on the phone as you go.
- **Fruit.** Hidden around each level. Touch one and it follows you; it is
  only yours once you have stood on solid ground with it for a moment, or
  reached a checkpoint or the end. Die first and it goes back.
- **Medals.** Three per level, shown as dots under it on the map: finish
  inside the par time, finish without dying, keep every fruit.
- **Secret exits.** Some levels hide a second way out, a purple trophy. It
  finishes the level and opens a hidden level on the map. There is one in 1-1.
- **Heroes.** Virtual Guy from the start; Ninja Frog for 5 fruit, Pink Man for
  6 medals, Mask Dude for beating a secret level.

## Movement

- **The dash.** One per time in the air, back when you land; Lumi's glow
  turns from gold to a pale blue while it is spent and flashes when it comes
  back. Eight directions, about four tiles on its own, and the world stops
  for a beat when it starts. A third of a second between one dash and the
  next.
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

## Where it is

The project started as Oddy, a procedural run-based shooter for desktop (that
version is tagged `shooter-final`), and was rebuilt as a hand-made world-map
platformer for phones. It is playable start to finish: three worlds of five
levels, a secret level, three bosses, a map, a save, music.

What is being worked on now:

- **Rooms for Worlds 2 and 3.** World 1 has been rebuilt as hard, screen-sized
  rooms around the light and shadow blocks. The other two worlds, the secret
  level and the boss arenas are still as they were, and have only been
  retuned for the heavier, quicker movement that came with the rooms.
- **Art.** Heroes, creatures and traps are Pixel Adventure's; they are to be
  redrawn before any store release.
- **Sound.** Most effects and all the music are CC0 packs.

## Building

```
tools/build_raylib.sh android    # once: raylib for arm64, with the NDK
tools/build_android.sh           # build/lumi.apk
tools/build_android.sh run       # ...then install it on the connected phone and start it
```

Needs [Odin](https://odin-lang.org) (`dev-2026-10`, as CI uses), the Android
SDK (build-tools, a platform, the NDK) under `ANDROID_HOME` or
`~/Android/Sdk`, and a JDK for `apksigner`. The script signs with the debug key
Android Studio makes, or with `ODDY_KEYSTORE` (password `ODDY_KEYSTORE_PASS`).

CI (`.github/workflows/android.yml`) does the same on GitHub's runners for
every push and pull request, and for a tag `v*` puts the APK on a release. With
repository secrets `ODDY_KEYSTORE_B64` (the keystore, base64) and
`ODDY_KEYSTORE_PASS` it signs with that key, so each release installs over the
last; without them every build is signed with a throwaway key and has to be
installed fresh.

### On the desktop, for development

The same code runs in a window on Linux, which is the quick way to work on
levels and movement. It is a development tool, not a release.

```
tools/build_raylib.sh linux      # once
odin run src -out:lumi           # keyboard
odin run src -out:lumi -define:TOUCH=true   # the phone's touch layout, with the mouse as one finger
```

Run it from the repo root (asset paths are relative). `F5` reads the levels
file again, `F11` toggles fullscreen.

Three more builds of the same code, for checking it without playing it:

| | |
|---|---|
| `tools/dev/shots.sh` | plays a fixed script and saves pictures to `build/shots/` (`-define:SHOTS=true`, `src/devshots.odin`); add `-define:TOUCH=true` for the phone's layout |
| `tools/dev/solve.sh` | gets through every room by brute force, once with plain moves and once with every trick, and names any room it cannot (`-define:SOLVE=true`, `src/devsolve.odin`). `tools/dev/solve.sh W1_2` checks one level; `TRACE=1 build/lumi_solve W1_2` prints the route |
| `tools/dev/soak.sh` | plays every level with a button-mashing hero for hours of game time in a few seconds, looking for ways to get stuck: a boss out of its arena or stuck in one state, a fight that cannot be finished, an exit that stays shut, a death with no respawn (`-define:SOAK=true`, `src/devsoak.odin`). `TRACE=1 build/lumi_soak W2_5` prints each fight |

Run the soak after touching a boss, and the solver after touching a room or
the movement.

## Editing levels

The levels live in one [LDtk](https://ldtk.io) project, `levels/lumi.ldtk`,
and are played in the order LDtk lists them. There are two ways to make one.

**As text**, for levels made of rooms. Each is a file in `levels/rooms/`
named after its level (`W1_2.txt`): a few `key: value` lines (`name`, `par`,
`zone`), then its rooms, thirty characters by fifteen rows each, introduced
by `===`:

```
#  rock          =  one-way platform   ^  spikes        ~  water    C  crate
L  light block   D  shadow block       @  spawn point   E  exit     X  secret exit
o  gem           F  fruit              R  dash refill   T  trampoline
S  saw           ff falling platform   P  pig   B  bat   M  slime
```

`tools/levels/build.py` writes them into the LDtk file, leaving every other
level alone (the top of that script has the whole format).
`tools/dev/solve.sh` runs it first, so solving a level also rebuilds it.

**In LDtk**, for everything else: open the file in LDtk 1.5, draw, save, and
press `F5` in the running game. It reads the file again and restarts the
level you are on.

- **Collision** (IntGrid, 16px): `1` rock, `2` one-way platform, `3` spikes
  (they point away from the rock beside them), `4` water, `5` crate, `6` light
  block, `7` shadow block. Only the shape is
  drawn; the game picks the grass, edges and corners itself from which
  neighbours are rock.
- **Entities**: `Player_Start` (one per level), `Checkpoint`, `Exit` (the
  trophy that finishes the level), `Hint`, a line of text floating in the
  level (its `Text` field), and the traps and creatures:

  | Entity | |
  |---|---|
  | `Saw` | resize it into a track; the saw runs end to end along its long side (`Speed`) |
  | `Moving_Platform` | the same, with a platform you can stand on |
  | `Falling_Platform` | drops a moment after you land on it, then grows back |
  | `Trampoline` | throws you high and gives the dash back |
  | `Fan` | blows you up as far as its height |
  | `Fire` | put it over a floor tile: it lights a moment after you step on it |
  | `Arrow_Shooter` | `Dir`, `Interval`, `Delay`; arrows fly about 18 tiles |
  | `Refill` | gives a spent dash back, then grows back |
  | `Spike_Head` | shudders, then drops when you are under it, and climbs back |
  | `Pig`, `Slime` | walk back and forth, turning at walls and edges |
  | `Rino` | charges when you are level with it, dazed when it hits a wall |
  | `Bat` | swings three tiles either side of where it is placed |
  | `Bee` | bobs up and down |
  | `Geyser` | bubbles, then erupts and throws you up to its height (`Delay`) |
  | `Ooze_King`, `Broodmother`, `Warden` | the bosses; the level's exit opens when it is beaten |

  Land on a creature to kill it: you bounce and get the dash back. Touching
  one any other way, or any trap, is a death. Everything is put back as it
  started each time you die.
  Two more for the map: `Fruit`, a collectible (its look is picked by the
  game), and `Secret_Exit`, a second way out whose `Unlocks` field names the
  secret level it opens. And the gems: `Gem` for one, `Gem_Line` for a row or
  column of them, one a tile along the rectangle's long side.
  And for rooms: `Room`, a rectangle about a screen in size (30 by 15 tiles),
  and `Spawn`, where you come back to life in it. A level with no `Room` is
  one big scrolling room with `Checkpoint` lanterns, as levels used to be.
- **Level identifiers** place a level on the map: `W2_4` is world 2, level 4
  (1 to 5, the fifth is the boss); `W1_S1` is a secret level of world 1, shown
  above the level whose secret exit names it.
- **Level fields**: `Name`, shown when the level starts and on the clear card;
  `Zone` (`Mossy`, `Drowned`, `Ember`), which picks the colours, the light and
  what drifts through the air; and `Par`, the seconds to beat for the time
  medal.

Anything else in the file is ignored by the game. If the file cannot be read,
the game starts in a bare room whose hint says why.

## Layout

Code is one Odin package in `src/`. Odin makes a directory a package, and this
game is small enough and cross-referential enough that splitting it would buy
nothing but import cycles, so files are grouped by prefix instead.

| File | |
|---|---|
| `main.odin` | window setup and the main loop |
| `main_android.odin` | the entry point raylib calls on Android |
| `haptics.odin` | vibration on a phone (the C side is `android/native/haptics.c`) |
| `game.odin` | the `Game` struct, update order, draw order |
| `input.odin` | keyboard and touch, read into one `Input` per frame |
| `player.odin` | movement, jumps, the dash, death and respawn |
| `physics.odin` | axis-separated AABB vs tiles, one-way platforms |
| `ldtk.odin` | reading `levels/lumi.ldtk` |
| `level.odin` | the level being played: checkpoints, the exits, fruit, hints |
| `rooms.odin` | rooms: the camera's bounds, the slide between them, where you respawn |
| `light.odin` | light and shadow blocks, switched by the dash |
| `worldmap.odin` | the world map and the hero picker |
| `progress.odin` | what is open and what is earned: unlocks, medals, heroes |
| `save.odin` | the save file |
| `settings.odin` | volumes, vibration and the two comfort settings |
| `music.odin` | the tracks and the crossfade between them |
| `things.odin` | traps and moving pieces |
| `enemy.odin` | the creatures, and landing on them |
| `boss.odin` | the bosses, their floor ripples, the boss bar |
| `tilemap.odin` | tile grid, spikes, autotiling, grass and flowers, drawing |
| `camera.odin` | virtual resolution, the following camera, the parallax backdrops |
| `lighting.odin` | the light map and every light in it |
| `zone.odin` | the three worlds and how each one looks |
| `decor.odin` | torches, roots, stalactites, crystals, drifting motes |
| `atmosphere.odin` | sun shafts, the glow off water and lava |
| `depth.odin` | haze, the mid-ground and the out-of-focus foreground |
| `post.odin` | bloom and the vignette, over the finished picture |
| `fx.odin` | sparks and puffs: dust, dash bursts, the puff you vanish and arrive in |
| `lore.odin` | every line of prose in the game |
| `animation.odin` | sprite sheets and the animation player |
| `assets.odin` | every file the game loads, in one place |
| `hud.odin` | shared drawing helpers, the clock and the death count |
| `hud_touch.odin` | the on-screen stick and buttons |
| `hud_screens.odin` | title, how-to-play, pause and level-clear boards |
| `ui.odin` | menu buttons and boards: layout, press handling, nine-slicing |
| `devshots.odin`, `devsolve.odin`, `devsoak.odin` | the screenshot script, the room solver and the soak test: compiled in only when asked for |

Outside `src/`: `levels/` is the LDtk project and the text rooms it is partly
built from, `android/` the manifest, launcher icon and the native helper,
`tools/` the build scripts, `tools/levels/` the room builder, `tools/dev/` the
three checks above, `tools/art/` the Python that draws the terrain and
backdrops (`python3 tools/art/make_art.py`, needs Pillow and NumPy),
`tools/audio/` the one that synthesizes a few of the sound effects, and
`.github/workflows/android.yml` the CI that builds the APK.

Some names inside still say `oddy` (`liboddy.so`, the `ODDY_*` build
variables and secrets): the project's first name, kept because nothing a
player sees depends on it.

## raylib

The game links raylib 6.0 statically, built from raylib's source by
`tools/build_raylib.sh` into `libs/raylib/<platform>/` (the libraries are not
checked in). `libs/raylib/` also holds a copy of Odin's raylib bindings with the
library paths pointed there, so a build does not depend on what the system's
Odin or raylib package happens to ship.

## Credits

The worlds themselves (ground, grass and flowers, bridges, water, skies and
backdrops) and the launcher icon are drawn for the game by `tools/art/make_art.py`.
Music by Juhani Junkala (CC0). Characters and traps
are from Pixel Frog's Pixel Adventure 1 and 2 (CC-BY 4.0: heroes, creatures,
traps, fruit), menus from Kenney's
Pixel UI pack (CC0), sound effects from Juhani Junkala's Essential Retro Video
Game Sound Effects Collection (CC0). The full list, including what is still to
be replaced, is in `assets/CREDITS.md`.
