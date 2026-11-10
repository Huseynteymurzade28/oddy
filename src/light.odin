package game

import "core:math"
import rl "../libs/raylib"

/*
Lumi's light, and what it does to the world.

Her light is her dash: gold while the dash is ready, spent and pale once it
is used, back when her feet find the ground. Two kinds of block take their
cue from it:

  light blocks   solid while the light burns, open air while it is spent
  shadow blocks  the other way round: only there in the dark

So a dash is also a switch. It opens the bright wall in front of you and
takes away the bright floor behind; it makes the dark ledge you are about to
need. And anything that hands the dash back in mid-air (a refill, a
trampoline, a creature's head) throws the switch the other way while you are
still flying.

Two rules keep it fair:

  Shadow gives no light. Standing on a shadow block does not bring the dash
  back, or it would vanish from under you the moment you landed.

  Nothing closes on you. A block that ought to turn solid while you are
  inside it waits until you have left.
*/

Light_Kind :: enum u8 {
	Lit,
	Dark,
}

LIGHT_PULSE :: 0.18 // the flash as a kind of block turns solid

// Which of the two are solid now. Global rather than passed around: every
// collision query in the game asks `is_blocking`, and this is its one extra
// piece of state.
light_solid := [Light_Kind]bool {
	.Lit  = true,
	.Dark = false,
}
light_pulse: [Light_Kind]f32

light_reset :: proc() {
	light_solid = {
		.Lit  = true,
		.Dark = false,
	}
	light_pulse = {}
}

@(private = "file")
tile_of := [Light_Kind]Tile {
	.Lit  = .Lit,
	.Dark = .Dark,
}

@(private = "file")
overlaps_kind :: proc(m: ^Tilemap, r: rl.Rectangle, tile: Tile) -> bool {
	x0, y0 := int(math.floor(r.x / TILE)), int(math.floor(r.y / TILE))
	x1, y1 := int(math.floor((r.x + r.width - 0.01) / TILE)), int(math.floor((r.y + r.height - 0.01) / TILE))
	for ty in y0 ..= y1 {
		for tx in x0 ..= x1 {
			if tile_at(m, tx, ty) == tile {
				return true
			}
		}
	}
	return false
}

// Brings the blocks into step with the light. Called whenever the dash may
// have been spent or come back.
light_sync :: proc(g: ^Game) {
	if !g.level.has_light {
		return
	}
	p := &g.player
	burning := p.dashes > 0 || p.dead
	want := [Light_Kind]bool {
		.Lit  = burning,
		.Dark = !burning,
	}
	changed := false
	for kind in Light_Kind {
		if want[kind] == light_solid[kind] {
			continue
		}
		if want[kind] && !p.dead && overlaps_kind(&g.map_tiles, player_rect(p^), tile_of[kind]) {
			continue // not while she is inside one
		}
		light_solid[kind] = want[kind]
		changed = true
		if want[kind] {
			light_pulse[kind] = LIGHT_PULSE
		}
	}
	if changed && !p.dead {
		play(&g.assets, burning ? .Light_On : .Light_Off)
		game_flash(g, burning ? rl.Color{255, 220, 140, 44} : rl.Color{96, 76, 210, 56})
	}
}

// Is the only thing under these feet shadow? Then the dash stays spent.
standing_on_shadow :: proc(m: ^Tilemap, r: rl.Rectangle) -> bool {
	ty := int(math.floor((r.y + r.height + 0.5) / TILE))
	x0 := int(math.floor(r.x / TILE))
	x1 := int(math.floor((r.x + r.width - 0.01) / TILE))
	shadow := false
	for tx in x0 ..= x1 {
		t := tile_at(m, tx, ty)
		if t == .Dark {
			shadow = true
		} else if is_blocking(t) || t == .Platform {
			return false
		}
	}
	return shadow
}

