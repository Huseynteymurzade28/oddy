package game

import "core:math/rand"
import rl "vendor:raylib"

/*
The world is a grid of rooms. A run grows a connected blob of them, stamps a
template into each one, punches doors between neighbours, and then decides what
lives inside. Nothing here is persisted: every run regenerates the whole map.
*/

GRID_W :: 5
GRID_H :: 4
ROOMS_PER_RUN :: 11

Dir :: enum u8 {
	North,
	East,
	South,
	West,
}
Dirs :: bit_set[Dir]

DIR_STEP := [Dir][2]int {
	.North = {0, -1},
	.East  = {1, 0},
	.South = {0, 1},
	.West  = {-1, 0},
}

dir_opposite :: proc(d: Dir) -> Dir {
	switch d {
	case .North:
		return .South
	case .South:
		return .North
	case .East:
		return .West
	case .West:
		return .East
	}
	return .North
}

Room_Role :: enum u8 {
	Unused,
	Start,
	Normal,
	Treasure,
	Key,
	Boss,
}

Room :: struct {
	role:  Room_Role,
	doors: Dirs,
	depth: int, // rooms travelled from the start, used to ramp difficulty
	seen:  bool, // has the player been here? drives the minimap
}

World :: struct {
	rooms: [GRID_H][GRID_W]Room,
	start: [2]int, // grid coordinates, {x, y}
	boss:  [2]int,
	gates: [dynamic][2]int, // tile coordinates cleared when the key is taken
}

world_destroy :: proc(w: ^World) {
	delete(w.gates)
	w^ = {}
}

room_at :: proc(w: ^World, x, y: int) -> ^Room {
	if x < 0 || x >= GRID_W || y < 0 || y >= GRID_H {
		return nil
	}
	return &w.rooms[y][x]
}

// Which room a world position falls in.
room_coords :: proc(pos: rl.Vector2) -> [2]int {
	return {int(pos.x) / (ROOM_W * TILE), int(pos.y) / (ROOM_H * TILE)}
}

// The world-space rectangle of a room, used to pen the camera in.
room_rect :: proc(cell: [2]int) -> rl.Rectangle {
	return {
		f32(cell.x * ROOM_W * TILE),
		f32(cell.y * ROOM_H * TILE),
		ROOM_W * TILE,
		ROOM_H * TILE,
	}
}

// ---------------------------------------------------------------- generation ---

@(private = "file")
grow_layout :: proc(w: ^World) {
	// Start on the bottom row: the world then tends to build upward and inward,
	// which reads better than a blob around a random middle cell.
	w.start = {rand.int_max(GRID_W), GRID_H - 1}
	w.rooms[w.start.y][w.start.x].role = .Normal

	used := make([dynamic][2]int, context.temp_allocator)
	append(&used, w.start)

	for len(used) < ROOMS_PER_RUN {
		from := used[rand.int_max(len(used))]
		dir := Dir(rand.int_max(len(Dir)))
		step := DIR_STEP[dir]
		to := [2]int{from.x + step.x, from.y + step.y}

		target := room_at(w, to.x, to.y)
		if target == nil {
			continue
		}
		if target.role == .Unused {
			target.role = .Normal
			append(&used, to)
		}
		// Connect either way: revisiting an existing room just adds a loop, and
		// loops are what make the map feel like a place rather than a tree.
		w.rooms[from.y][from.x].doors += {dir}
		target.doors += {dir_opposite(dir)}
	}
}

// Breadth-first distance from the start room, in rooms.
@(private = "file")
measure_depths :: proc(w: ^World) {
	for y in 0 ..< GRID_H {
		for x in 0 ..< GRID_W {
			w.rooms[y][x].depth = -1
		}
	}
	queue := make([dynamic][2]int, context.temp_allocator)
	append(&queue, w.start)
	w.rooms[w.start.y][w.start.x].depth = 0

	for i := 0; i < len(queue); i += 1 {
		cell := queue[i]
		here := &w.rooms[cell.y][cell.x]
		for dir in here.doors {
			step := DIR_STEP[dir]
			next := [2]int{cell.x + step.x, cell.y + step.y}
			room := room_at(w, next.x, next.y)
			if room == nil || room.role == .Unused || room.depth >= 0 {
				continue
			}
			room.depth = here.depth + 1
			append(&queue, next)
		}
	}
}

