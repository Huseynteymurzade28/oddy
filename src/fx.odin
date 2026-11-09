package game

import "core:math"
import "core:math/rand"
import rl "../libs/raylib"

/*
Particles that only exist to be looked at: the dust a landing kicks up, the
puff behind a dash, the burst a death leaves behind. None of them collide.
*/

Spark :: struct {
	pos:      rl.Vector2,
	vel:      rl.Vector2,
	life:     f32,
	max_life: f32,
	size:     f32,
	gravity:  f32,
	tint:     rl.Color,
}

spawn_spark :: proc(g: ^Game, pos: rl.Vector2, dir: rl.Vector2, tint: rl.Color, speed, size: f32) {
	angle := math.atan2(dir.y, dir.x) + rand.float32_range(-0.9, 0.9)
	s := rand.float32_range(speed * 0.4, speed)
	life := rand.float32_range(0.12, 0.32)
	append(
		&g.sparks,
		Spark {
			pos = pos,
			vel = {math.cos(angle) * s, math.sin(angle) * s},
			life = life,
			max_life = life,
			size = size,
			gravity = 120,
			tint = tint,
		},
	)
}

spawn_burst :: proc(g: ^Game, pos: rl.Vector2, tint: rl.Color, count: int, speed, size: f32) {
	for _ in 0 ..< count {
		angle := rand.float32_range(0, math.TAU)
		spawn_spark(g, pos, {math.cos(angle), math.sin(angle)}, tint, speed, size)
	}
}

sparks_update :: proc(g: ^Game, dt: f32) {
	live := 0
	for &s in g.sparks {
		s.life -= dt
		if s.life <= 0 {
			continue
		}
		s.vel.y += s.gravity * dt
		s.vel *= 1 - min(1, 3.0 * dt)
		s.pos += s.vel * dt
		g.sparks[live] = s
		live += 1
	}
	resize(&g.sparks, live)
}

sparks_draw :: proc(g: ^Game) {
	rl.BeginBlendMode(.ADDITIVE)
	for s in g.sparks {
		c := s.tint
		c.a = u8(f32(c.a) * clamp(s.life / s.max_life, 0, 1))
		rl.DrawCircleV(s.pos, s.size, c)
	}
	rl.EndBlendMode()
}

// A one-shot animation left in the world: the puff a body vanishes in, or
// arrives in.
Poof :: struct {
	anim: Animator,
	pos:  rl.Vector2,
}

spawn_poof :: proc(g: ^Game, anim: ^Anim, pos: rl.Vector2) {
	p := Poof{pos = pos}
	animator_restart(&p.anim, anim)
	append(&g.poofs, p)
}

poofs_update :: proc(g: ^Game, dt: f32) {
	live := 0
	for &p in g.poofs {
		animator_update(&p.anim, dt)
		if p.anim.finished {
			continue
		}
		g.poofs[live] = p
		live += 1
	}
	resize(&g.poofs, live)
}

poofs_draw :: proc(g: ^Game) {
	for p in g.poofs {
		animator_draw(p.anim, p.pos, false)
	}
}

// ------------------------------------------------------------ popups ---

// A word that floats up out of the world and fades: "+3", "x2".
Popup :: struct {
	text:   cstring,
	pos:    rl.Vector2,
	t:      f32,
	colour: rl.Color,
}

POPUP_TIME :: 0.9

spawn_popup :: proc(g: ^Game, pos: rl.Vector2, colour: rl.Color, text: cstring) {
	append(&g.popups, Popup{text = text, pos = pos, colour = colour})
}

popups_update :: proc(g: ^Game, dt: f32) {
	live := 0
	for &p in g.popups {
		p.t += dt
		p.pos.y -= (28 - p.t * 20) * dt
		if p.t >= POPUP_TIME {
			delete(p.text)
			continue
		}
		g.popups[live] = p
		live += 1
	}
	resize(&g.popups, live)
}

popups_draw :: proc(g: ^Game) {
	a := &g.assets
	for p in g.popups {
		// Pops in a size larger, then settles; fades over the last third.
		k := clamp(1 - p.t / POPUP_TIME, 0, 1)
		alpha := u8(255 * clamp(k * 3, 0, 1))
		w := rl.MeasureTextEx(a.font, p.text, 8, 1).x
		pos := rl.Vector2{math.round(p.pos.x - w / 2), math.round(p.pos.y)}
		ink := rl.Color{40, 26, 34, alpha}
		for d in ([4]rl.Vector2{{-1, 0}, {1, 0}, {0, -1}, {0, 1}}) {
			rl.DrawTextEx(a.font, p.text, pos + d, 8, 1, ink)
		}
		rl.DrawTextEx(a.font, p.text, pos + {0, 1}, 8, 1, ink)
		c := p.colour
		c.a = alpha
		rl.DrawTextEx(a.font, p.text, pos, 8, 1, c)
	}
}

