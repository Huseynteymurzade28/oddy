package game

import "core:math"
import "core:math/rand"
import rl "../libs/raylib"

/*
The things the art pack does not have, drawn in code: torches on the walls,
roots and stalactites hanging from ceilings, crystals and mushrooms on floors,
and the motes that drift through the air. None of it collides. Most of it
glows, which is what the lighting pass is for: the light map reads `g.decor`
for its torches and crystals.

What grows where is the zone's business (see `zone.odin`): roots and
mushrooms up in the moss, stalactites and crystals in the flooded middle and
the deep, torches everywhere someone used to work.
*/

Decor_Kind :: enum u8 {
	Torch,
	Root,
	Stalactite,
	Crystal,
	Mushroom,
}

Decor :: struct {
	kind:   Decor_Kind,
	pos:    rl.Vector2, // flame, tip of the anchor, or base on the floor
	length: f32, // roots and stalactites
	side:   f32, // torches: which way the bracket comes off the wall
	phase:  f32,
	tint:   rl.Color,
	light:  rl.Color,
	radius: f32, // of its light, 0 for none
}

Mote_Kind :: enum u8 {
	Firefly,
	Dust,
	Drip,
	Ember,
	Butterfly, // drawn from the critters sheet, not as a glowing dot
	Bubble,
}

Mote :: struct {
	kind:     Mote_Kind,
	pos:      rl.Vector2,
	vel:      rl.Vector2,
	life:     f32,
	max_life: f32,
	size:     f32,
	tint:     rl.Color,
	glow:     bool,
	phase:    f32,
}

MAX_MOTES :: 140

// ------------------------------------------------------------------ placing ---

@(private = "file")
solid :: proc(m: ^Tilemap, x, y: int) -> bool {
	t := tile_at(m, x, y)
	return t == .Rock || t == .Deep || t == .Moss
}

@(private = "file")
open :: proc(m: ^Tilemap, x, y: int) -> bool {
	return tile_at(m, x, y) == .Empty
}

// Rolls the decorations for the whole level, after its tiles are final. The
// roll is seeded from the level's size, so the same level always grows the
// same moss.
decor_scatter :: proc(g: ^Game) {
	clear(&g.decor)
	clear(&g.liquid_glows)
	m := &g.map_tiles
	zone := g.level.zone
	look := ZONE_LOOKS[zone]

	state := rand.create(u64(m.width * 7919 + m.height))
	context.random_generator = rand.default_random_generator(&state)

	torches := make([dynamic]rl.Vector2, context.temp_allocator)
	for ty in 1 ..< m.height - 1 {
		for tx in 1 ..< m.width - 1 {
			if !open(m, tx, ty) {
				continue
			}
			px := f32(tx) * TILE
			py := f32(ty) * TILE

			// Lava gives off light along its surface.
			if zone == .Ember && tile_at(m, tx, ty + 1) == .Water && tx % 3 == 0 {
				append(&g.liquid_glows, rl.Vector2{px + TILE / 2, py + TILE})
			}

			// Hanging from a ceiling.
			if solid(m, tx, ty - 1) && open(m, tx, ty + 1) {
				switch zone {
				case .Mossy:
					if rand.float32() < 0.22 {
						append(&g.decor, Decor {
							kind   = .Root,
							pos    = {px + rand.float32_range(3, 13), py},
							length = rand.float32_range(8, 34),
							phase  = rand.float32_range(0, math.TAU),
							tint   = {64, 92, 54, 255},
						})
					}
				case .Drowned, .Ember:
					if rand.float32() < 0.2 {
						tint := mul_color({120, 112, 128, 255}, look.rock)
						append(&g.decor, Decor {
							kind   = .Stalactite,
							pos    = {px + rand.float32_range(4, 12), py},
							length = rand.float32_range(6, 18),
							phase  = rand.float32_range(0, math.TAU),
							tint   = tint,
						})
					}
				}
			}

			// Standing on a floor.
			if solid(m, tx, ty + 1) {
				switch zone {
				case .Mossy:
					if rand.float32() < 0.05 {
						append(&g.decor, Decor {
							kind   = .Mushroom,
							pos    = {px + rand.float32_range(3, 13), py + TILE},
							phase  = rand.float32_range(0, math.TAU),
							tint   = {120, 240, 220, 255},
							light  = {60, 130, 120, 255},
							radius = 22,
						})
					}
				case .Drowned, .Ember:
					if rand.float32() < 0.06 {
						append(&g.decor, Decor {
							kind   = .Crystal,
							pos    = {px + rand.float32_range(4, 12), py + TILE},
							length = rand.float32_range(6, 12),
							phase  = rand.float32_range(0, math.TAU),
							tint   = look.accent,
							light  = mul_color(look.accent, {140, 140, 140, 255}),
							radius = 40,
						})
					}
				}
			}

			// On a wall, with open air under it, and never two close together.
			// Not in the moss: nobody needs a torch in broad daylight.
			if zone == .Mossy {
				continue
			}
			side: f32 = 0
			if solid(m, tx - 1, ty) {
				side = -1
			} else if solid(m, tx + 1, ty) {
				side = 1
			}
			if side != 0 && open(m, tx, ty + 1) && open(m, tx, ty - 1) && rand.float32() < 0.08 {
				pos := rl.Vector2{px + TILE / 2 + side * 5, py + 6}
				crowded := false
				for t in torches {
					if rl.Vector2Distance(t, pos) < TILE * 9 {
						crowded = true
					}
				}
				if !crowded {
					append(&torches, pos)
					append(&g.decor, Decor {
						kind   = .Torch,
						pos    = pos,
						side   = side,
						phase  = rand.float32_range(0, math.TAU),
						tint   = look.accent,
						light  = mul_color(look.accent, {220, 210, 200, 255}),
						radius = 84,
					})
				}
			}
		}
	}
}

