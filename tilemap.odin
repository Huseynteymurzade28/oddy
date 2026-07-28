package game

import "core:math"
import rl "vendor:raylib"

TILE :: 16
TILESET_COLUMNS :: 20

Tile :: enum u8 {
	Empty,
	Rock, // mossy cave rock, the ordinary terrain
	Deep, // unlit rock, used for bedrock and room borders
	Moss, // overgrown rock, marks the surface of a room
	Platform, // one-way: solid from above only
	Water, // hazard, does not block movement
	Gate, // seals the boss room; every gate tile clears when the key is taken
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

// Outside the map the world is solid rock, except above it, so a jump that
// overshoots the ceiling does not slam into an invisible wall.
tile_at :: proc(m: ^Tilemap, x, y: int) -> Tile {
	if y < 0 {
		return .Empty
	}
	if x < 0 || x >= m.width || y >= m.height {
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
	return t == .Rock || t == .Deep || t == .Moss || t == .Gate
}

is_hazard :: proc(t: Tile) -> bool {
	return t == .Water
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

// Hazards do not block movement, they just kill, so they are queried separately.
tilemap_touches_hazard :: proc(m: ^Tilemap, r: rl.Rectangle) -> bool {
	x0, y0, x1, y1 := tile_range(r)
	for ty in y0 ..= y1 {
		for tx in x0 ..= x1 {
			if is_hazard(tile_at(m, tx, ty)) {
				return true
			}
		}
	}
	return false
}

// ---------------------------------------------------------------- rendering ---

/*
The tileset holds several 6x6 blocks, each one a full nine-slice of a material:
the outer ring is its edges and corners, and the 4x4 interior is fill variants.
A material only has to name the index of its top-left corner.
*/
MATERIAL_ROCK :: 0
MATERIAL_DEEP :: 6
MATERIAL_MOSS :: 120

// The one-way platforms are a single strip: a left cap, four middles, a right cap.
PLATFORM_LEFT :: 12
PLATFORM_MID :: 13
PLATFORM_RIGHT :: 17

// Water is a 2x2 pattern (a surface row over a body row) with five frames of
// animation stacked down the sheet, two rows apart.
WATER_SURFACE :: 18
WATER_BODY :: 38
WATER_FRAMES :: 5
WATER_FRAME_STRIDE :: 40
WATER_FRAME_TIME :: 0.18

@(private = "file")
material_base :: proc(t: Tile) -> int {
	switch t {
	case .Rock:
		return MATERIAL_ROCK
	case .Deep:
		return MATERIAL_DEEP
	case .Moss:
		return MATERIAL_MOSS
	case .Gate:
		return MATERIAL_DEEP
	case .Empty, .Platform, .Water:
	}
	return -1
}

tileset_source :: proc(index: int) -> rl.Rectangle {
	return {f32(index % TILESET_COLUMNS) * TILE, f32(index / TILESET_COLUMNS) * TILE, TILE, TILE}
}

// Cheap deterministic noise so neighbouring fill tiles do not all pick the same
// variant, without having to store a variant per cell.
@(private = "file")
variant :: proc(x, y, salt: int) -> int {
	h := (x * 73856093) ~ (y * 19349663) ~ (salt * 83492791)
	h = h ~ (h >> 13)
	return abs(h) % 4
}

// Picks the nine-slice cell for a solid tile from which of its four neighbours
// are also solid. Different materials still count as joined, so a mossy surface
// sits flush on the rock below it.
@(private = "file")
solid_source :: proc(m: ^Tilemap, x, y: int, t: Tile) -> rl.Rectangle {
	base := material_base(t)
	if base < 0 {
		return {}
	}
	up := is_blocking(tile_at(m, x, y - 1))
	down := is_blocking(tile_at(m, x, y + 1))
	left := is_blocking(tile_at(m, x - 1, y))
	right := is_blocking(tile_at(m, x + 1, y))

	col := 0
	switch {
	case left && right:
		col = 1 + variant(x, y, 1)
	case left:
		col = 5
	case:
		// No neighbour on the left; an isolated column reads best as a left cap.
		col = 0
	}

	row := 0
	switch {
	case up && down:
		row = 1 + variant(x, y, 2)
	case up:
		row = 5
	case:
		row = 0
	}

	return tileset_source(base + col + TILESET_COLUMNS * row)
}

@(private = "file")
water_source :: proc(m: ^Tilemap, x, y: int, time: f32) -> rl.Rectangle {
	frame := int(time / WATER_FRAME_TIME) % WATER_FRAMES
	row := tile_at(m, x, y - 1) == .Water ? WATER_BODY : WATER_SURFACE
	col := ((x % 2) + 2) % 2 // the pattern is two tiles wide
	return tileset_source(row + col + frame * WATER_FRAME_STRIDE)
}

@(private = "file")
platform_source :: proc(m: ^Tilemap, x, y: int) -> rl.Rectangle {
	left := tile_at(m, x - 1, y) == .Platform
	right := tile_at(m, x + 1, y) == .Platform
	switch {
	case left && right:
		return tileset_source(PLATFORM_MID + variant(x, y, 3))
	case left:
		return tileset_source(PLATFORM_RIGHT)
	}
	return tileset_source(PLATFORM_LEFT)
}

tilemap_draw :: proc(m: ^Tilemap, a: ^Assets, view: rl.Rectangle, time: f32) {
	x0 := max(0, int(math.floor(view.x / TILE)) - 1)
	y0 := max(0, int(math.floor(view.y / TILE)) - 1)
	x1 := min(m.width - 1, int((view.x + view.width) / TILE) + 1)
	y1 := min(m.height - 1, int((view.y + view.height) / TILE) + 1)

	for y in y0 ..= y1 {
		for x in x0 ..= x1 {
			t := tile_at(m, x, y)
			if t == .Empty {
				continue
			}
			dest := rl.Rectangle{f32(x) * TILE, f32(y) * TILE, TILE, TILE}
			src: rl.Rectangle
			tint := rl.WHITE
			switch t {
			case .Water:
				src = water_source(m, x, y, time)
				tint = {255, 255, 255, 210}
			case .Platform:
				src = platform_source(m, x, y)
			case .Gate:
				// A sealed door reads as bedrock lit from within, pulsing so it
				// is obvious it is waiting on something.
				src = solid_source(m, x, y, t)
				pulse := u8(180 + 60 * math.sin(time * 4 + f32(y)))
				tint = {255, 210, pulse, 255}
			case .Rock, .Deep, .Moss:
				src = solid_source(m, x, y, t)
			case .Empty:
				continue
			}
			rl.DrawTexturePro(a.tileset, src, dest, {}, 0, tint)
		}
	}
}
