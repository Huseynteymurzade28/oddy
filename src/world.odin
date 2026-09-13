package game

import rl "vendor:raylib"

/*
The shape of a run: a grid of rooms, which of them are connected, and what each
one is for. This file is only the data and the queries — `world_gen.odin` fills
it in, and `hud_minimap.odin` draws it.
*/

GRID_W :: 5
GRID_H :: 4

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
	Shop,
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

rooms_seen :: proc(w: ^World) -> int {
	count := 0
	for y in 0 ..< GRID_H {
		for x in 0 ..< GRID_W {
			if w.rooms[y][x].seen {
				count += 1
			}
		}
	}
	return count
}

// Does this cell border somewhere the player has been? Rooms that do are hinted
// at on the map instead of being hidden outright.
room_neighbour_seen :: proc(w: ^World, x, y: int) -> bool {
	for dir in Dir {
		step := DIR_STEP[dir]
		if room := room_at(w, x + step.x, y + step.y); room != nil && room.seen {
			return true
		}
	}
	return false
}
