package game

import "core:math"
import "core:math/rand"
import rl "vendor:raylib"

/*
Shots are drawn as a bright point of light rather than a sprite: a white core
inside two additive halos, with a short streak behind it in the direction of
travel. It reads cleanly at 16px tile scale and colours itself per weapon.
*/

BULLET_RADIUS :: 1.6
EXPLOSION_RADIUS :: 26.0

Bullet :: struct {
	pos:         rl.Vector2,
	vel:         rl.Vector2,
	damage:      f32,
	life:        f32,
	pierce:      int,
	explosive:   bool,
	knockback:   f32,
	tint:        rl.Color,
	from_player: bool,
	last_hit:    int, // enemy index this shot already passed through
	dead:        bool,
}

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
	for i in 0 ..< count {
		angle := rand.float32_range(0, math.TAU)
		spawn_spark(g, pos, {math.cos(angle), math.sin(angle)}, tint, speed, size)
	}
}

// Fires one weapon. Called with the muzzle position so the tracer starts at the
// barrel rather than inside the player.
weapon_fire :: proc(g: ^Game, w: ^Weapon, origin: rl.Vector2, angle: f32) {
	for i in 0 ..< max(1, w.pellets) {
		a := angle + rand.float32_range(-w.spread, w.spread)
		dir := rl.Vector2{math.cos(a), math.sin(a)}
		// Pellets from a spread weapon carry slightly different speeds so the
		// cloud stretches out instead of staying a rigid arc.
		speed := w.speed * (w.pellets > 1 ? rand.float32_range(0.82, 1.08) : 1)
		append(
			&g.bullets,
			Bullet {
				pos = origin,
				vel = dir * speed,
				damage = w.damage,
				life = w.range / max(speed, 1),
				pierce = w.pierce,
				explosive = w.explosive,
				knockback = w.knockback,
				tint = w.tint,
				from_player = true,
				last_hit = -1,
			},
		)
	}

	spawn_spark(g, origin, {math.cos(angle), math.sin(angle)}, w.tint, 90, 1.4)
	g.shake = max(g.shake, w.pellets > 1 ? 3.0 : 1.2)
	play(&g.assets, .Shoot)
}

enemy_fire :: proc(g: ^Game, origin, vel: rl.Vector2, damage, life: f32, tint: rl.Color) {
	append(
		&g.bullets,
		Bullet {
			pos = origin,
			vel = vel,
			damage = damage,
			life = life,
			tint = tint,
			from_player = false,
			last_hit = -1,
		},
	)
}

@(private = "file")
explode :: proc(g: ^Game, b: ^Bullet) {
	spawn_burst(g, b.pos, b.tint, 22, 240, 2.2)
	spawn_burst(g, b.pos, {255, 240, 190, 255}, 10, 150, 1.6)
	g.shake = max(g.shake, 7)
	play(&g.assets, .Explode)

	for &e, i in g.enemies {
		if !e.alive {
			continue
		}
		centre := enemy_centre(e)
		if rl.Vector2Distance(centre, b.pos) > EXPLOSION_RADIUS {
			continue
		}
		push := rl.Vector2Normalize(centre - b.pos) * b.knockback
		enemy_damage(g, i, b.damage, push)
	}
	// The blast is indiscriminate, which is the price of carrying a launcher.
	if rl.Vector2Distance(player_centre(g.player), b.pos) < EXPLOSION_RADIUS * 0.8 {
		player_hurt(&g.player, &g.assets, b.pos.x)
		g.shake = max(g.shake, 9)
	}
}

bullets_update :: proc(g: ^Game, dt: f32) {
	for &b in g.bullets {
		if b.dead {
			continue
		}
		b.life -= dt
		b.pos += b.vel * dt
		if b.life <= 0 {
			b.dead = true
			continue
		}

		if is_blocking(tile_at(&g.map_tiles, int(b.pos.x / TILE), int(b.pos.y / TILE))) {
			b.dead = true
			if b.explosive {
				explode(g, &b)
			} else {
				spawn_spark(g, b.pos, -rl.Vector2Normalize(b.vel), b.tint, 110, 1.3)
				spawn_spark(g, b.pos, -rl.Vector2Normalize(b.vel), b.tint, 80, 1.0)
			}
			continue
		}

		if b.from_player {
			for &e, i in g.enemies {
				if !e.alive || i == b.last_hit {
					continue
				}
				if !rl.CheckCollisionCircleRec(b.pos, BULLET_RADIUS + 1, enemy_rect(e)) {
					continue
				}
				if b.explosive {
					b.dead = true
					explode(g, &b)
					break
				}
				push := rl.Vector2Normalize(b.vel) * b.knockback
				enemy_damage(g, i, b.damage, push)
				spawn_spark(g, b.pos, -rl.Vector2Normalize(b.vel), b.tint, 130, 1.4)
				b.last_hit = i
				if b.pierce <= 0 {
					b.dead = true
					break
				}
				b.pierce -= 1
			}
		} else if !g.player.dead {
			if rl.CheckCollisionCircleRec(b.pos, BULLET_RADIUS + 1, player_rect(g.player)) {
				b.dead = true
				if player_hurt(&g.player, &g.assets, b.pos.x) {
					g.shake = max(g.shake, 5)
				}
				spawn_burst(g, b.pos, b.tint, 8, 120, 1.4)
			}
		}
	}

	// Compact in place; the order of live bullets does not matter.
	live := 0
	for b in g.bullets {
		if !b.dead {
			g.bullets[live] = b
			live += 1
		}
	}
	resize(&g.bullets, live)
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

// A glowing point: a hot white core wrapped in two soft halos, plus a streak
// showing where it came from.
@(private = "file")
draw_glow :: proc(pos: rl.Vector2, radius: f32, tint: rl.Color) {
	halo := tint
	halo.a = 50
	rl.DrawCircleV(pos, radius * 2.6, halo)
	halo.a = 110
	rl.DrawCircleV(pos, radius * 1.5, halo)
	rl.DrawCircleV(pos, radius * 0.7, rl.Color{255, 255, 255, 235})
}

bullets_draw :: proc(g: ^Game) {
	rl.BeginBlendMode(.ADDITIVE)
	defer rl.EndBlendMode()

	for b in g.bullets {
		trail := b.tint
		trail.a = 70
		rl.DrawLineV(b.pos - b.vel * 0.02, b.pos, trail)
		draw_glow(b.pos, b.explosive ? BULLET_RADIUS * 1.7 : BULLET_RADIUS, b.tint)
	}

	for s in g.sparks {
		t := s.life / s.max_life
		tint := s.tint
		tint.a = u8(clamp(t, 0, 1) * 220)
		rl.DrawCircleV(s.pos, s.size * (0.4 + t * 0.6), tint)
	}
}
