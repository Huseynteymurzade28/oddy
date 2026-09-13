# Oddy

A 2D run-based platform shooter in Odin + raylib. Every run builds a fresh
network of rooms: find the rune-key, unseal the vault, and break the warden.

```
odin run src -out:oddy
```

Asset paths are relative to the working directory, so run it from the repo root.

## The run

The Hollow under Greyreach took the mine, then the miners, then the town. At the
bottom of it the warden — a golem built to keep the deep sealed — has spent a
century feeding it instead.

1. Explore the Hollow and find the **rune-key**.
2. The key unseals the **warden's vault** — every door into it is barred until
   you have it.
3. **Break the warden.** That is the way out.

Somewhere in the middle of the map there is a **stall**. It is the only place
coins are worth anything, and it never has enough on it to sell you everything.

Dying rebuilds the whole map, so no two descents are the same.

## Controls

| Key | |
|---|---|
| `A` `D` / arrows | move |
| `Space` | jump — again in the air to double jump |
| `Space` against a wall | wall jump |
| Mouse | aim |
| Left click | shoot |
| `E` | open a chest, again to take the gun — or buy at the stall |
| `F11` | fullscreen |
| `R` | new run (on an end screen) |

## Mechanics

- **Rolled weapons.** Chests roll a gun from a class and a rarity; deeper rooms
  tilt the rarity table upward. The starting pistol never runs out of ammo, so a
  run can never stall on an empty gun.
- **The stall.** Three crates, three offers, one run's worth of coins — a gun,
  and two of {a heart, a heart container, a full magazine, a trigger job}. Never
  enough money for all three, and it does not restock, so what you skip is gone.
- **Coyote time, jump buffering, variable jump height** — a jump pressed slightly
  early or slightly late still counts, and releasing early cuts it short.
- **Rooms wake up.** Enemies only act while you are in their room.
- **The golem has two phases.** Its armour soaks half of everything until it
  breaks, and the unarmoured form throws shockwaves along the floor.

## Layout

Code is one Odin package in `src/`. Odin makes a directory a package, and this
game is small enough and cross-referential enough that splitting it into several
would buy nothing but import cycles — so files are grouped by prefix instead, and
`assets/` mirrors those groups.

| File | |
|---|---|
| `main.odin` | window setup and the main loop |
| `game.odin` | the `Game` struct, update order, draw order |
| `camera.odin` | virtual resolution, room-locked camera, parallax, vignette |
| `lore.odin` | **the story** — every line of prose in the game |
| `world.odin` | the room grid: roles, doors, queries |
| `world_gen.odin` | growing a run: layout, stamping, doors, spawns |
| `world_templates.odin` | **the room shapes** — one character per tile |
| `tilemap.odin` | tile grid, materials, nine-slicing, drawing |
| `physics.odin` | axis-separated AABB vs tiles, one-way platforms |
| `player.odin` | movement, jump feel, damage, shooting |
| `enemy.odin` | walkers, flyers, and the golem's two phases |
| `weapon.odin` | weapon classes, rarity rolls, holding and drawing a gun |
| `bullet.odin` | shots, impacts, muzzle flashes, sparks |
| `chest.odin` | chests and the take-it-or-leave-it prompt |
| `shop.odin` | the stall: what it offers, what it costs, what it does |
| `pickup.odin` | coins, healing runes, the key |
| `animation.odin` | sprite sheets and the animation player |
| `assets.odin` | every file the game loads, in one place |
| `hud.odin` | shared drawing helpers, hearts, coins, weapon panel |
| `hud_minimap.odin` | the map panel |
| `hud_screens.odin` | title and end cards |

## Editing rooms

`world_templates.odin` holds the room shapes as text, one character per 16x16
tile, `ROOM_W` x `ROOM_H` per block. The legend is at the top of that file:

```
  terrain                 spawn candidates
    .  empty                E  enemy
    #  rock                 C  chest
    X  bedrock              o  coin
    %  mossy surface        r  health rune
    =  one-way platform     S  the player's starting flag
    ~  water (deadly)       K  the boss key
                            B  the boss
                            M  the stall
```

Spawn characters are offers, not orders — the generator decides how many of them
a given room actually uses, based on its role and how deep it is.

Doors are punched through templates after the fact, so two rules keep a run
traversable: columns `DOOR_X..DOOR_X+3` must stay clear on the top rows with
something to jump from below, and rows `DOOR_Y..DOOR_Y+2` must stay clear along
both side walls.

## Assets

See `assets/CREDITS.md`. Everything under `assets/` is loaded by `assets.odin`
and nothing else opens a file, so moving or replacing art is a one-file change.

`assets/sprites/objects/` splits two ways: `animated/` holds the sprite sheets
that play (chest, coin, key, rune, flag), and the sibling folders are numbered
still images used as scenery — `grass/`, `bushes/`, `stones/`, `ridges/`,
`fence/`, `boxes/`, `trees/`, `willows/`, `ladders/`, `pointers/`. A folder is one
`Prop_Kind`, so adding a variant means dropping in the next number and bumping
one count in `assets.odin`.
