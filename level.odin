package game

import "core:strings"
import rl "vendor:raylib"

/*
Legend for LEVEL_DATA (level_data.odin):

	terrain            entities                decorations
	  .  empty           @  player spawn         T  tree
	  #  earth/grass     X  exit door            b  bush
	  S  stone           c  checkpoint sign      h  flowers
	  G  gold            o  coin                 m  mushroom
	  =  one-way plat    f  fruit (heals 1)      n  fence
	  W  water (deadly)  g  green slime
	  L  lava (deadly)   p  purple slime (fast)

Entity and decoration characters leave the tile itself empty, so a coin sitting
on the ground is written directly over the row above the ground.
*/

// Fills `g` from LEVEL_DATA: builds the tilemap and spawns every entity.
level_load :: proc(g: ^Game) {
	rows := strings.split_lines(strings.trim_space(LEVEL_DATA), context.temp_allocator)

	width := 0
	for row in rows {
		width = max(width, len(row))
	}
	g.world = tilemap_make(width, len(rows))

	clear(&g.enemies)
	clear(&g.pickups)
	clear(&g.checkpoints)
	g.coins_total = 0

	for row, y in rows {
		for c, x in row {
			// Bottom centre of this tile, the convention every entity uses.
			foot := rl.Vector2{f32(x) * TILE + TILE / 2, f32(y) * TILE + TILE}

			switch c {
			case '#':
				tile_set(&g.world, x, y, .Dirt)
			case 'S':
				tile_set(&g.world, x, y, .Stone)
			case 'G':
				tile_set(&g.world, x, y, .Gold)
			case '=':
				tile_set(&g.world, x, y, .Platform)
			case 'W':
				tile_set(&g.world, x, y, .Water)
			case 'L':
				tile_set(&g.world, x, y, .Lava)

			case 'T':
				deco_set(&g.world, x, y, .Tree)
			case 'b':
				deco_set(&g.world, x, y, .Bush)
			case 'h':
				deco_set(&g.world, x, y, .Flowers)
			case 'm':
				deco_set(&g.world, x, y, .Mushroom)
			case 'n':
				deco_set(&g.world, x, y, .Fence)

			case '@':
				player_init(&g.player, foot)
			case 'X':
				g.goal = Goal{{x, y}}
			case 'c':
				append(&g.checkpoints, checkpoint_make(x, y))
			case 'o':
				append(&g.pickups, pickup_make(.Coin, x, y))
				g.coins_total += 1
			case 'f':
				append(&g.pickups, pickup_make(.Fruit, x, y))
			case 'g':
				append(&g.enemies, enemy_make(.Green, foot))
			case 'p':
				append(&g.enemies, enemy_make(.Purple, foot))
			}
		}
	}
}
