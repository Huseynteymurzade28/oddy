package game

import "core:math"
import rl "../libs/raylib"

TILE :: 16
TILESET_COLUMNS :: 20

Tile :: enum u8 {
	Empty,
	Rock, // mossy cave rock, the ordinary terrain
	Deep, // unlit rock, used for bedrock and room borders
	Moss, // overgrown rock, marks the surface of a room
	Platform, // one-way: solid from above only
	Water, // hazard, does not block movement
	Spike, // hazard on the side it points to; see `spike_hitbox`
	Crate, // solid until a dash or a head breaks it; see `crate_break`
}

Tilemap :: struct {
	width:  int,
	height: int,
	tiles:  []Tile,
}

tilemap_make :: proc(width, height: int) -> Tilemap {
	return {width = width, height = height, tiles = make([]Tile, width * height)}
}

tilemap_destroy :: proc(m: ^Tilemap) {
	delete(m.tiles)
	m^ = {}
}

// Outside the map the sides are solid rock. Above and below it is open air:
// a jump that overshoots the top does not hit an invisible ceiling, and a fall
// out of the bottom is a death (see `player_update`).
tile_at :: proc(m: ^Tilemap, x, y: int) -> Tile {
	if y < 0 || y >= m.height {
		return .Empty
	}
	if x < 0 || x >= m.width {
		return .Deep
	}
	return m.tiles[y * m.width + x]
}

tile_set :: proc(m: ^Tilemap, x, y: int, t: Tile) {
	if x >= 0 && x < m.width && y >= 0 && y < m.height {
		m.tiles[y * m.width + x] = t
	}
}

is_blocking :: proc(t: Tile) -> bool {
	return t == .Rock || t == .Deep || t == .Moss || t == .Crate
}

// Ground for the look of things: what the autotiler joins up. A crate is
// solid but sits apart, so the earth around it keeps its edges.
is_ground :: proc(t: Tile) -> bool {
	return t == .Rock || t == .Deep || t == .Moss
}

tilemap_bounds :: proc(m: ^Tilemap) -> rl.Vector2 {
	return {f32(m.width) * TILE, f32(m.height) * TILE}
}

@(private = "file")
tile_range :: proc(r: rl.Rectangle) -> (x0, y0, x1, y1: int) {
	return int(math.floor(r.x / TILE)),
		int(math.floor(r.y / TILE)),
		int(math.floor((r.x + r.width - 0.01) / TILE)),
		int(math.floor((r.y + r.height - 0.01) / TILE))
}

// Does the rectangle overlap solid ground? Used to keep spawns out of walls.
tilemap_overlaps_solid :: proc(m: ^Tilemap, r: rl.Rectangle) -> bool {
	x0, y0, x1, y1 := tile_range(r)
	for ty in y0 ..= y1 {
		for tx in x0 ..= x1 {
			if is_blocking(tile_at(m, tx, ty)) {
				return true
			}
		}
	}
	return false
}

// Which way a spike points: away from the rock it grows on. A spike with rock
// on no side points up.
spike_dir :: proc(m: ^Tilemap, x, y: int) -> [2]int {
	switch {
	case is_blocking(tile_at(m, x, y + 1)):
		return {0, -1}
	case is_blocking(tile_at(m, x, y - 1)):
		return {0, 1}
	case is_blocking(tile_at(m, x - 1, y)):
		return {1, 0}
	case is_blocking(tile_at(m, x + 1, y)):
		return {-1, 0}
	}
	return {0, -1}
}

// Only the half of a spike tile against its rock hurts, and not quite all of
// that: brushing the tips of a row of spikes is a near miss, not a death.
SPIKE_DEPTH :: 7
SPIKE_INSET :: 2

spike_hitbox :: proc(m: ^Tilemap, x, y: int) -> rl.Rectangle {
	ox, oy := f32(x) * TILE, f32(y) * TILE
	switch spike_dir(m, x, y) {
	case {0, 1}:
		return {ox + SPIKE_INSET, oy, TILE - SPIKE_INSET * 2, SPIKE_DEPTH}
	case {1, 0}:
		return {ox, oy + SPIKE_INSET, SPIKE_DEPTH, TILE - SPIKE_INSET * 2}
	case {-1, 0}:
		return {ox + TILE - SPIKE_DEPTH, oy + SPIKE_INSET, SPIKE_DEPTH, TILE - SPIKE_INSET * 2}
	}
	return {ox + SPIKE_INSET, oy + TILE - SPIKE_DEPTH, TILE - SPIKE_INSET * 2, SPIKE_DEPTH}
}

// Hazards do not block movement, they just kill, so they are queried separately.
// Water kills anywhere in its tile, spikes only in their hitbox.
tilemap_touches_hazard :: proc(m: ^Tilemap, r: rl.Rectangle) -> bool {
	x0, y0, x1, y1 := tile_range(r)
	for ty in y0 ..= y1 {
		for tx in x0 ..= x1 {
			switch tile_at(m, tx, ty) {
			case .Water:
				return true
			case .Spike:
				if rl.CheckCollisionRecs(r, spike_hitbox(m, tx, ty)) {
					return true
				}
			case .Empty, .Rock, .Deep, .Moss, .Platform, .Crate:
			}
		}
	}
	return false
}

// ---------------------------------------------------------------- rendering ---

/*
Each world's terrain sheet (drawn by tools/art/terrain.py) is 16 tiles wide:

  rows 0-5  the ground. The column is which of the four neighbours are also
            ground (1 up, 2 right, 4 down, 8 left), the row one of six
            variants, so every edge and corner has its own tile.
  row 6     inner corners (0-3), grass fringes standing above an exposed top
            (4-7), and flowers and tufts (8-15).
  row 7     one-way platform: left end, two middles, right end, a lone one.
  row 8     liquid: the surface in four frames (0-3), the body (4-7).

The ground darkens a step with each tile further from the open air above it,
which gives the earth depth without a second set of tiles.
*/

