package game

import "core:math"
import rl "../libs/raylib"

/*
Rooms. A level can be cut into rooms, each a `Room` rectangle drawn in LDtk,
about a screen in size. Then:

  the camera stays inside the room you are in, and slides across to the next
  when you walk, fall or climb out of one into another, the world holding
  still while it does;

  you come back to life in the room you died in, at whichever of its `Spawn`
  points is nearest to where you came in, with everything in the level put
  back as it was;

  falling out of the bottom of a room with no room under it is a death.

Each room is one idea and one thing to get past, and dying costs you only
that. A level with no rooms drawn is one big room, as levels used to be.
*/

ROOM_SLIDE :: 0.4 // seconds the camera takes to cross to the next room
ROOM_FALL_MARGIN :: 24.0

// Which room a point is in, or -1.
room_at :: proc(g: ^Game, p: rl.Vector2) -> int {
	for r, i in g.level.rooms {
		if p.x >= r.x && p.x < r.x + r.width && p.y >= r.y && p.y < r.y + r.height {
			return i
		}
	}
	return -1
}

// What the camera may show: the room, or the whole level if there are none.
room_bounds :: proc(g: ^Game) -> rl.Rectangle {
	if g.level.room >= 0 && g.level.room < len(g.level.rooms) {
		return g.level.rooms[g.level.room]
	}
	size := tilemap_bounds(&g.map_tiles)
	return {0, 0, size.x, size.y}
}

// The room's spawn point nearest to `near`.
room_spawn :: proc(g: ^Game, room: int, near: rl.Vector2) -> (best: rl.Vector2, ok: bool) {
	r := g.level.rooms[room]
	closest := f32(1e9)
	for s in g.level.spawns {
		// A spawn's feet rest on the floor, which may be the room's last row.
		if !rl.CheckCollisionPointRec(s - {0, 1}, r) {
			continue
		}
		if d := rl.Vector2Distance(s, near); d < closest {
			closest = d
			best = s
			ok = true
		}
	}
	return
}

// Called when a level starts or restarts.
rooms_reset :: proc(g: ^Game) {
	g.level.room = room_at(g, g.level.spawn - {0, PLAYER_H / 2})
	g.room_slide = 0
}

rooms_update :: proc(g: ^Game) {
	l := &g.level
	p := &g.player
	if len(l.rooms) == 0 || p.dead {
		return
	}
	c := player_centre(p^)
	at := room_at(g, c)
	if at == l.room {
		return
	}
	if at < 0 {
		// Out of every room: only a death if it is out of the bottom.
		if l.room >= 0 {
			r := l.rooms[l.room]
			if c.y > r.y + r.height + ROOM_FALL_MARGIN {
				player_kill(g)
			}
		}
		return
	}

	from := l.room
	l.room = at
	g.room_slide = 1
	g.room_from = g.camera.target
	g.deaths_here = 0
	if s, ok := room_spawn(g, at, p.pos); ok {
		g.respawn = s
	}
	player_refill_dash(p)
	light_sync(g)
	// Climbing out of the top of a room, you are carried far enough to land
	// in the one above.
	if from >= 0 && l.rooms[at].y < l.rooms[from].y && p.vel.y < 0 {
		p.vel.y = min(p.vel.y, -JUMP_VELOCITY)
	}
	play(&g.assets, .Room)
}

// Everything outside the room you are in falls into shade, so the room is
// the picture even on a screen wider than it.
rooms_draw_shade :: proc(g: ^Game, view: rl.Rectangle) {
	if len(g.level.rooms) == 0 || g.level.room < 0 {
		return
	}
	r := g.level.rooms[g.level.room]
	k := 1 - g.room_slide
	c := rl.Color{14, 10, 26, u8(150 * k * k)}
	big: f32 = 4000
	rl.DrawRectangleRec({r.x - big, view.y - 8, big, view.height + 16}, c)
	rl.DrawRectangleRec({r.x + r.width, view.y - 8, big, view.height + 16}, c)
	rl.DrawRectangleRec({r.x, r.y - big, r.width, big}, c)
	rl.DrawRectangleRec({r.x, r.y + r.height, r.width, big}, c)
}

// A row of pips along the top of the screen: one per room, the one you are
// in lit.
rooms_draw_pips :: proc(g: ^Game) {
	n := len(g.level.rooms)
	if n < 2 || g.level_intro > 0.3 {
		return
	}
	view := view_size()
	gap: f32 = 7
	x := math.round(view.x / 2 - f32(n - 1) * gap / 2)
	for i in 0 ..< n {
		px := x + f32(i) * gap
		fill_rect(px - 2, 5, 5, 5, {20, 14, 30, 170})
		colour := rl.Color{130, 124, 150, 255}
		if i < g.level.room {
			colour = {255, 206, 92, 255}
		} else if i == g.level.room {
			colour = {255, 250, 224, 255}
		}
		fill_rect(px - 1, 6, 3, 3, colour)
	}
}