// ---------------------------------------------------------- confetti ---

Confetti :: struct {
	pos:    rl.Vector2,
	vel:    rl.Vector2,
	spin:   f32,
	angle:  f32,
	life:   f32,
	colour: rl.Color,
}

CONFETTI_COLOURS := [6]rl.Color {
	{255, 120, 150, 255},
	{255, 214, 80, 255},
	{120, 220, 255, 255},
	{150, 230, 120, 255},
	{200, 150, 255, 255},
	{255, 160, 90, 255},
}

spawn_confetti :: proc(g: ^Game, pos: rl.Vector2, count: int) {
	for i in 0 ..< count {
		angle := rand.float32_range(-math.PI * 0.85, -math.PI * 0.15)
		speed := rand.float32_range(90, 230)
		append(&g.confetti, Confetti {
			pos    = pos,
			vel    = {math.cos(angle) * speed, math.sin(angle) * speed},
			spin   = rand.float32_range(-12, 12),
			angle  = rand.float32_range(0, 360),
			life   = rand.float32_range(1.6, 2.6),
			colour = CONFETTI_COLOURS[i % len(CONFETTI_COLOURS)],
		})
	}
}

confetti_update :: proc(g: ^Game, dt: f32) {
	live := 0
	for &c in g.confetti {
		c.life -= dt
		if c.life <= 0 {
			continue
		}
		c.vel.y += 160 * dt
		c.vel *= 1 - min(1, 1.6 * dt) // the air slows paper quickly
		c.vel.x += math.sin(c.life * 7 + c.spin) * 30 * dt // and it flutters
		c.pos += c.vel * dt
		c.angle += c.spin * 30 * dt
		g.confetti[live] = c
		live += 1
	}
	resize(&g.confetti, live)
}

confetti_draw :: proc(g: ^Game) {
	for c in g.confetti {
		col := c.colour
		col.a = u8(255 * clamp(c.life, 0, 1))
		// A flat piece of paper turning over: its width swings with the spin.
		w := 3 * abs(math.cos(c.angle * math.PI / 180)) + 0.6
		rl.DrawRectanglePro({c.pos.x, c.pos.y, w, 2}, {w / 2, 1}, c.angle * 0.3, col)
	}
}

// ------------------------------------------------------------ chips ---

// A splinter of a broken crate, tumbling under gravity.
Chip :: struct {
	pos:   rl.Vector2,
	vel:   rl.Vector2,
	angle: f32,
	spin:  f32,
	kind:  int,
	life:  f32,
}

spawn_chips :: proc(g: ^Game, centre: rl.Vector2, push: rl.Vector2) {
	for i in 0 ..< 6 {
		angle := rand.float32_range(0, math.TAU)
		speed := rand.float32_range(60, 150)
		append(&g.chips, Chip {
			pos   = centre + {rand.float32_range(-5, 5), rand.float32_range(-5, 5)},
			vel   = {math.cos(angle) * speed, math.sin(angle) * speed - 90} + push * 0.3,
			spin  = rand.float32_range(-20, 20),
			kind  = i % 4,
			life  = 1.2,
		})
	}
}

chips_update :: proc(g: ^Game, dt: f32) {
	live := 0
	for &c in g.chips {
		c.life -= dt
		if c.life <= 0 {
			continue
		}
		c.vel.y += GRAVITY * dt
		c.pos += c.vel * dt
		c.angle += c.spin * 20 * dt
		g.chips[live] = c
		live += 1
	}
	resize(&g.chips, live)
}

chips_draw :: proc(g: ^Game) {
	tex := g.assets.terrain[g.level.zone]
	for c in g.chips {
		tint := rl.Color{255, 255, 255, u8(255 * clamp(c.life * 2, 0, 1))}
		rl.DrawTexturePro(tex, terrain_source(9 + c.kind, ROW_LIQUID), {c.pos.x, c.pos.y, TILE, TILE}, {TILE / 2, TILE / 2}, c.angle, tint)
	}
}
