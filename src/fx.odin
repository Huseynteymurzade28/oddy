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
