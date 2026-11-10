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
// Spikes kill in their hitbox; liquid only when it is lava (`liquid_kills`),
// otherwise you swim in it.
tilemap_touches_hazard :: proc(m: ^Tilemap, r: rl.Rectangle, liquid_kills: bool) -> bool {
	x0, y0, x1, y1 := tile_range(r)
	for ty in y0 ..= y1 {
		for tx in x0 ..= x1 {
			switch tile_at(m, tx, ty) {
			case .Water:
				if liquid_kills {
					return true
				}
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

The ground darkens the further it is from the open sky, which gives the earth
depth without a second set of tiles: that is the light map's doing, see
`lighting_bake`.
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
				draw(tex, mask, cell_hash(x, y, 1) % GROUND_VARIANTS, x, y)
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
				// Foam only where the water meets open air, not under a roof.
				surface := tile_at(m, x, y - 1) == .Empty
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

// The water again, see-through, over whatever is in it: the player and the
// creatures look like they are in it rather than in front of it. Then its
// depth: the liquid darkens the further down it goes, and daylight slants
// in through the surface.
tilemap_draw_water_front :: proc(g: ^Game, view: rl.Rectangle) {
	m := &g.map_tiles
	zone := g.level.zone
	lava := zone == .Ember
	tex := g.assets.terrain[zone]
	x0 := max(0, int(math.floor(view.x / TILE)) - 1)
	y0 := max(0, int(math.floor(view.y / TILE)) - 1)
	x1 := min(m.width - 1, int((view.x + view.width) / TILE) + 1)
	y1 := min(m.height - 1, int((view.y + view.height) / TILE) + 1)
	frame := int(g.time / LIQUID_FRAME_TIME) % 4

	DEEP :: 7 // tiles down at which it is as dark as it gets
	deep := lava ? rl.Color{84, 8, 14, 120} : rl.Color{10, 30, 96, 150}
	shade :: proc(deep: rl.Color, tiles: int) -> rl.Color {
		c := deep
		c.a = u8(f32(deep.a) * f32(min(tiles, DEEP)) / DEEP)
		return c
	}

	for y in y0 ..= y1 {
		for x in x0 ..= x1 {
			if tile_at(m, x, y) != .Water {
				continue
			}
			surface := tile_at(m, x, y - 1) == .Empty
			if !lava { // nothing swims in lava
				col := (frame + x) % 4 + (surface ? 0 : 4)
				rl.DrawTexturePro(tex, terrain_source(col, ROW_LIQUID), {f32(x) * TILE, f32(y) * TILE, TILE, TILE}, {}, 0, {255, 255, 255, 110})
			}
			above := 0
			for above < DEEP && tile_at(m, x, y - above - 1) == .Water {
				above += 1
			}
			rl.DrawRectangleGradientV(i32(x * TILE), i32(y * TILE), TILE, TILE, shade(deep, above), shade(deep, above + 1))
		}
	}

	rl.BeginBlendMode(.ADDITIVE)
	for y in y0 ..= y1 {
		for x in x0 - 3 ..= x1 {
			if tile_at(m, x, y) != .Water || tile_at(m, x, y - 1) != .Empty {
				continue
			}
			px := f32(x) * TILE
			py := f32(y) * TILE
			if lava {
				// The surface is the hottest part: a band of glow along it.
				pulse := 0.7 + 0.3 * math.sin(g.time * 2.4 + f32(x) * 0.9)
				hot := rl.Color{u8(150 * pulse), u8(84 * pulse), u8(20 * pulse), 255}
				rl.DrawRectangleGradientV(i32(px), i32(py) + 2, TILE, 9, hot, {0, 0, 0, 255})
				rl.DrawRectangleGradientV(i32(px), i32(py) - 9, TILE, 11, {0, 0, 0, 255}, {u8(70 * pulse), u8(30 * pulse), 0, 255})
				continue
			}
			if cell_hash(x, y, 21) % 3 != 0 {
				continue
			}
			// A shaft of daylight, as deep as there is water for it.
			room := 0
			for room < 5 && tile_at(m, x + (room + 1) / 3, y + room) == .Water {
				room += 1
			}
			if room < 2 {
				continue
			}
			breathe := 0.6 + 0.4 * math.sin(g.time * 1.1 + f32(x) * 1.3)
			width := 5 + f32(cell_hash(x, y, 22) % 6)
			length := f32(room) * TILE - 3
			SEGMENTS :: 6
			for seg in 0 ..< SEGMENTS {
				t0 := f32(seg) / SEGMENTS
				t1 := f32(seg + 1) / SEGMENTS
				a := 30 * (1 - t0) * breathe
				c := rl.Color{u8(a * 0.55), u8(a * 0.9), u8(a), 255}
				ax := px + 4 + length * t0 * 0.3
				bx := px + 4 + length * t1 * 0.3
				ay := py + 3 + length * t0
				by := py + 3 + length * t1
				w0 := width * (1 + t0 * 0.8)
				w1 := width * (1 + t1 * 0.8)
				tri({ax, ay}, {ax + w0, ay}, {bx + w1, by}, c)
				tri({ax, ay}, {bx + w1, by}, {bx, by}, c)
			}
		}
	}
	rl.EndBlendMode()
}
