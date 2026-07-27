package game

import "core:math"
import rl "vendor:raylib"

CHECKPOINT_TILE_OFF :: 72 // pale signpost
CHECKPOINT_TILE_ON :: 56 // same sign, painted
GOAL_TILE_DOOR :: 55
GOAL_TILE_SIGN :: 50

Checkpoint :: struct {
	tile:   [2]int,
	active: bool,
	pulse:  f32, // grows briefly when the flag is claimed
}

checkpoint_make :: proc(tx, ty: int) -> Checkpoint {
	return {tile = {tx, ty}}
}

// Where the player respawns: standing on the tile below the sign.
checkpoint_spawn :: proc(c: Checkpoint) -> rl.Vector2 {
	return {f32(c.tile.x) * TILE + TILE / 2, f32(c.tile.y) * TILE + TILE}
}

checkpoint_rect :: proc(c: Checkpoint) -> rl.Rectangle {
	return {f32(c.tile.x) * TILE - 2, f32(c.tile.y) * TILE, TILE + 4, TILE}
}

checkpoint_draw :: proc(c: Checkpoint, a: ^Assets) {
	index := c.active ? CHECKPOINT_TILE_ON : CHECKPOINT_TILE_OFF
	scale := 1 + math.sin(clamp(c.pulse, 0, 1) * math.PI) * 0.35
	w := f32(TILE) * scale
	dest := rl.Rectangle {
		f32(c.tile.x) * TILE + TILE / 2 - w / 2,
		f32(c.tile.y) * TILE + TILE - w,
		w,
		w,
	}
	tint := c.active ? rl.WHITE : rl.Color{170, 170, 190, 255}
	rl.DrawTexturePro(a.tileset, tileset_source(index), dest, {}, 0, tint)
}

Goal :: struct {
	tile: [2]int,
}

goal_rect :: proc(g: Goal) -> rl.Rectangle {
	return {f32(g.tile.x) * TILE, f32(g.tile.y) * TILE, TILE, TILE}
}

goal_draw :: proc(g: Goal, a: ^Assets, time: f32) {
	door := rl.Rectangle{f32(g.tile.x) * TILE, f32(g.tile.y) * TILE, TILE, TILE}
	rl.DrawTexturePro(a.tileset, tileset_source(GOAL_TILE_DOOR), door, {}, 0, rl.WHITE)

	sign := door
	sign.y -= TILE + 4 + math.sin(time * 2.5) * 2
	rl.DrawTexturePro(a.tileset, tileset_source(GOAL_TILE_SIGN), sign, {}, 0, rl.WHITE)
}