@(private = "file")
assign_roles :: proc(w: ^World) {
	// The two rooms hardest to reach become the boss and the key, so the key is
	// always a detour rather than something you trip over on the way.
	best, second := [2]int{-1, -1}, [2]int{-1, -1}
	for y in 0 ..< GRID_H {
		for x in 0 ..< GRID_W {
			if w.rooms[y][x].role == .Unused || (x == w.start.x && y == w.start.y) {
				continue
			}
			d := w.rooms[y][x].depth
			if best.x < 0 || d > w.rooms[best.y][best.x].depth {
				second = best
				best = {x, y}
			} else if second.x < 0 || d > w.rooms[second.y][second.x].depth {
				second = {x, y}
			}
		}
	}

	w.rooms[w.start.y][w.start.x].role = .Start
	if best.x >= 0 {
		w.boss = best
		w.rooms[best.y][best.x].role = .Boss
	}
	if second.x >= 0 {
		w.rooms[second.y][second.x].role = .Key
	}

	// Two treasure rooms, picked from whatever is still ordinary.
	plain := make([dynamic][2]int, context.temp_allocator)
	for y in 0 ..< GRID_H {
		for x in 0 ..< GRID_W {
			if w.rooms[y][x].role == .Normal {
				append(&plain, [2]int{x, y})
			}
		}
	}
	rand.shuffle(plain[:])
	for i in 0 ..< min(2, len(plain)) {
		cell := plain[i]
		w.rooms[cell.y][cell.x].role = .Treasure
	}
}

@(private = "file")
template_for :: proc(role: Room_Role) -> string {
	switch role {
	case .Start:
		return ROOM_START
	case .Boss:
		return ROOM_BOSS
	case .Key:
		return ROOM_KEY
	case .Treasure:
		return ROOM_TREASURE
	case .Normal:
		return ROOM_TEMPLATES[rand.int_max(len(ROOM_TEMPLATES))]
	case .Unused:
	}
	return ROOM_TEMPLATES[0]
}

// Candidate positions harvested from one stamped template, in tile coordinates.
@(private = "file")
Spawns :: struct {
	enemies:  [dynamic][2]int,
	chests:   [dynamic][2]int,
	coins:    [dynamic][2]int,
	runes:    [dynamic][2]int,
	player:   [2]int,
	key:      [2]int,
	boss:     [2]int,
	has_key:  bool,
	has_boss: bool,
}

@(private = "file")
stamp_room :: proc(m: ^Tilemap, cell: [2]int, template: string) -> Spawns {
	s := Spawns {
		enemies = make([dynamic][2]int, context.temp_allocator),
		chests  = make([dynamic][2]int, context.temp_allocator),
		coins   = make([dynamic][2]int, context.temp_allocator),
		runes   = make([dynamic][2]int, context.temp_allocator),
	}
	ox, oy := cell.x * ROOM_W, cell.y * ROOM_H

	x, y := 0, 0
	for c in template {
		if c == '\n' {
			x = 0
			y += 1
			continue
		}
		tx, ty := ox + x, oy + y
		// Unused cells were pre-filled with rock, so anything a template does
		// not explicitly make solid has to be hollowed out again.
		tile_set(m, tx, ty, .Empty)
		switch c {
		case '#':
			tile_set(m, tx, ty, .Rock)
		case 'X':
			tile_set(m, tx, ty, .Deep)
		case '%':
			tile_set(m, tx, ty, .Moss)
		case '=':
			tile_set(m, tx, ty, .Platform)
		case '~':
			tile_set(m, tx, ty, .Water)
		case 'E':
			append(&s.enemies, [2]int{tx, ty})
		case 'C':
			append(&s.chests, [2]int{tx, ty})
		case 'o':
			append(&s.coins, [2]int{tx, ty})
		case 'r':
			append(&s.runes, [2]int{tx, ty})
		case 'S':
			s.player = {tx, ty}
		case 'K':
			s.key = {tx, ty}
			s.has_key = true
		case 'B':
			s.boss = {tx, ty}
			s.has_boss = true
		}
		x += 1
	}
	return s
}

