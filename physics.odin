package game

import "core:math"
import rl "vendor:raylib"

// Axis-separated AABB-vs-tilemap movement. Callers move one axis at a time,
// which keeps corner cases (sliding along a wall while falling) simple.

@(private = "file")
tile_span :: proc(lo, size: f32) -> (int, int) {
	return int(math.floor(lo / TILE)), int(math.floor((lo + size - 0.01) / TILE))
}

// Moves `r` horizontally and snaps it out of the first blocking tile in the way.
// One-way platforms never block sideways movement.
move_x :: proc(m: ^Tilemap, r: rl.Rectangle, dx: f32) -> (out: rl.Rectangle, hit: bool) {
	out = r
	out.x += dx
	if dx == 0 {
		return
	}

	y0, y1 := tile_span(out.y, out.height)
	x0, x1 := tile_span(out.x, out.width)

	check :: proc(m: ^Tilemap, tx, y0, y1: int) -> bool {
		for ty in y0 ..= y1 {
			if is_blocking(tile_at(m, tx, ty)) {
				return true
			}
		}
		return false
	}

	if dx > 0 {
		for tx in x0 ..= x1 {
			if check(m, tx, y0, y1) {
				out.x = f32(tx) * TILE - out.width
				return out, true
			}
		}
	} else {
		for tx := x1; tx >= x0; tx -= 1 {
			if check(m, tx, y0, y1) {
				out.x = f32(tx + 1) * TILE
				return out, true
			}
		}
	}
	return
}

// Moves `r` vertically. While falling, one-way platforms act as ground, but only
// if the rectangle's feet were already at or above the platform surface — that
// is what lets the player jump up through them. `drop_through` disables them
// entirely so the player can deliberately fall off.
move_y :: proc(
	m: ^Tilemap,
	r: rl.Rectangle,
	dy: f32,
	drop_through := false,
) -> (
	out: rl.Rectangle,
	grounded: bool,
	bumped_head: bool,
) {
	out = r
	out.y += dy
	if dy == 0 {
		return
	}

	x0, x1 := tile_span(out.x, out.width)
	y0, y1 := tile_span(out.y, out.height)

	if dy > 0 {
		feet_before := r.y + r.height
		for ty in y0 ..= y1 {
			for tx in x0 ..= x1 {
				t := tile_at(m, tx, ty)
				solid := is_blocking(t)
				if !solid && t == .Platform && !drop_through {
					solid = feet_before <= f32(ty) * TILE + 1
				}
				if solid {
					out.y = f32(ty) * TILE - out.height
					return out, true, false
				}
			}
		}
	} else {
		for ty := y1; ty >= y0; ty -= 1 {
			for tx in x0 ..= x1 {
				if is_blocking(tile_at(m, tx, ty)) {
					out.y = f32(ty + 1) * TILE
					return out, false, true
				}
			}
		}
	}
	return
}

// Is there ground directly beneath the rectangle? Used for coyote time and for
// keeping enemies from walking off ledges.
on_ground :: proc(m: ^Tilemap, r: rl.Rectangle) -> bool {
	_, grounded, _ := move_y(m, r, 1)
	return grounded
}

// Which side has a wall against it: -1 for left, +1 for right, 0 for neither.
// The probe is inset vertically so that standing in a corner, or brushing a
// ceiling, does not read as a climbable wall.
wall_side :: proc(m: ^Tilemap, r: rl.Rectangle) -> f32 {
	probe := rl.Rectangle{r.x - 2, r.y + 4, 2, r.height - 8}
	if tilemap_overlaps_solid(m, probe) {
		return -1
	}
	probe.x = r.x + r.width
	if tilemap_overlaps_solid(m, probe) {
		return 1
	}
	return 0
}