// The blocks themselves, drawn in code: glass full of daylight, and slabs
// of night with stars in them. An open one is only its outline, creeping.
light_blocks_draw :: proc(g: ^Game, x0, y0, x1, y1: int) {
	if !g.level.has_light {
		return
	}
	m := &g.map_tiles
	dt := rl.GetFrameTime()
	for kind in Light_Kind {
		light_pulse[kind] = max(0, light_pulse[kind] - dt)
	}
	for y in y0 ..= y1 {
		for x in x0 ..= x1 {
			t := tile_at(m, x, y)
			if t != .Lit && t != .Dark {
				continue
			}
			kind: Light_Kind = t == .Lit ? .Lit : .Dark
			px, py := f32(x) * TILE, f32(y) * TILE
			up := tile_at(m, x, y - 1) == t
			down := tile_at(m, x, y + 1) == t
			left := tile_at(m, x - 1, y) == t
			right := tile_at(m, x + 1, y) == t

			if !light_solid[kind] {
				c: rl.Color = kind == .Lit ? {255, 220, 130, 255} : {168, 140, 255, 255}
				fill := c
				fill.a = 44
				rl.DrawRectangleV({px, py}, {TILE, TILE}, fill)
				// A dashed line round the outside of the group, crawling.
				c.a = 235
				crawl := int(g.time * 10)
				for k in 0 ..< TILE / 2 {
					if (k + crawl + x * 8 + y * 8) % 4 >= 2 {
						continue
					}
					o := f32(k) * 2
					if !up {rl.DrawRectangleV({px + o, py}, {2, 1}, c)}
					if !down {rl.DrawRectangleV({px + o, py + TILE - 1}, {2, 1}, c)}
					if !left {rl.DrawRectangleV({px, py + o}, {1, 2}, c)}
					if !right {rl.DrawRectangleV({px + TILE - 1, py + o}, {1, 2}, c)}
				}
				continue
			}

			body, edge, shine: rl.Color
			if kind == .Lit {
				body, edge, shine = {255, 204, 96, 255}, {160, 96, 40, 255}, {255, 246, 204, 255}
			} else {
				body, edge, shine = {58, 44, 116, 255}, {24, 16, 56, 255}, {136, 112, 220, 255}
			}
			rl.DrawRectangleV({px, py}, {TILE, TILE}, body)
			if kind == .Lit {
				// Brighter toward the middle, and a slow glint going over.
				rl.DrawRectangleV({px + 3, py + 3}, {TILE - 6, TILE - 6}, {255, 226, 140, 255})
				glint := math.mod(g.time * 26 + f32(x - y) * 6, 90)
				if glint < TILE - 2 {
					rl.DrawRectangleV({px + glint, py + 2}, {2, TILE - 4}, {255, 250, 224, 200})
				}
			} else {
				// Stars, each at its own slow twinkle.
				for k in 0 ..< 3 {
					h := (x * 73856093) ~ (y * 19349663) ~ (k * 83492791)
					h = abs(h ~ (h >> 13))
					sx := f32(2 + h % 12)
					sy := f32(2 + (h / 13) % 12)
					a := 0.5 + 0.5 * math.sin(g.time * (1.5 + f32(k)) + f32(h % 7))
					rl.DrawRectangleV({px + sx, py + sy}, {1, 1}, {214, 204, 255, u8(70 + 185 * a)})
				}
			}
			if !up {
				rl.DrawRectangleV({px, py}, {TILE, 1}, edge)
				rl.DrawRectangleV({px + 1, py + 1}, {TILE - 2, 1}, shine)
			}
			if !down {rl.DrawRectangleV({px, py + TILE - 1}, {TILE, 1}, edge)}
			if !left {rl.DrawRectangleV({px, py}, {1, TILE}, edge)}
			if !right {rl.DrawRectangleV({px + TILE - 1, py}, {1, TILE}, edge)}
			if light_pulse[kind] > 0 {
				rl.DrawRectangleV({px, py}, {TILE, TILE}, {255, 255, 255, u8(200 * light_pulse[kind] / LIGHT_PULSE)})
			}
		}
	}
}