// ------------------------------------------------------------------- motes ---

@(private = "file")
spawn_mote :: proc(g: ^Game, m: Mote) {
	if len(g.motes) < MAX_MOTES {
		append(&g.motes, m)
	}
}

motes_update :: proc(g: ^Game, dt: f32) {
	view := camera_view(g)
	zone := g.level.zone
	look := ZONE_LOOKS[zone]
	random_in_view :: proc(view: rl.Rectangle) -> rl.Vector2 {
		return {
			view.x + rand.float32_range(0, view.width),
			view.y + rand.float32_range(0, view.height),
		}
	}

	// What drifts depends on the world.
	switch zone {
	case .Mossy:
		// Pollen on the air, and a few butterflies about.
		if rand.float32() < dt * 3 {
			life := rand.float32_range(4, 7)
			spawn_mote(g, {
				kind = .Dust,
				pos = random_in_view(view),
				vel = {rand.float32_range(4, 12), rand.float32_range(-3, 3)},
				life = life,
				max_life = life,
				size = 0.7,
				tint = {255, 250, 210, 170},
				phase = rand.float32_range(0, math.TAU),
			})
		}
		butterflies := 0
		for m in g.motes {
			if m.kind == .Butterfly {
				butterflies += 1
			}
		}
		if butterflies < 5 && rand.float32() < dt * 0.8 {
			life := rand.float32_range(8, 14)
			spawn_mote(g, {
				kind = .Butterfly,
				pos = random_in_view(view),
				vel = {rand.float32_range(-14, 14), rand.float32_range(-6, 6)},
				life = life,
				max_life = life,
				size = f32(rand.int_max(3)), // which colour
				tint = {255, 255, 255, 255},
				phase = rand.float32_range(0, math.TAU),
			})
		}
	case .Drowned:
		if rand.float32() < dt * 2.5 {
			life := rand.float32_range(3, 6)
			spawn_mote(g, {
				kind = .Bubble,
				pos = {view.x + rand.float32_range(0, view.width), view.y + view.height + 4},
				vel = {0, rand.float32_range(-30, -14)},
				life = life,
				max_life = life,
				size = rand.float32_range(1, 2.6),
				phase = rand.float32_range(0, math.TAU),
			})
		}
		if rand.float32() < dt * 5 {
			life := rand.float32_range(4, 7)
			spawn_mote(g, {
				kind = .Dust,
				pos = random_in_view(view),
				vel = {rand.float32_range(-4, 4), rand.float32_range(2, 6)},
				life = life,
				max_life = life,
				size = 0.8,
				tint = {170, 200, 240, 150},
				phase = rand.float32_range(0, math.TAU),
			})
		}
		// Water gathers on the tips of the stalactites and lets go.
		for d in g.decor {
			if d.kind != .Stalactite || !rl.CheckCollisionPointRec(d.pos, view) {
				continue
			}
			if rand.float32() < dt * 0.25 {
				spawn_mote(g, {
					kind = .Drip,
					pos = d.pos + {0, d.length},
					life = 3,
					max_life = 3,
					size = 1,
					tint = {170, 220, 255, 220},
				})
			}
		}
	case .Ember:
		if rand.float32() < dt * 7 {
			life := rand.float32_range(2, 4)
			spawn_mote(g, {
				kind = .Ember,
				pos = {view.x + rand.float32_range(0, view.width), view.y + view.height + 4},
				vel = {rand.float32_range(-10, 10), rand.float32_range(-46, -22)},
				life = life,
				max_life = life,
				size = rand.float32_range(0.7, 1.4),
				tint = look.mote,
				glow = true,
				phase = rand.float32_range(0, math.TAU),
			})
		}
		for glow in g.liquid_glows {
			if rl.CheckCollisionPointRec(glow, view) && rand.float32() < dt * 0.6 {
				life := rand.float32_range(1, 2)
				spawn_mote(g, {
					kind = .Ember,
					pos = glow + {rand.float32_range(-8, 8), -2},
					vel = {rand.float32_range(-6, 6), rand.float32_range(-40, -20)},
					life = life,
					max_life = life,
					size = 1.2,
					tint = {255, 180, 90, 255},
					glow = true,
				})
			}
		}
	}

	// Torches shed sparks whatever the zone.
	for d in g.decor {
		if d.kind == .Torch && rl.CheckCollisionPointRec(d.pos, view) && rand.float32() < dt * 1.5 {
			spawn_mote(g, {
				kind = .Ember,
				pos = d.pos + {rand.float32_range(-1.5, 1.5), -3},
				vel = {rand.float32_range(-5, 5), rand.float32_range(-24, -12)},
				life = 0.9,
				max_life = 0.9,
				size = 0.8,
				tint = d.tint,
				glow = false,
			})
		}
	}

	live := 0
	for &m in g.motes {
		m.life -= dt
		m.phase += dt
		switch m.kind {
		case .Firefly:
			m.vel += {math.cos(m.phase * 1.3) * 10, math.sin(m.phase * 1.7) * 10} * dt
		case .Dust:
			m.vel.x += math.sin(m.phase) * 2 * dt
		case .Drip:
			m.vel.y += 420 * dt
			if is_blocking(tile_at(&g.map_tiles, int(m.pos.x / TILE), int(m.pos.y / TILE))) ||
			   tile_at(&g.map_tiles, int(m.pos.x / TILE), int(m.pos.y / TILE)) == .Water {
				spawn_burst(g, m.pos - {0, 1}, {170, 220, 255, 255}, 3, 40, 0.8)
				m.life = 0
			}
		case .Ember:
			m.vel.x += math.sin(m.phase * 3) * 12 * dt
		case .Butterfly:
			// Fluttering: wandering sideways, bobbing in little hops.
			m.vel.x += math.cos(m.phase * 0.7) * 18 * dt
			m.vel.y = math.sin(m.phase * 5) * 14 + math.sin(m.phase * 0.9) * 6
			m.vel.x = clamp(m.vel.x, -20, 20)
		case .Bubble:
			m.vel.x = math.sin(m.phase * 4) * 6
		}
		m.pos += m.vel * dt
		if m.life <= 0 || !rl.CheckCollisionPointRec(m.pos, {view.x - 40, view.y - 40, view.width + 80, view.height + 80}) {
			continue
		}
		g.motes[live] = m
		live += 1
	}
	resize(&g.motes, live)
}

