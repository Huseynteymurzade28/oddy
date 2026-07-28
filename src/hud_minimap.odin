package game

import "core:math"
import rl "vendor:raylib"

/*
The map panel in the top-right corner.

It is the only way to read the shape of a run, so it draws four things rather
than one: which rooms exist, how they join up, what is in the ones you have
already walked through, and where in the current room you are standing. Rooms
you have not reached yet are shown as bare outlines when they touch somewhere
you have been, so the map always has an edge to push against.

Cells are 16x9 — the same 16:9 as a real room — so the shape of the map on
screen matches the shape of the world behind it.
*/

@(private = "file")
CELL_W :: 18.0
@(private = "file")
CELL_H :: 10.0
@(private = "file")
GAP :: 5.0 // the corridors between rooms are drawn in here
@(private = "file")
PAD :: 4.0
@(private = "file")
HEADER :: 11.0

@(private = "file")
GRID_PX_W :: GRID_W * (CELL_W + GAP) - GAP
@(private = "file")
GRID_PX_H :: GRID_H * (CELL_H + GAP) - GAP

@(private = "file")
INK :: rl.Color{16, 14, 22, 235} // icons, drawn dark on the room colour

@(private = "file")
ROLE_COLORS := [Room_Role]rl.Color {
	.Unused   = {0, 0, 0, 0},
	.Normal   = {96, 108, 138, 235},
	.Start    = {110, 190, 130, 235},
	.Treasure = {236, 200, 110, 235},
	.Key      = {240, 168, 92, 235},
	.Boss     = {214, 84, 84, 235},
}

draw_minimap :: proc(g: ^Game) {
	a := &g.assets
	view := view_size()

	panel_w: f32 = GRID_PX_W + PAD * 2
	panel_h: f32 = GRID_PX_H + PAD * 2 + HEADER
	px := view.x - panel_w - 5
	py: f32 = 5
	gx := px + PAD
	gy := py + PAD + HEADER

	fill_rect(px, py, panel_w, panel_h, {12, 10, 18, 195})
	outline_rect(px, py, panel_w, panel_h, {72, 80, 106, 220})
	draw_text(a, "HOLLOW", {px + PAD, py + 3}, 8, {150, 162, 190, 255})
	draw_text_right(
		a,
		rl.TextFormat("%d/%d", rooms_seen(&g.world), ROOMS_PER_RUN),
		px + panel_w - PAD,
		py + 3,
		8,
		{100, 110, 136, 255},
	)
	fill_rect(px + PAD, py + HEADER, GRID_PX_W, 1, {48, 52, 72, 220})

	// Corridors first, so the rooms sit on top of their own connections.
	for y in 0 ..< GRID_H {
		for x in 0 ..< GRID_W {
			draw_doors(g, gx, gy, x, y)
		}
	}
	for y in 0 ..< GRID_H {
		for x in 0 ..< GRID_W {
			draw_room(g, gx, gy, x, y)
		}
	}
	draw_player_dot(g, gx, gy)

	// What to do next, hanging off the bottom edge of the panel.
	draw_text_right(
		a,
		objective_text(g),
		px + panel_w,
		py + panel_h + 4,
		8,
		g.player.has_key ? rl.Color{240, 168, 92, 255} : rl.Color{255, 214, 110, 255},
	)
}

@(private = "file")
cell_pos :: proc(gx, gy: f32, x, y: int) -> (f32, f32) {
	return gx + f32(x) * (CELL_W + GAP), gy + f32(y) * (CELL_H + GAP)
}

// A room is only worth hinting at if the player could plausibly walk to it next.
@(private = "file")
is_known :: proc(g: ^Game, x, y: int) -> bool {
	room := room_at(&g.world, x, y)
	if room == nil || room.role == .Unused {
		return false
	}
	return room.seen || room_neighbour_seen(&g.world, x, y)
}

@(private = "file")
draw_doors :: proc(g: ^Game, gx, gy: f32, x, y: int) {
	room := room_at(&g.world, x, y)
	if room == nil || !is_known(g, x, y) {
		return
	}
	cx, cy := cell_pos(gx, gy, x, y)

	// Only the two directions that own the gap are drawn; the neighbour draws
	// its own side of the grid.
	for dir in ([?]Dir{.East, .South}) {
		if dir not_in room.doors {
			continue
		}
		step := DIR_STEP[dir]
		if !is_known(g, x + step.x, y + step.y) {
			continue
		}
		other := room_at(&g.world, x + step.x, y + step.y)
		both := room.seen && other != nil && other.seen
		colour := both ? rl.Color{120, 132, 164, 235} : rl.Color{54, 58, 78, 220}

		if dir == .East {
			fill_rect(cx + CELL_W, cy + CELL_H / 2 - 1.5, GAP, 3, colour)
		} else {
			fill_rect(cx + CELL_W / 2 - 1.5, cy + CELL_H, 3, GAP, colour)
		}
	}
}

