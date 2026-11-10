package game

import "core:math"
import rl "../libs/raylib"

/*
The dark, and what pushes it back.

The world is drawn at full brightness, then multiplied by a light map: a small
render target the size of the virtual screen, cleared to the zone's ambient
colour and with every light added on top as a soft circle. Where lights pile up
the map saturates to white and the art shows as painted; everywhere else it
sinks toward the ambient tint. That one multiply is what gives the zones their
colour, makes a torch read as a torch, and lets a lit checkpoint stand out in the dark.

The map is a quarter of a megapixel at most and the lights are a few dozen
gradient circles, so this is cheap enough for a phone.
*/

Lighting :: struct {
	target:  rl.RenderTexture2D,
	size:    [2]i32,
	ambient: rl.Color, // eased toward the level's, so a change fades in
	// How much of the sky reaches each corner of each tile, 255 for all of
	// it: (width + 1) x (height + 1), baked when a level is entered.
	sky:     []u8,
	sky_w:   int,
	sky_h:   int,
}

// How far the daylight carries under a roof, in tiles, and how much harder
// it is for it to get through earth than through air.
SKY_REACH :: 12.0
SKY_EARTH_COST :: 1.8
SKY_ROOF_REACH :: 5 // tiles under a roof that it shades
SKY_AIR_SHADE :: 0.6 // open air never gets as dark as the inside of the earth

lighting_destroy :: proc(l: ^Lighting) {
	if l.target.id != 0 {
		rl.UnloadRenderTexture(l.target)
	}
	delete(l.sky)
	l^ = {}
}

/*
Works out where the sky reaches. Every cell with open air above it is lit; from there the light spreads cell to cell, losing a little with each
step through air and more with each step through earth. The result is soft
shade under overhangs and in caves, and ground that darkens the deeper into
it you look, which is what makes the earth read as a solid mass rather than
a flat pattern.
*/
lighting_bake :: proc(g: ^Game) {
	m := &g.map_tiles
	l := &g.lighting
	w, h := m.width, m.height
	FAR :: f32(1e6)

	dist := make([]f32, w * h, context.temp_allocator)
	// A roof only keeps the daylight off what is close under it: in a tall
	// shaft the sky still finds its way down past the ledges.
	for x in 0 ..< w {
		since_roof := SKY_ROOF_REACH
		for y in 0 ..< h {
			if is_ground(m.tiles[y * w + x]) {
				since_roof = 0
			} else {
				since_roof += 1
			}
			dist[y * w + x] = since_roof > SKY_ROOF_REACH ? 0 : FAR
		}
	}

	// Sweeps there and back until nothing changes: plenty for a level-sized
	// grid, and it only runs once per level.
	relax :: proc(m: ^Tilemap, dist: []f32, x, y, dx, dy: int) -> bool {
		nx, ny := x + dx, y + dy
		if nx < 0 || ny < 0 || nx >= m.width || ny >= m.height {
			return false
		}
		i := y * m.width + x
		step: f32 = is_ground(m.tiles[i]) ? SKY_EARTH_COST : 1
		if dx != 0 && dy != 0 {
			step *= 1.414
		}
		d := dist[ny * m.width + nx] + step
		if d < dist[i] {
			dist[i] = d
			return true
		}
		return false
	}
	for _ in 0 ..< 12 {
		changed := false
		for y in 0 ..< h {
			for x in 0 ..< w {
				changed |= relax(m, dist, x, y, -1, 0)
				changed |= relax(m, dist, x, y, 0, -1)
				changed |= relax(m, dist, x, y, -1, -1)
				changed |= relax(m, dist, x, y, 1, -1)
			}
		}
		for y := h - 1; y >= 0; y -= 1 {
			for x := w - 1; x >= 0; x -= 1 {
				changed |= relax(m, dist, x, y, 1, 0)
				changed |= relax(m, dist, x, y, 0, 1)
				changed |= relax(m, dist, x, y, 1, 1)
				changed |= relax(m, dist, x, y, -1, 1)
			}
		}
		if !changed {
			break
		}
	}

	// The first cell under the sky is still fully lit, earth or air.
	cell :: proc(m: ^Tilemap, dist: []f32, x, y: int) -> f32 {
		cx := clamp(x, 0, m.width - 1)
		cy := clamp(y, 0, m.height - 1)
		i := cy * m.width + cx
		earth := is_ground(m.tiles[i])
		d := dist[i] - (earth ? SKY_EARTH_COST : 1)
		t := clamp(d / SKY_REACH, 0, 1)
		t = t * t * (3 - 2 * t)
		return 1 - t * (earth ? 1 : SKY_AIR_SHADE)
	}

	delete(l.sky)
	l.sky_w, l.sky_h = w + 1, h + 1
	l.sky = make([]u8, l.sky_w * l.sky_h)
	for y in 0 ..= h {
		for x in 0 ..= w {
			v := cell(m, dist, x - 1, y - 1) + cell(m, dist, x, y - 1) + cell(m, dist, x - 1, y) + cell(m, dist, x, y)
			l.sky[y * l.sky_w + x] = u8(v / 4 * 255)
		}
	}
}