terrain_source :: proc(col, row: int) -> rl.Rectangle {
	return {f32(col) * TILE, f32(row) * TILE, TILE, TILE}
}

LIQUID_FRAME_TIME :: 0.2
GROUND_VARIANTS :: 6
ROW_EXTRAS :: GROUND_VARIANTS
ROW_PLATFORM :: GROUND_VARIANTS + 1
ROW_LIQUID :: GROUND_VARIANTS + 2

// Cheap deterministic noise, so neighbouring tiles do not all pick the same
// variant, without having to store a variant per cell.
@(private = "file")
cell_hash :: proc(x, y, salt: int) -> int {
	h := (x * 73856093) ~ (y * 19349663) ~ (salt * 83492791)
	h = h ~ (h >> 13)
	return abs(h)
}

@(private = "file")
solid_at :: proc(m: ^Tilemap, x, y: int) -> bool {
	return is_ground(tile_at(m, x, y))
}

tilemap_draw :: proc(g: ^Game, view: rl.Rectangle) {
	m := &g.map_tiles
	tex := g.assets.terrain[g.level.zone]
	x0 := max(0, int(math.floor(view.x / TILE)) - 1)
	y0 := max(0, int(math.floor(view.y / TILE)) - 1)
	x1 := min(m.width - 1, int((view.x + view.width) / TILE) + 1)
	y1 := min(m.height - 1, int((view.y + view.height) / TILE) + 1)
	frame := int(g.time / LIQUID_FRAME_TIME) % 4

	draw :: proc(tex: rl.Texture2D, col, row, x, y: int, tint := rl.WHITE) {
		rl.DrawTexturePro(tex, terrain_source(col, row), {f32(x) * TILE, f32(y) * TILE, TILE, TILE}, {}, 0, tint)
	}

	for y in y0 ..= y1 {
		for x in x0 ..= x1 {
			switch tile_at(m, x, y) {
			case .Rock, .Deep, .Moss:
				up := solid_at(m, x, y - 1)
				right := solid_at(m, x + 1, y)
				down := solid_at(m, x, y + 1)
				left := solid_at(m, x - 1, y)
				mask := int(up) | int(right) << 1 | int(down) << 2 | int(left) << 3
				// How deep under the surface: a step darker per tile.
				depth := 0
				for depth < 4 && solid_at(m, x, y - depth - 1) && y - depth - 1 >= 0 {
					depth += 1
				}
				k := u8(255 - depth * 14)
				draw(tex, mask, cell_hash(x, y, 1) % GROUND_VARIANTS, x, y, {k, k, k, 255})
				if up && left && !solid_at(m, x - 1, y - 1) {draw(tex, 0, ROW_EXTRAS, x, y)}
				if up && right && !solid_at(m, x + 1, y - 1) {draw(tex, 1, ROW_EXTRAS, x, y)}
				if down && left && !solid_at(m, x - 1, y + 1) {draw(tex, 2, ROW_EXTRAS, x, y)}
				if down && right && !solid_at(m, x + 1, y + 1) {draw(tex, 3, ROW_EXTRAS, x, y)}
			case .Platform:
				left := tile_at(m, x - 1, y) == .Platform
				right := tile_at(m, x + 1, y) == .Platform
				col := 4
				switch {
				case left && right:
					col = 1 + cell_hash(x, y, 3) % 2
				case right:
					col = 0
				case left:
					col = 3
				}
				draw(tex, col, ROW_PLATFORM, x, y)
			case .Water:
				surface := tile_at(m, x, y - 1) != .Water
				col := (frame + x) % 4 + (surface ? 0 : 4)
				draw(tex, col, ROW_LIQUID, x, y, {255, 255, 255, 235})
			case .Spike:
				draw_spike(g, x, y)
			case .Crate:
				draw(tex, 8, ROW_LIQUID, x, y)
			case .Empty:
			}
		}
	}

	// What grows on top: a fringe of grass over every exposed top, and now
	// and then a flower, in the open cell above the ground.
	for y in y0 ..= y1 {
		for x in x0 ..= x1 {
			if !solid_at(m, x, y) || tile_at(m, x, y - 1) != .Empty {
				continue
			}
			draw(tex, 4 + cell_hash(x, y, 5) % 4, ROW_EXTRAS, x, y - 1)
			if h := cell_hash(x, y, 9) % 100; h < 26 {
				// Flowers nod in a breeze that rolls along the ground.
				sway := math.round(math.sin(g.time * 2.2 + f32(x) * 0.7) * 1.2)
				dest := rl.Rectangle{f32(x) * TILE + sway, f32(y - 1) * TILE, TILE, TILE}
				rl.DrawTexturePro(tex, terrain_source(8 + h % 8, ROW_EXTRAS), dest, {}, 0, rl.WHITE)
			}
		}
	}
}

// Pixel Adventure's spikes point up from the bottom of their cell; any other
// way is the same sprite turned.
@(private = "file")
draw_spike :: proc(g: ^Game, x, y: int) {
	d := spike_dir(&g.map_tiles, x, y)
	angle: f32
	switch d {
	case {0, 1}:
		angle = 180
	case {1, 0}:
		angle = 90
	case {-1, 0}:
		angle = 270
	}
	tex := g.assets.traps.spikes
	src := rl.Rectangle{0, 0, f32(tex.width), f32(tex.height)}
	dest := rl.Rectangle{f32(x) * TILE + TILE / 2, f32(y) * TILE + TILE / 2, TILE, TILE}
	rl.DrawTexturePro(tex, src, dest, {TILE / 2, TILE / 2}, angle, rl.WHITE)
}