motes_draw :: proc(g: ^Game) {
	// Butterflies and bubbles are drawn as they are, before the glowing kinds.
	for m in g.motes {
		fade := clamp(m.life / m.max_life * 4, 0, 1) * clamp(m.life * 2, 0, 1)
		switch m.kind {
		case .Butterfly:
			frame := int(m.phase * 8) % 2
			col := int(m.size) % 3
			src := rl.Rectangle{f32(col * 2 + frame) * 8, 0, m.vel.x < 0 ? -8 : 8, 8}
			rl.DrawTexturePro(g.assets.critters, src, {math.round(m.pos.x), math.round(m.pos.y), 8, 8}, {4, 4}, 0, {255, 255, 255, u8(255 * fade)})
		case .Bubble:
			rl.DrawCircleLinesV(m.pos, m.size, {230, 250, 255, u8(200 * fade)})
			rl.DrawPixelV(m.pos - {m.size * 0.4, m.size * 0.4}, {255, 255, 255, u8(230 * fade)})
		case .Firefly, .Dust, .Drip, .Ember:
		}
	}
	rl.BeginBlendMode(.ADDITIVE)
	for m in g.motes {
		if m.kind == .Butterfly || m.kind == .Bubble {
			continue
		}
		fade := clamp(m.life / m.max_life * 3, 0, 1) * clamp(m.life * 2, 0, 1)
		c := m.tint
		c.a = u8(f32(c.a) * fade)
		size := m.size
		if m.kind == .Firefly {
			// Fireflies blink.
			c.a = u8(f32(c.a) * (0.5 + 0.5 * math.sin(m.phase * 4)))
			halo := c
			halo.a /= 4
			rl.DrawCircleV(m.pos, 3, halo)
		}
		if m.kind == .Drip {
			rl.DrawLineV(m.pos - {0, 3}, m.pos, c)
			continue
		}
		rl.DrawCircleV(m.pos, size, c)
	}
	rl.EndBlendMode()
}

