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
}

lighting_destroy :: proc(l: ^Lighting) {
	if l.target.id != 0 {
		rl.UnloadRenderTexture(l.target)
	}
	l^ = {}
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

	// You carry a lantern's worth of light, so the dark is never total.
	if !g.player.dead || g.player.death_timer > 0 {
		c := player_centre(g.player)
		light(c, 110 * flicker, {150, 140, 120, 255})
		light(c, 50, {120, 110, 96, 255})
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

	// Checkpoints glow once they are lit, and the flag at the end always does.
	for c in g.level.checkpoints {
		if c.active && near(view, c.pos, 60) {
			light(c.pos - {0, 20}, 54, {170, 160, 120, 255})
		}
	}
	light(g.level.exit - {0, 20}, 70, {200, 170, 100, 255})
}