// Multiplies the light map by the baked sky, a smooth quad per tile. Lights
// are added after this, so a torch or Lumi herself pushes the shade back.
@(private = "file")
draw_sky_shade :: proc(g: ^Game, view: rl.Rectangle) {
	l := &g.lighting
	if len(l.sky) == 0 {
		return
	}
	shade := ZONE_LOOKS[g.level.zone].shade
	at :: proc(l: ^Lighting, x, y: int) -> u8 {
		return l.sky[clamp(y, 0, l.sky_h - 1) * l.sky_w + clamp(x, 0, l.sky_w - 1)]
	}
	x0 := int(math.floor(view.x / TILE)) - 1
	y0 := int(math.floor(view.y / TILE)) - 1
	x1 := int((view.x + view.width) / TILE) + 1
	y1 := int((view.y + view.height) / TILE) + 1
	rl.BeginBlendMode(.MULTIPLIED)
	for y in y0 ..= y1 {
		for x in x0 ..= x1 {
			tl, tr := at(l, x, y), at(l, x + 1, y)
			bl, br := at(l, x, y + 1), at(l, x + 1, y + 1)
			if tl == 255 && tr == 255 && bl == 255 && br == 255 {
				continue
			}
			c :: proc(shade: rl.Color, v: u8) -> rl.Color {
				return lerp_color(shade, rl.WHITE, f32(v) / 255)
			}
			rec := rl.Rectangle{f32(x) * TILE, f32(y) * TILE, TILE, TILE}
			rl.DrawRectangleGradientEx(rec, c(shade, tl), c(shade, bl), c(shade, br), c(shade, tr))
		}
	}
	rl.EndBlendMode()
}

// Draws one soft light into the map. Only valid between `lighting_begin` and
// `lighting_end`.
light :: proc(pos: rl.Vector2, radius: f32, colour: rl.Color) {
	rl.DrawCircleGradient(pos, radius, colour, {0, 0, 0, 0})
}

lighting_update :: proc(g: ^Game, dt: f32) {
	want := ZONE_LOOKS[g.level.zone].ambient
	if g.lighting.ambient.a == 0 {
		g.lighting.ambient = want
	}
	g.lighting.ambient = lerp_color(g.lighting.ambient, want, min(1, dt * 3))
}

// Renders the light map for this frame. Done before the world is drawn, since
// it uses its own render target.
lighting_render :: proc(g: ^Game, shake: rl.Vector2) {
	l := &g.lighting
	view := view_size()
	size := [2]i32{i32(math.ceil(view.x)), i32(PIXEL_HEIGHT)}
	if l.target.id == 0 || l.size != size {
		if l.target.id != 0 {
			rl.UnloadRenderTexture(l.target)
		}
		l.target = rl.LoadRenderTexture(size.x, size.y)
		rl.SetTextureFilter(l.target.texture, .BILINEAR)
		l.size = size
	}

	cam := rl.Camera2D {
		target = g.camera.target,
		offset = view / 2 + shake / max(g.camera.zoom, 0.01),
		zoom   = 1,
	}

	rl.BeginTextureMode(l.target)
	rl.ClearBackground(l.ambient)
	rl.BeginMode2D(cam)
	draw_sky_shade(g, camera_view(g))
	rl.BeginBlendMode(.ADDITIVE)
	gather_lights(g)
	rl.EndBlendMode()
	rl.EndMode2D()
	rl.EndTextureMode()
}