// ------------------------------------------------------------------ drawing ---

decor_draw :: proc(g: ^Game) {
	view := camera_view(g)
	t := g.time
	for d in g.decor {
		if !rl.CheckCollisionPointRec(d.pos, {view.x - 48, view.y - 48, view.width + 96, view.height + 96}) {
			continue
		}
		switch d.kind {
		case .Root:
			draw_root(d, t)
		case .Stalactite:
			tip := d.pos + {0, d.length}
			tri(d.pos + {-3.5, -1}, tip, d.pos + {3.5, -1}, d.tint)
			hi := lerp_color(d.tint, {255, 255, 255, 255}, 0.25)
			rl.DrawLineV(d.pos + {-1.5, 0}, tip - {0.3, 2}, hi)
		case .Crystal:
			draw_crystal(d, t)
		case .Mushroom:
			stem := rl.Color{190, 200, 180, 255}
			rl.DrawRectangleV(d.pos + {-0.5, -4}, {1.5, 4}, stem)
			cap := d.tint
			cap.a = u8(200 + 55 * math.sin(t * 2 + d.phase))
			rl.DrawCircleSector(d.pos + {0.25, -4}, 3, 180, 360, 8, cap)
		case .Torch:
			draw_torch(d, t)
		}
	}
}

@(private = "file")
draw_root :: proc(d: Decor, t: f32) {
	segs := max(2, int(d.length / 5))
	prev := d.pos
	leaf := rl.Color{86, 128, 66, 255}
	for i in 1 ..= segs {
		f := f32(i) / f32(segs)
		sway := math.sin(t * 1.3 + d.phase + f * 2) * 2.2 * f
		p := d.pos + {sway, d.length * f}
		rl.DrawLineEx(prev, p, 1.4 - f * 0.6, d.tint)
		if i % 2 == 0 {
			side: f32 = (i / 2) % 2 == 0 ? 1 : -1
			tri(p, p + {side * 3, 1.5}, p + {0, 2.5}, leaf)
		}
		prev = p
	}
}

@(private = "file")
draw_crystal :: proc(d: Decor, t: f32) {
	pulse := 0.8 + 0.2 * math.sin(t * 2 + d.phase)
	base := d.tint
	dark := mul_color(base, {120, 120, 140, 255})
	bright := lerp_color(base, {255, 255, 255, 255}, 0.4 * pulse)
	h := d.length
	// Three shards, the middle one tallest.
	shard :: proc(foot: rl.Vector2, h, w, lean: f32, fill, edge: rl.Color) {
		tip := foot + {lean, -h}
		tri(foot + {-w, 0}, foot + {w, 0}, tip, fill)
		rl.DrawLineV(foot + {-w * 0.3, -0.5}, tip, edge)
	}
	shard(d.pos + {-3.5, 0}, h * 0.6, 2, -2, dark, bright)
	shard(d.pos + {3.5, 0}, h * 0.5, 2, 2, dark, bright)
	shard(d.pos, h, 2.5, 0.5, base, bright)
}

@(private = "file")
draw_torch :: proc(d: Decor, t: f32) {
	wall_x := d.pos.x + d.side * 5
	bracket := rl.Color{58, 48, 44, 255}
	rl.DrawRectangleV({min(wall_x, d.pos.x), d.pos.y + 4}, {abs(wall_x - d.pos.x) + 1, 1.5}, bracket)
	rl.DrawRectangleV({d.pos.x - 1, d.pos.y + 1}, {2, 6}, {92, 66, 46, 255})

	// The flame: three blobs, each flickering at its own rate.
	f1 := math.sin(t * 13 + d.phase) * 0.5
	f2 := math.sin(t * 17 + d.phase * 2) * 0.6
	outer := d.tint
	rl.BeginBlendMode(.ADDITIVE)
	halo := outer
	halo.a = 60
	rl.DrawCircleV(d.pos - {0, 1}, 6 + f1, halo)
	rl.EndBlendMode()
	rl.DrawCircleV(d.pos - {0, 1 + f2 * 0.3}, 2.6 + f1 * 0.4, outer)
	tri(d.pos + {-2.4, -1}, d.pos + {f2, -6.5 + f1}, d.pos + {2.4, -1}, outer)
	core := lerp_color(outer, {255, 250, 220, 255}, 0.7)
	rl.DrawCircleV(d.pos - {0, 1.2}, 1.3, core)
}

// raylib only fills triangles wound one way round; this fills either.
tri :: proc(a, b, c: rl.Vector2, colour: rl.Color) {
	cross := (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
	if cross < 0 {
		rl.DrawTriangle(a, b, c, colour)
	} else {
		rl.DrawTriangle(a, c, b, colour)
	}
}