@(private = "file")
carve_doors :: proc(w: ^World, m: ^Tilemap, cell: [2]int) {
	room := w.rooms[cell.y][cell.x]
	ox, oy := cell.x * ROOM_W, cell.y * ROOM_H

	// Only the two directions that own the shared wall are carved; the
	// neighbour carves its own side when its turn comes.
	if .East in room.doors {
		for i in 0 ..< DOOR_H {
			tile_set(m, ox + ROOM_W - 1, oy + DOOR_Y + i, .Empty)
			tile_set(m, ox + ROOM_W, oy + DOOR_Y + i, .Empty)
		}
	}
	if .West in room.doors {
		for i in 0 ..< DOOR_H {
			tile_set(m, ox, oy + DOOR_Y + i, .Empty)
			tile_set(m, ox - 1, oy + DOOR_Y + i, .Empty)
		}
	}
	if .South in room.doors {
		for i in 0 ..< DOOR_W {
			tile_set(m, ox + DOOR_X + i, oy + ROOM_H - 2, .Empty)
			tile_set(m, ox + DOOR_X + i, oy + ROOM_H - 1, .Empty)
			tile_set(m, ox + DOOR_X + i, oy + ROOM_H, .Empty)
		}
	}
	if .North in room.doors {
		for i in 0 ..< DOOR_W {
			tile_set(m, ox + DOOR_X + i, oy, .Empty)
			tile_set(m, ox + DOOR_X + i, oy - 1, .Empty)
		}
	}
}

// Seals every entrance of the boss room. The tiles are remembered so taking the
// key can clear them all at once.
@(private = "file")
seal_boss_room :: proc(w: ^World, m: ^Tilemap) {
	cell := w.boss
	room := w.rooms[cell.y][cell.x]
	ox, oy := cell.x * ROOM_W, cell.y * ROOM_H

	add :: proc(w: ^World, m: ^Tilemap, x, y: int) {
		tile_set(m, x, y, .Gate)
		append(&w.gates, [2]int{x, y})
	}

	if .East in room.doors {
		for i in 0 ..< DOOR_H {add(w, m, ox + ROOM_W - 1, oy + DOOR_Y + i)}
	}
	if .West in room.doors {
		for i in 0 ..< DOOR_H {add(w, m, ox, oy + DOOR_Y + i)}
	}
	if .South in room.doors {
		for i in 0 ..< DOOR_W {add(w, m, ox + DOOR_X + i, oy + ROOM_H - 1)}
	}
	if .North in room.doors {
		for i in 0 ..< DOOR_W {add(w, m, ox + DOOR_X + i, oy)}
	}
}

world_unlock_gates :: proc(w: ^World, m: ^Tilemap) {
	for gate in w.gates {
		tile_set(m, gate.x, gate.y, .Empty)
	}
	clear(&w.gates)
}

// Walks down from a tile looking for something to stand on. Returns the world
// position of the ground, or false if the drop is too long to be a floor.
@(private = "file")
ground_below :: proc(m: ^Tilemap, tile: [2]int, reach := 8) -> (rl.Vector2, bool) {
	for i in 0 ..< reach {
		y := tile.y + i
		below := tile_at(m, tile.x, y + 1)
		if is_blocking(below) || below == .Platform {
			if is_blocking(tile_at(m, tile.x, y)) {
				return {}, false
			}
			return {f32(tile.x) * TILE + TILE / 2, f32(y) * TILE + TILE}, true
		}
	}
	return {}, false
}

@(private = "file")
tile_centre :: proc(tile: [2]int) -> rl.Vector2 {
	return {f32(tile.x) * TILE + TILE / 2, f32(tile.y) * TILE + TILE / 2}
}

// Enemies unlock as the run goes deeper, so the first rooms are never a wall of
// flyers and armoured crabs.
@(private = "file")
roll_enemy_kind :: proc(depth: int) -> Enemy_Kind {
	pool := make([dynamic]Enemy_Kind, context.temp_allocator)
	append(&pool, Enemy_Kind.Rat, Enemy_Kind.Rat, Enemy_Kind.Slime)
	if depth >= 1 {
		append(&pool, Enemy_Kind.Bat, Enemy_Kind.Slime)
	}
	if depth >= 2 {
		append(&pool, Enemy_Kind.Crab, Enemy_Kind.Skull)
	}
	if depth >= 3 {
		append(&pool, Enemy_Kind.Pebble, Enemy_Kind.Crab)
	}
	return rand.choice(pool[:])
}

