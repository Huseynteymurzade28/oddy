package game

import rl "vendor:raylib"

PLAYER_W :: 8
PLAYER_H :: 13

RUN_SPEED :: 125.0
GROUND_ACCEL :: 1500.0
AIR_ACCEL :: 1000.0
GROUND_FRICTION :: 1800.0
AIR_FRICTION :: 350.0
GRAVITY :: 900.0
MAX_FALL :: 420.0
JUMP_VELOCITY :: 330.0
JUMP_CUT :: 0.45 // fraction of upward speed kept when jump is released early
COYOTE_TIME :: 0.10 // grace period for jumping after walking off a ledge
JUMP_BUFFER :: 0.12 // how early a jump press still counts on landing
STOMP_BOUNCE :: 250.0
INVULN_TIME :: 1.2
RESPAWN_DELAY :: 0.9
MAX_HEALTH :: 3

Player :: struct {
	pos:           rl.Vector2, // at the feet, horizontally centred
	vel:           rl.Vector2,
	flip:          bool,
	grounded:      bool,
	coyote:        f32,
	jump_buffer:   f32,
	holding_jump:  bool,
	health:        int,
	invuln:        f32,
	dead:          bool,
	respawn_timer: f32,
	spawn:         rl.Vector2,
	anim:          Animator,
}

player_init :: proc(p: ^Player, spawn: rl.Vector2) {
	p^ = Player {
		pos    = spawn,
		spawn  = spawn,
		health = MAX_HEALTH,
	}
}

player_rect :: proc(p: Player) -> rl.Rectangle {
	return {p.pos.x - PLAYER_W / 2, p.pos.y - PLAYER_H, PLAYER_W, PLAYER_H}
}

@(private = "file")
approach :: proc(current, target, delta: f32) -> f32 {
	return current < target ? min(current + delta, target) : max(current - delta, target)
}

player_update :: proc(p: ^Player, m: ^Tilemap, a: ^Assets, dt: f32) {
	if p.dead {
		p.respawn_timer -= dt
		return
	}
	if p.invuln > 0 {
		p.invuln -= dt
	}

	// --- input ---------------------------------------------------------------
	move: f32
	if rl.IsKeyDown(.LEFT) || rl.IsKeyDown(.A) {
		move -= 1
	}
	if rl.IsKeyDown(.RIGHT) || rl.IsKeyDown(.D) {
		move += 1
	}
	down := rl.IsKeyDown(.DOWN) || rl.IsKeyDown(.S)
	jump_pressed := rl.IsKeyPressed(.SPACE) || rl.IsKeyPressed(.UP) || rl.IsKeyPressed(.W)
	jump_held := rl.IsKeyDown(.SPACE) || rl.IsKeyDown(.UP) || rl.IsKeyDown(.W)

	if jump_pressed {
		p.jump_buffer = JUMP_BUFFER
	}
	p.jump_buffer = max(0, p.jump_buffer - dt)
	p.coyote = max(0, p.coyote - dt)

	// --- horizontal ----------------------------------------------------------
	if move != 0 {
		accel: f32 = p.grounded ? GROUND_ACCEL : AIR_ACCEL
		p.vel.x = approach(p.vel.x, move * RUN_SPEED, accel * dt)
		p.flip = move < 0
	} else {
		friction: f32 = p.grounded ? GROUND_FRICTION : AIR_FRICTION
		p.vel.x = approach(p.vel.x, 0, friction * dt)
	}

	// --- jump ----------------------------------------------------------------
	if p.jump_buffer > 0 && (p.grounded || p.coyote > 0) {
		p.vel.y = -JUMP_VELOCITY
		p.grounded = false
		p.coyote = 0
		p.jump_buffer = 0
		p.holding_jump = true
		play(a, .Jump)
	}
	if p.holding_jump && !jump_held {
		if p.vel.y < 0 {
			p.vel.y *= JUMP_CUT
		}
		p.holding_jump = false
	}
	if p.vel.y >= 0 {
		p.holding_jump = false
	}

	p.vel.y = min(p.vel.y + GRAVITY * dt, MAX_FALL)

	// --- move and collide ----------------------------------------------------
	r := player_rect(p^)
	wall_hit: bool
	r, wall_hit = move_x(m, r, p.vel.x * dt)
	if wall_hit {
		p.vel.x = 0
	}

	was_airborne := !p.grounded
	falling_speed := p.vel.y
	grounded, bumped_head: bool
	r, grounded, bumped_head = move_y(m, r, p.vel.y * dt, down)
	if grounded {
		if was_airborne && falling_speed > 200 {
			play(a, .Tap)
		}
		p.vel.y = 0
		p.coyote = COYOTE_TIME
	}
	if bumped_head {
		p.vel.y = 0
	}
	p.grounded = grounded
	p.pos = {r.x + PLAYER_W / 2, r.y + PLAYER_H}

	if tilemap_touches_hazard(m, player_rect(p^)) {
		player_kill(p, a)
	}

	// --- animation -----------------------------------------------------------
	switch {
	case !p.grounded && p.vel.y < 0:
		animator_play(&p.anim, &a.player_run, CLIP_PLAYER_JUMP)
	case !p.grounded:
		animator_play(&p.anim, &a.player_run, CLIP_PLAYER_FALL)
	case abs(p.vel.x) > 5:
		animator_play(&p.anim, &a.player_run, CLIP_PLAYER_RUN)
	case:
		animator_play(&p.anim, &a.player_idle, CLIP_PLAYER_IDLE)
	}
	animator_update(&p.anim, dt)
}

player_hurt :: proc(p: ^Player, a: ^Assets, source_x: f32) -> bool {
	if p.dead || p.invuln > 0 {
		return false
	}
	p.health -= 1
	p.invuln = INVULN_TIME
	p.vel.y = -170
	p.vel.x = p.pos.x < source_x ? -130 : 130
	if p.health <= 0 {
		player_kill(p, a)
	} else {
		play(a, .Hurt)
	}
	return true
}

player_kill :: proc(p: ^Player, a: ^Assets) {
	if p.dead {
		return
	}
	p.dead = true
	p.health = 0
	p.respawn_timer = RESPAWN_DELAY
	play(a, .Hurt)
}

player_respawn :: proc(p: ^Player) {
	p.pos = p.spawn
	p.vel = {}
	p.health = MAX_HEALTH
	p.dead = false
	p.invuln = INVULN_TIME
	p.grounded = false
	p.holding_jump = false
}

player_heal :: proc(p: ^Player) -> bool {
	if p.health >= MAX_HEALTH {
		return false
	}
	p.health += 1
	return true
}

player_draw :: proc(p: Player, a: ^Assets) {
	if p.dead {
		return
	}
	tint := rl.WHITE
	// Blink while the invulnerability window is open.
	if p.invuln > 0 && int(p.invuln * 20) % 2 == 0 {
		tint = {255, 255, 255, 80}
	}
	animator_draw(p.anim, p.pos, p.flip, tint)
}
