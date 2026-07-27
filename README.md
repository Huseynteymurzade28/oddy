# Oddy

A 2D platformer written in Odin + raylib. One large interconnected map: reach
the exit door, and collect all 71 coins along the way if you want the bonus.

```
odin run . -out:oddy
```

## Controls

| Key | |
|---|---|
| `A` / `D` or arrow keys | walk |
| `Space` / `W` / `Up` | jump — hold for a higher one |
| `Down` / `S` | drop through a one-way platform |
| `F11` | fullscreen |
| `R` | restart (on the finish screen) |

## Mechanics

- **Coyote time** (0.10 s): you can still jump for a moment after walking off a
  ledge.
- **Jump buffer** (0.12 s): a jump pressed just before landing still counts.
- **Variable jump height**: releasing the jump key early cuts the upward speed.
- **Stomping**: landing on a slime squashes it and bounces you; touching one
  from the side costs a heart and grants a short invulnerability window.
- **3 hearts + checkpoints**: running out of hearts, or falling into water or
  lava, sends you back to the last sign you touched. Collected coins stay
  collected, enemies come back. Fruit refills one heart.

## File layout

| File | |
|---|---|
| `main.odin` | window setup and the main loop |
| `game.odin` | game state, update order, camera, background |
| `level.odin` | parser turning the map text into tiles and entities |
| `level_data.odin` | **the map itself** — one character per tile |
| `tilemap.odin` | tile grid, materials, decorations, drawing |
| `physics.odin` | axis-separated AABB vs tile collision, one-way platforms |
| `player.odin` | player physics, jump feel, damage and death |
| `enemy.odin` | slime patrol and squashing |
| `pickup.odin` | coins and fruit |
| `checkpoint.odin` | checkpoint signs and the exit door |
| `animation.odin` | sprite sheets and the animation player |
| `assets.odin` | all loading/unloading and animation clips in one place |
| `hud.odin` | hearts, coin counter, menu screens |

## Editing the map

The text block in `level_data.odin` *is* the map — one character per 16x16
tile. The legend lives at the top of `level.odin`:

```
  .  empty            @  player spawn      T  tree
  #  earth/grass      X  exit door         b  bush
  S  stone            c  checkpoint sign   h  flowers
  G  gold             o  coin              m  mushroom
  =  one-way plat     f  fruit (heals 1)   n  fence
  W  water (deadly)   g  green slime
  L  lava (deadly)    p  purple slime (fast)
```

Rows do not have to be the same length; the longest one sets the map width.
Entity and decoration characters leave the tile itself empty, so a coin resting
on the ground is written on the row above the ground.

## Assets

Everything under `assets/` comes from Brackeys' free 2D platformer pack (see
`assets/LICENSE & CREDITS.txt`). The player sprites (`player_idle.png`,
`player_run.png`) are this project's own.