@(private = "file")
populate_room :: proc(g: ^Game, cell: [2]int, s: ^Spawns) {
	room := &g.world.rooms[cell.y][cell.x]

	if s.has_boss {
		append(&g.enemies, enemy_make(.Golem, tile_centre(s.boss) + {0, TILE / 2}))
	}
	if s.has_key {
		append(&g.pickups, pickup_make(.Key, tile_centre(s.key)))
	}

	enemy_budget := 0
	#partial switch room.role {
	case .Normal, .Key:
		enemy_budget = 2 + room.depth / 2 + rand.int_max(2)
	case .Treasure:
		enemy_budget = rand.int_max(2)
	}

	rand.shuffle(s.enemies[:])
	for tile in s.enemies {
		if enemy_budget <= 0 {
			break
		}
		enemy_budget -= 1
		kind := roll_enemy_kind(room.depth)
		if enemy_flies(kind) {
			append(&g.enemies, enemy_make(kind, tile_centre(tile)))
			continue
		}
		// A walker with no floor under its marker would fall out of the room, so
		// it becomes a flyer instead of being dropped.
		if pos, ok := ground_below(&g.map_tiles, tile); ok {
			append(&g.enemies, enemy_make(kind, pos))
		} else {
			append(&g.enemies, enemy_make(.Bat, tile_centre(tile)))
		}
	}

	chest_budget := 0
	#partial switch room.role {
	case .Treasure:
		chest_budget = len(s.chests)
	case .Normal, .Key:
		chest_budget = rand.float32() < 0.45 ? 1 : 0
	}
	rand.shuffle(s.chests[:])
	for tile in s.chests {
		if chest_budget <= 0 {
			break
		}
		if pos, ok := ground_below(&g.map_tiles, tile); ok {
			append(&g.chests, chest_make(pos))
			chest_budget -= 1
		}
	}

	for tile in s.coins {
		if rand.float32() < 0.7 {
			append(&g.pickups, pickup_make(.Coin, tile_centre(tile)))
			g.coins_total += 1
		}
	}
	for tile in s.runes {
		append(&g.pickups, pickup_make(.Rune, tile_centre(tile)))
	}
}

// Builds a whole run: layout, terrain, doors, and everything that lives in it.
world_generate :: proc(g: ^Game) {
	g.world = {}
	g.world.gates = make([dynamic][2]int)
	g.map_tiles = tilemap_make(GRID_W * ROOM_W, GRID_H * ROOM_H)

	clear(&g.enemies)
	clear(&g.pickups)
	clear(&g.chests)
	clear(&g.bullets)
	clear(&g.sparks)
	g.coins_total = 0

	grow_layout(&g.world)
	measure_depths(&g.world)
	assign_roles(&g.world)

	// Unvisited cells are solid rock, so the world has weight around its edges.
	for i in 0 ..< len(g.map_tiles.tiles) {
		g.map_tiles.tiles[i] = .Deep
	}

	spawns: [GRID_H][GRID_W]Spawns
	for y in 0 ..< GRID_H {
		for x in 0 ..< GRID_W {
			if g.world.rooms[y][x].role == .Unused {
				continue
			}
			spawns[y][x] = stamp_room(&g.map_tiles, {x, y}, template_for(g.world.rooms[y][x].role))
		}
	}
	for y in 0 ..< GRID_H {
		for x in 0 ..< GRID_W {
			if g.world.rooms[y][x].role != .Unused {
				carve_doors(&g.world, &g.map_tiles, {x, y})
			}
		}
	}
	seal_boss_room(&g.world, &g.map_tiles)

	for y in 0 ..< GRID_H {
		for x in 0 ..< GRID_W {
			if g.world.rooms[y][x].role == .Unused {
				continue
			}
			populate_room(g, {x, y}, &spawns[y][x])
		}
	}

	start := spawns[g.world.start.y][g.world.start.x]
	player_init(&g.player, tile_centre(start.player) + {0, TILE / 2})
	g.world.rooms[g.world.start.y][g.world.start.x].seen = true
	// Off to one side, so the banner is a landmark rather than something the
	// player is permanently standing inside.
	g.flag_pos = g.player.pos + {-28, 0}
}
