package game

import "core:math"
import rl "vendor:raylib"

TILE :: 16
TILESET_COLUMNS :: 16

Tile :: enum u8 {
	Empty,
	Dirt, // grass-topped earth, the main terrain
	Stone, // caves and bedrock
	Gold, // the plateau near the finish
	Platform, // one-way: solid from above only
	Water, // hazard
	Lava, // hazard
}

Deco :: enum u8 {
	None,
	Tree,
	Bush,
	Flowers,
	Mushroom,
	Fence,
}

Tilemap :: struct {
	width:  int,
	height: int,
	tiles:  []Tile,
	deco:   []Deco,
}

tilemap_make :: proc(width, height: int) -> Tilemap {
	return {
		width = width,
		height = height,
		tiles = make([]Tile, width * height),
		deco = make([]Deco, width * height),
	}
}

tilemap_destroy :: proc(m: ^Tilemap) {
	delete(m.tiles)
	delete(m.deco)
}

// Outside the map the world is solid rock, except above it, so a jump that
// overshoots the ceiling does not slam into an invisible wall.
tile_at :: proc(m: ^Tilemap, x, y: int) -> Tile {
	if y < 0 {
		return .Empty
	}
	if x < 0 || x >= m.width || y >= m.height {
		return .Stone
	}
	return m.tiles[y * m.width + x]
}

tile_set :: proc(m: ^Tilemap, x, y: int, t: Tile) {
	if x >= 0 && x < m.width && y >= 0 && y < m.height {
		m.tiles[y * m.width + x] = t
	}
}

deco_at :: proc(m: ^Tilemap, x, y: int) -> Deco {
	if x < 0 || x >= m.width || y < 0 || y >= m.height {
		return .None
	}
	return m.deco[y * m.width + x]
}

deco_set :: proc(m: ^Tilemap, x, y: int, d: Deco) {
	if x >= 0 && x < m.width && y >= 0 && y < m.height {
		m.deco[y * m.width + x] = d
	}
}

is_blocking :: proc(t: Tile) -> bool {
	return t == .Dirt || t == .Stone || t == .Gold
}

is_hazard :: proc(t: Tile) -> bool {
	return t == .Water || t == .Lava
}

tilemap_bounds :: proc(m: ^Tilemap) -> rl.Vector2 {
	return {f32(m.width) * TILE, f32(m.height) * TILE}
}

// Does the rectangle touch a hazard tile? Hazards do not block movement, they
// just kill, so they are queried separately from the solid tiles.
tilemap_touches_hazard :: proc(m: ^Tilemap, r: rl.Rectangle) -> bool {
	x0 := int(math.floor(r.x / TILE))
	x1 := int(math.floor((r.x + r.width - 0.01) / TILE))
	y0 := int(math.floor(r.y / TILE))
	y1 := int(math.floor((r.y + r.height - 0.01) / TILE))
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

tileset_source :: proc(index: int) -> rl.Rectangle {
	return {
		f32(index % TILESET_COLUMNS) * TILE,
		f32(index / TILESET_COLUMNS) * TILE,
		TILE,
		TILE,
	}
}

// Surface tile and buried tile for each material. Every tile in this pack is a
// self-contained outlined block, so all a cell needs to know is whether it is
// exposed to the sky.
material_tiles :: proc(t: Tile) -> (surface: int, fill: int) {
	switch t {
	case .Dirt:
		return 0, 16
	case .Stone:
		return 8, 24
	case .Gold:
		return 4, 20
	case .Water:
		return 148, 164
	case .Lava:
		return 212, 228
	case .Empty, .Platform:
	}
	return -1, -1
}

// Decorations taller than one tile are listed bottom-first and stacked upwards
// from the cell they were placed in.
deco_tree := [?]int{80, 64, 48}
deco_bush := [?]int{81}
deco_flowers := [?]int{97}
deco_mushroom := [?]int{87}
deco_fence := [?]int{57}

deco_tiles :: proc(d: Deco) -> []int {
	switch d {
	case .Tree:
		return deco_tree[:]
	case .Bush:
		return deco_bush[:]
	case .Flowers:
		return deco_flowers[:]
	case .Mushroom:
		return deco_mushroom[:]
	case .Fence:
		return deco_fence[:]
	case .None:
	}
	return nil
}

// One-way platforms come from their own sheet: column 0 is a standalone stub,
// column 1 has a rounded left cap and a flat right edge (so it also serves as
// the repeating middle), column 2 is the right cap.
platform_source :: proc(m: ^Tilemap, x, y: int) -> rl.Rectangle {
	left := tile_at(m, x - 1, y) == .Platform
	right := tile_at(m, x + 1, y) == .Platform
	col := 0
	switch {
	case left && right, !left && right:
		col = 1
	case left && !right:
		col = 2
	}
	return {f32(col) * TILE, 0, TILE, TILE}
}

tilemap_draw :: proc(m: ^Tilemap, a: ^Assets, view: rl.Rectangle) {
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
			if t == .Platform {
				rl.DrawTexturePro(a.platforms, platform_source(m, x, y), dest, {}, 0, rl.WHITE)
				continue
			}
			surface, fill := material_tiles(t)
			index := fill
			above := tile_at(m, x, y - 1)
			if t == .Water || t == .Lava {
				if above != t {
					index = surface
				}
			} else if above == .Empty || above == .Platform {
				// Only ground open to the sky gets its grassy/decorated top;
				// ground under water or lava stays plain.
				index = surface
			}
			rl.DrawTexturePro(a.tileset, tileset_source(index), dest, {}, 0, rl.WHITE)
		}
	}

	// Decorations are drawn after the terrain so their outlines sit on top of it.
	for y in y0 ..= y1 {
		for x in x0 ..= x1 {
			stack := deco_tiles(deco_at(m, x, y))
			for index, i in stack {
				dest := rl.Rectangle{f32(x) * TILE, f32(y - i) * TILE, TILE, TILE}
				rl.DrawTexturePro(a.tileset, tileset_source(index), dest, {}, 0, rl.WHITE)
			}
		}
	}
}