@(private = "file")
draw_room :: proc(g: ^Game, gx, gy: f32, x, y: int) {
	room := room_at(&g.world, x, y)
	if room == nil || room.role == .Unused {
		return
	}
	cx, cy := cell_pos(gx, gy, x, y)

	if !room.seen {
		if room_neighbour_seen(&g.world, x, y) {
			// Somewhere to go: an empty outline, no hint of what is inside.
			fill_rect(cx, cy, CELL_W, CELL_H, {26, 26, 38, 200})
			outline_rect(cx, cy, CELL_W, CELL_H, {58, 62, 84, 220})
		}
		return
	}

	colour := ROLE_COLORS[room.role]
	// The sealed vault throbs until the key opens it, then burns steady.
	if room.role == .Boss {
		pulse := (math.sin(g.time * 4) * 0.5 + 0.5) * (g.player.has_key ? 0.15 : 0.45)
		colour.r = u8(clamp(f32(colour.r) * (1 - pulse) + 255 * pulse, 0, 255))
		colour.g = u8(f32(colour.g) * (1 - pulse * 0.6))
		colour.b = u8(f32(colour.b) * (1 - pulse * 0.6))
	}

	fill_rect(cx, cy, CELL_W, CELL_H, colour)
	outline_rect(cx, cy, CELL_W, CELL_H, {18, 16, 26, 200})
	// A darker floor line, so a room reads as a side-on space rather than a box.
	fill_rect(cx, cy + CELL_H - 1, CELL_W, 1, {18, 16, 26, 120})

	if x == g.room.x && y == g.room.y {
		outline_rect(cx, cy, CELL_W, CELL_H, {255, 255, 255, 200})
	}
	draw_room_icon(room.role, cx + CELL_W / 2, cy + CELL_H / 2, g.player.has_key)
}

// Five-pixel glyphs, drawn dark on the room's own colour.
@(private = "file")
draw_room_icon :: proc(role: Room_Role, cx, cy: f32, has_key: bool) {
	switch role {
	case .Start:
		// A flag on a pole: where the run began.
		fill_rect(cx - 2, cy - 3, 1, 6, INK)
		fill_rect(cx - 1, cy - 3, 4, 3, INK)
	case .Treasure:
		// A chest: a lid line over a body.
		fill_rect(cx - 3, cy - 2, 6, 2, INK)
		fill_rect(cx - 3, cy, 6, 3, INK)
		fill_rect(cx - 1, cy, 2, 1, ROLE_COLORS[.Treasure])
	case .Key:
		// A key: ring and shaft.
		fill_rect(cx - 3, cy - 2, 3, 3, INK)
		fill_rect(cx - 2, cy - 1, 1, 1, ROLE_COLORS[.Key])
		fill_rect(cx, cy - 1, 4, 1, INK)
		fill_rect(cx + 2, cy, 2, 1, INK)
	case .Boss:
		// A skull: brow, eyes, jaw. Locked rooms get a bar across them.
		fill_rect(cx - 2, cy - 3, 5, 4, INK)
		fill_rect(cx - 1, cy + 1, 3, 2, INK)
		fill_rect(cx - 1, cy - 2, 1, 2, ROLE_COLORS[.Boss])
		fill_rect(cx + 1, cy - 2, 1, 2, ROLE_COLORS[.Boss])
		if !has_key {
			fill_rect(cx - 5, cy - 1, 11, 1, {255, 235, 190, 220})
		}
	case .Normal, .Unused:
	}
}

// Where the player is standing, placed by their fraction across the real room so
// the dot slides toward a doorway before the map flips to the next cell.
@(private = "file")
draw_player_dot :: proc(g: ^Game, gx, gy: f32) {
	room := room_at(&g.world, g.room.x, g.room.y)
	if room == nil || room.role == .Unused {
		return
	}
	bounds := room_rect(g.room)
	fx := clamp((g.player.pos.x - bounds.x) / bounds.width, 0, 1)
	fy := clamp((g.player.pos.y - bounds.y) / bounds.height, 0, 1)

	cx, cy := cell_pos(gx, gy, g.room.x, g.room.y)
	px := cx + 1 + fx * (CELL_W - 3)
	py := cy + 1 + fy * (CELL_H - 3)

	fill_rect(px - 1, py - 1, 4, 4, {18, 16, 26, 220})
	blink := u8(200 + math.sin(g.time * 6) * 55)
	fill_rect(px, py, 2, 2, {255, 255, 255, blink})
}
