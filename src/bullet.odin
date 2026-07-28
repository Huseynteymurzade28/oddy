package game

import "core:math"
import "core:math/rand"
import rl "vendor:raylib"

/*
Every shot is a sprite from `assets/sprites/bullets/`, sitting on a soft additive
glow in the weapon's colour so it stays readable against dark rock. One strip per
shot type holds the whole life of a round: the flash at the barrel, the shape in
flight, and the splash where it lands. The art is drawn pointing up, so putting
it on a heading means rotating by that heading plus a quarter turn.
*/

BULLET_RADIUS :: 1.6
EXPLOSION_RADIUS :: 26.0
SHOT_FRAME_TIME :: 0.045

Bullet_Art :: enum u8 {
	Pistol,
	Sniper,
	Shotgun,
	Laser,
}

@(private = "file")
Art_Info :: struct {
	flight:       int, // the frame drawn while the shot is in the air
	muzzle:       [2]int, // first and last frame of the flash at the barrel
	impact:       [2]int, // first and last frame of the splash where it lands
	flight_scale: f32,
	effect_scale: f32,
}

// Frame numbers picked by eye off the strips. The small calibres have no real
// flare to show, so their muzzle frame is just the round leaving the barrel; the
// shotgun and the laser both ship a proper flash on frame 1.
@(private = "file")
BULLET_ART := [Bullet_Art]Art_Info {
	.Pistol = {
		flight = 1,
		muzzle = {0, 0},
		impact = {4, 6},
		flight_scale = 1.00,
		effect_scale = 1.00,
	},
	.Sniper = {
		flight = 2,
		muzzle = {0, 0},
		impact = {4, 5},
		flight_scale = 0.85,
		effect_scale = 0.85,
	},
	.Shotgun = {
		flight = 2,
		muzzle = {1, 1},
		impact = {5, 6},
		flight_scale = 0.60,
		effect_scale = 0.65,
	},
	.Laser = {
		flight = 4,
		muzzle = {1, 1},
		impact = {5, 8},
		flight_scale = 0.75,
		effect_scale = 0.40,
	},
}

Bullet :: struct {
	pos:         rl.Vector2,
	vel:         rl.Vector2,
	damage:      f32,
	life:        f32,
	pierce:      int,
	explosive:   bool,
	knockback:   f32,
	art:         Bullet_Art,
	tint:        rl.Color,
	from_player: bool,
	last_hit:    int, // enemy index this shot already passed through
	dead:        bool,
}

// A one-shot run through part of a bullet strip: muzzle flashes and impacts.
Effect :: struct {
	art:   Bullet_Art,
	frame: int,
	last:  int,
	timer: f32,
	pos:   rl.Vector2,
	angle: f32, // degrees, already turned to face the heading
	scale: f32,
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

// The art points up, so a shot travelling along `heading` is the sprite turned a
// further quarter turn.
@(private = "file")
sprite_angle :: proc(heading: f32) -> f32 {
	return heading * math.DEG_PER_RAD + 90
}

@(private = "file")
spawn_effect :: proc(g: ^Game, art: Bullet_Art, frames: [2]int, pos: rl.Vector2, heading: f32) {
	append(
		&g.effects,
		Effect {
			art = art,
			frame = frames[0],
			last = frames[1],
			pos = pos,
			angle = sprite_angle(heading),
			scale = BULLET_ART[art].effect_scale,
		},
	)
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

// Fires one weapon. Called with the muzzle position so the tracer starts at the
// barrel rather than inside the player.
weapon_fire :: proc(g: ^Game, w: ^Weapon, origin: rl.Vector2, angle: f32) {
	art := weapon_art(w.class)

	for _ in 0 ..< max(1, w.pellets) {
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
				art = art,
				tint = w.tint,
				from_player = true,
				last_hit = -1,
			},
		)
	}

	spawn_effect(g, art, BULLET_ART[art].muzzle, origin, angle)
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
			art = .Shotgun,
			tint = tint,
			from_player = false,
			last_hit = -1,
		},
	)
}

// Ends a shot where it is, with the right splash for what it hit.
@(private = "file")
bullet_land :: proc(g: ^Game, b: ^Bullet) {
	b.dead = true
	if b.explosive {
		explode(g, b)
		return
	}
	heading := math.atan2(b.vel.y, b.vel.x)
	spawn_effect(g, b.art, BULLET_ART[b.art].impact, b.pos, heading)
	spawn_spark(g, b.pos, -rl.Vector2Normalize(b.vel), b.tint, 110, 1.3)
}

@(private = "file")
explode :: proc(g: ^Game, b: ^Bullet) {
	spawn_burst(g, b.pos, b.tint, 22, 240, 2.2)
	spawn_burst(g, b.pos, {255, 240, 190, 255}, 10, 150, 1.6)
	spawn_effect(g, b.art, BULLET_ART[b.art].impact, b.pos, math.atan2(b.vel.y, b.vel.x))
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
			bullet_land(g, &b)
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
					bullet_land(g, &b)
					break
				}
				push := rl.Vector2Normalize(b.vel) * b.knockback
				enemy_damage(g, i, b.damage, push)
				spawn_effect(
					g,
					b.art,
					BULLET_ART[b.art].impact,
					b.pos,
					math.atan2(b.vel.y, b.vel.x),
				)
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
				bullet_land(g, &b)
				if player_hurt(&g.player, &g.assets, b.pos.x) {
					g.shake = max(g.shake, 5)
				}
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

effects_update :: proc(g: ^Game, dt: f32) {
	live := 0
	for &e in g.effects {
		e.timer += dt
		for e.timer >= SHOT_FRAME_TIME {
			e.timer -= SHOT_FRAME_TIME
			e.frame += 1
		}
		if e.frame > e.last {
			continue
		}
		g.effects[live] = e
		live += 1
	}
	resize(&g.effects, live)
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

// ------------------------------------------------------------------ drawing ---

// A soft pool of the weapon's colour, so a shot stays visible over any tile.
@(private = "file")
draw_glow :: proc(pos: rl.Vector2, radius: f32, tint: rl.Color) {
	halo := tint
	halo.a = 44
	rl.DrawCircleV(pos, radius * 2.4, halo)
	halo.a = 78
	rl.DrawCircleV(pos, radius * 1.3, halo)
}

shots_draw :: proc(g: ^Game) {
	a := &g.assets

	rl.BeginBlendMode(.ADDITIVE)
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
	rl.EndBlendMode()

	// Cells are drawn from their centre, so the round is pushed back along its
	// heading to put its nose — rather than the middle of its trail — on the
	// point that actually collides.
	for b in g.bullets {
		info := BULLET_ART[b.art]
		sheet := &a.bullets[b.art]
		heading := math.atan2(b.vel.y, b.vel.x)
		back := sheet.frame_h * info.flight_scale * 0.5
		pos := b.pos - rl.Vector2{math.cos(heading), math.sin(heading)} * back
		anim_draw_rotated(
			sheet,
			info.flight,
			pos,
			sprite_angle(heading),
			rl.WHITE,
			info.flight_scale,
		)
	}

	for e in g.effects {
		anim_draw_rotated(&a.bullets[e.art], e.frame, e.pos, e.angle, rl.WHITE, e.scale)
	}
}