// Multiplies the screen by the light map.
lighting_apply :: proc(g: ^Game) {
	l := &g.lighting
	if l.target.id == 0 {
		return
	}
	src := rl.Rectangle{0, 0, f32(l.size.x), -f32(l.size.y)}
	s := hud_scale()
	dest := rl.Rectangle{0, 0, f32(l.size.x) * s, f32(l.size.y) * s}
	rl.BeginBlendMode(.MULTIPLIED)
	rl.DrawTexturePro(l.target.texture, src, dest, {}, 0, rl.WHITE)
	rl.EndBlendMode()
}

@(private = "file")
gather_lights :: proc(g: ^Game) {
	view := camera_view(g)
	near :: proc(view: rl.Rectangle, p: rl.Vector2, r: f32) -> bool {
		inside_x := p.x > view.x - r && p.x < view.x + view.width + r
		return inside_x && p.y > view.y - r && p.y < view.y + view.height + r
	}
	flicker := 1 + math.sin(g.time * 11) * 0.03 + math.sin(g.time * 23) * 0.02

	// Lumi is a light: the dark is never total around her. Warm while her
	// dash is ready, a cooler blue while it is spent.
	if !g.player.dead || g.player.death_timer > 0 {
		c := player_centre(g.player)
		warm := g.player.dashes > 0
		light(c, 120 * flicker, warm ? rl.Color{170, 150, 110, 255} : rl.Color{110, 130, 170, 255})
		light(c, 56, warm ? rl.Color{140, 120, 90, 255} : rl.Color{90, 110, 150, 255})
	}

	for d in g.decor {
		if d.radius <= 0 || !near(view, d.pos, d.radius) {
			continue
		}
		r := d.radius
		if d.kind == .Torch {
			r *= 1 + math.sin(g.time * 9 + d.pos.x) * 0.06
		}
		light(d.pos, r, d.light)
	}

	// The lava lights the room it is in from below.
	for glow in g.liquid_glows {
		if near(view, glow, 60) {
			light(glow, 56 + math.sin(g.time * 2 + glow.x * 0.1) * 4, {170, 70, 30, 255})
		}
	}

	for s in g.sparks {
		if s.size >= 1.8 && near(view, s.pos, 20) {
			c := s.tint
			c.a = 255
			light(s.pos, 14 * (s.life / s.max_life), mul_color(c, {120, 120, 120, 255}))
		}
	}
	for m in g.motes {
		if m.glow && near(view, m.pos, 16) {
			a := clamp(m.life / m.max_life * 3, 0, 1) * clamp(m.life, 0, 1)
			light(m.pos, 12, mul_color(m.tint, {u8(90 * a), u8(90 * a), u8(90 * a), 255}))
		}
	}

	for t in g.things {
		if !near(view, t.pos, 60) {
			continue
		}
		#partial switch t.kind {
		case .Fire:
			if t.state == 2 {
				light(t.pos - {0, 22}, 46 + math.sin(g.time * 17) * 3, {220, 120, 50, 255})
			} else if t.state == 1 {
				light(t.pos - {0, 18}, 22, {160, 90, 40, 255})
			}
		case .Refill:
			if t.state == 0 {
				light(t.pos, 26, {120, 150, 190, 255})
			}
		}
	}

	// Light blocks, while they are there, are lamps.
	if g.level.has_light && light_solid[.Lit] {
		x0, y0 := int(view.x / TILE) - 1, int(view.y / TILE) - 1
		x1, y1 := int((view.x + view.width) / TILE) + 1, int((view.y + view.height) / TILE) + 1
		for y in y0 ..= y1 {
			for x in x0 ..= x1 {
				if (x + y) % 2 == 0 && tile_at(&g.map_tiles, x, y) == .Lit {
					light({f32(x) * TILE + 8, f32(y) * TILE + 8}, 30, {120, 96, 50, 255})
				}
			}
		}
	}

	// Lit lanterns light the dark round them; the trophy at the end always
	// glows.
	for c in g.level.checkpoints {
		if c.lit && near(view, c.pos, 60) {
			light(c.pos + LANTERN_OFFSET, 64, {190, 150, 90, 255})
		}
	}
	light(g.level.exit - {0, 20}, 70, {200, 170, 100, 255})
}
