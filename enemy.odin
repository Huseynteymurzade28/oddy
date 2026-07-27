package game

import rl "vendor:raylib"

ENEMY_W :: 14
ENEMY_H :: 10
ENEMY_DEATH_TIME :: 0.28

Enemy_Kind :: enum {
	Green,
	Purple,
}

Enemy :: struct {
	pos:    rl.Vector2, // at the feet, horizontally centred
	vel:    rl.Vector2,
	dir:    f32, // -1 or +1
	kind:   Enemy_Kind,
	alive:  bool,
	dying:  f32,
	spawn:  rl.Vector2,
	anim:   Animator,
}

enemy_speed :: proc(k: Enemy_Kind) -> f32 {
	return k == .Green ? 24 : 44
}

enemy_make :: proc(kind: Enemy_Kind, spawn: rl.Vector2) -> Enemy {
	return {kind = kind, pos = spawn, spawn = spawn, dir = -1, alive = true}
}

enemy_rect :: proc(e: Enemy) -> rl.Rectangle {
	return {e.pos.x - ENEMY_W / 2, e.pos.y - ENEMY_H, ENEMY_W, ENEMY_H}
}

enemy_reset :: proc(e: ^Enemy) {
	e.pos = e.spawn
	e.vel = {}
	e.dir = -1
	e.alive = true
	e.dying = 0
}

enemy_update :: proc(e: ^Enemy, m: ^Tilemap, a: ^Assets, dt: f32) {
	if !e.alive {
		if e.dying > 0 {
			e.dying -= dt
			animator_update(&e.anim, dt)
		}
		return
	}

	e.vel.x = e.dir * enemy_speed(e.kind)
	e.vel.y = min(e.vel.y + GRAVITY * dt, MAX_FALL)

	r := enemy_rect(e^)
	wall_hit: bool
	r, wall_hit = move_x(m, r, e.vel.x * dt)
	if wall_hit {
		e.dir = -e.dir
	}

	grounded: bool
	r, grounded, _ = move_y(m, r, e.vel.y * dt)
	if grounded {
		e.vel.y = 0
	}
	e.pos = {r.x + ENEMY_W / 2, r.y + ENEMY_H}

	// Slimes patrol: they turn around at a ledge or at the edge of a hazard
	// rather than walking into it.
	if grounded {
		probe := rl.Rectangle {
			e.pos.x + e.dir * (ENEMY_W / 2 + 1) - 1,
			e.pos.y - ENEMY_H,
			2,
			ENEMY_H + 2,
		}
		if !on_ground(m, probe) || tilemap_touches_hazard(m, probe) {
			e.dir = -e.dir
		}
	}

	animator_play(&e.anim, &a.slime[e.kind], CLIP_SLIME_WALK)
	animator_update(&e.anim, dt)
}

enemy_squash :: proc(e: ^Enemy, a: ^Assets) {
	if !e.alive {
		return
	}
	e.alive = false
	e.dying = ENEMY_DEATH_TIME
	e.anim.sheet = &a.slime[e.kind]
	e.anim.clip = CLIP_SLIME_DIE
	e.anim.frame = 0
	e.anim.timer = 0
	e.anim.finished = false
	play(a, .Stomp)
}

enemy_draw :: proc(e: Enemy) {
	if !e.alive && e.dying <= 0 {
		return
	}
	tint := rl.WHITE
	if !e.alive {
		// Fade out over the squash animation.
		tint.a = u8(clamp(e.dying / ENEMY_DEATH_TIME, 0, 1) * 255)
	}
	animator_draw(e.anim, e.pos, e.dir > 0, tint)
}
