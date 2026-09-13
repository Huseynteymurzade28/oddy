package game

import "core:math"
import rl "vendor:raylib"

PLAYER_W :: 10
PLAYER_H :: 22

RUN_SPEED :: 128.0
GROUND_ACCEL :: 1500.0
AIR_ACCEL :: 1000.0
GROUND_FRICTION :: 1800.0
AIR_FRICTION :: 400.0
GRAVITY :: 900.0
MAX_FALL :: 430.0

JUMP_VELOCITY :: 305.0
DOUBLE_JUMP_VELOCITY :: 275.0
JUMP_CUT :: 0.45 // fraction of upward speed kept when jump is released early
COYOTE_TIME :: 0.10 // grace period for jumping after walking off a ledge
JUMP_BUFFER :: 0.12 // how early a jump press still counts on landing

WALL_SLIDE_SPEED :: 62.0
WALL_JUMP_X :: 210.0
WALL_JUMP_Y :: 300.0
WALL_STICK_TIME :: 0.16 // how long a wall jump overrides the steering input

INVULN_TIME :: 1.1
DEATH_DELAY :: 1.4
MAX_HEALTH :: 5
// The shop can sell extra hearts, but only so many: past this the row of them
// would run into the coin counter under it.
HEALTH_CAP :: 8

Player :: struct {
	pos:          rl.Vector2, // at the feet, horizontally centred
	vel:          rl.Vector2,
	flip:         bool,
	grounded:     bool,
	coyote:       f32,
	jump_buffer:  f32,
	holding_jump: bool,
	air_jumps:    int, // mid-air jumps still available
	wall_dir:     f32, // which side the wall is on while sliding: -1, 0 or +1
	wall_stick:   f32,
	invuln:       f32,
	health:       int,
	max_health:   int, // starts at MAX_HEALTH; the shop can raise it
	dead:         bool,
	death_timer:  f32,
	anim:         Animator,

	// combat
	aim:          f32, // radians, world space
	weapon:       Weapon,
	fire_cd:      f32,
	fire_rate:    f32, // a multiplier the shop can buy up, 1 by default

	// run progress
	has_key:      bool,
	coins:        int,
	kills:        int,
}

player_init :: proc(p: ^Player, spawn: rl.Vector2) {
	p^ = Player {
		pos        = spawn,
		health     = MAX_HEALTH,
		max_health = MAX_HEALTH,
		fire_rate  = 1,
		weapon     = weapon_starter(),
	}
}

player_rect :: proc(p: Player) -> rl.Rectangle {
	return {p.pos.x - PLAYER_W / 2, p.pos.y - PLAYER_H, PLAYER_W, PLAYER_H}
}

player_centre :: proc(p: Player) -> rl.Vector2 {
	return {p.pos.x, p.pos.y - PLAYER_H / 2}
}

// Where the gun is held, just in front of the chest.
player_hand :: proc(p: Player) -> rl.Vector2 {
	return {p.pos.x + (p.flip ? -2 : 2), p.pos.y - 13}
}

@(private = "file")
approach :: proc(current, target, delta: f32) -> f32 {
	return current < target ? min(current + delta, target) : max(current - delta, target)
}

player_update :: proc(g: ^Game, dt: f32) {
	p := &g.player
	a := &g.assets
	m := &g.map_tiles

	if p.dead {
		p.death_timer -= dt
		animator_update(&p.anim, dt)
		return
	}

	p.invuln = max(0, p.invuln - dt)
	p.fire_cd = max(0, p.fire_cd - dt)
	p.wall_stick = max(0, p.wall_stick - dt)

	// --- aim -----------------------------------------------------------------
	target := rl.GetScreenToWorld2D(rl.GetMousePosition(), g.camera)
	to_target := target - player_hand(p^)
	if rl.Vector2LengthSqr(to_target) > 0.01 {
		p.aim = math.atan2(to_target.y, to_target.x)
	}
	p.flip = math.cos(p.aim) < 0

	// --- input ---------------------------------------------------------------
	move: f32
	if rl.IsKeyDown(.A) || rl.IsKeyDown(.LEFT) {
		move -= 1
	}
	if rl.IsKeyDown(.D) || rl.IsKeyDown(.RIGHT) {
		move += 1
	}
	down := rl.IsKeyDown(.S) || rl.IsKeyDown(.DOWN)
	jump_pressed := rl.IsKeyPressed(.SPACE) || rl.IsKeyPressed(.W) || rl.IsKeyPressed(.UP)
	jump_held := rl.IsKeyDown(.SPACE) || rl.IsKeyDown(.W) || rl.IsKeyDown(.UP)

	if jump_pressed {
		p.jump_buffer = JUMP_BUFFER
	}
	p.jump_buffer = max(0, p.jump_buffer - dt)
	p.coyote = max(0, p.coyote - dt)

	// --- horizontal ----------------------------------------------------------
	// A wall jump owns the horizontal velocity briefly; without that, holding
	// the stick back into the wall would cancel the push immediately.
	if p.wall_stick <= 0 {
		if move != 0 {
			accel: f32 = p.grounded ? GROUND_ACCEL : AIR_ACCEL
			p.vel.x = approach(p.vel.x, move * RUN_SPEED, accel * dt)
		} else {
			friction: f32 = p.grounded ? GROUND_FRICTION : AIR_FRICTION
			p.vel.x = approach(p.vel.x, 0, friction * dt)
		}
	}

	// --- walls ---------------------------------------------------------------
	r := player_rect(p^)
	touching := wall_side(m, r)
	sliding := !p.grounded && p.vel.y > 0 && touching != 0 && move == touching
	p.wall_dir = sliding ? touching : 0

	// --- jumping -------------------------------------------------------------
	if p.jump_buffer > 0 {
		switch {
		case p.grounded || p.coyote > 0:
			p.vel.y = -JUMP_VELOCITY
			p.grounded = false
			p.coyote = 0
			p.jump_buffer = 0
			p.holding_jump = true
			p.air_jumps = 1
			play(a, .Jump)
		case p.wall_dir != 0:
			p.vel = {-p.wall_dir * WALL_JUMP_X, -WALL_JUMP_Y}
			p.wall_stick = WALL_STICK_TIME
			p.wall_dir = 0
			p.jump_buffer = 0
			p.holding_jump = true
			p.air_jumps = 1
			animator_restart(&p.anim, &a.player.double_jump)
			play(a, .Jump)
		case p.air_jumps > 0:
			p.air_jumps -= 1
			p.vel.y = -DOUBLE_JUMP_VELOCITY
			p.jump_buffer = 0
			p.holding_jump = true
			animator_restart(&p.anim, &a.player.double_jump)
			play(a, .Jump)
		}
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
	if p.wall_dir != 0 {
		p.vel.y = min(p.vel.y, WALL_SLIDE_SPEED)
	}

	// --- move and collide ----------------------------------------------------
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
		if was_airborne && falling_speed > 220 {
			spawn_burst(g, {r.x + PLAYER_W / 2, r.y + PLAYER_H}, {200, 220, 190, 255}, 5, 70, 1.0)
		}
		p.vel.y = 0
		p.coyote = COYOTE_TIME
		p.air_jumps = 1
	}
	if bumped_head {
		p.vel.y = 0
	}
	p.grounded = grounded
	p.pos = {r.x + PLAYER_W / 2, r.y + PLAYER_H}

	if tilemap_touches_hazard(m, player_rect(p^)) {
		player_kill(p, a)
	}

	// --- shooting ------------------------------------------------------------
	if rl.IsMouseButtonDown(.LEFT) && p.fire_cd <= 0 {
		player_shoot(g)
	}

	// --- animation -----------------------------------------------------------
	body := &a.player.idle
	switch {
	case p.invuln > INVULN_TIME - 0.35:
		body = &a.player.hit
	case p.wall_dir != 0:
		body = &a.player.wall_slide
	case !p.grounded && p.anim.anim == &a.player.double_jump && !p.anim.finished:
		body = &a.player.double_jump
	case !p.grounded && p.vel.y < 0:
		body = &a.player.jump
	case !p.grounded:
		body = &a.player.fall
	case abs(p.vel.x) > 6:
		body = &a.player.run
	}
	animator_play(&p.anim, body)
	animator_update(&p.anim, dt)
}

@(private = "file")
player_shoot :: proc(g: ^Game) {
	p := &g.player
	w := &p.weapon

	if !w.infinite && w.ammo <= 0 {
		player_drop_to_sidearm(g)
		return
	}

	hand := player_hand(p^)
	weapon_fire(g, w, weapon_muzzle(w^, hand, p.aim), p.aim)
	p.fire_cd = w.fire_time / max(p.fire_rate, 0.1)
	if !w.infinite {
		w.ammo -= 1
	}

	// A little push back, so heavy guns are felt in the movement too.
	recoil := w.knockback * f32(max(1, w.pellets)) * 0.09
	p.vel.x -= math.cos(p.aim) * recoil
	if !p.grounded {
		p.vel.y -= math.sin(p.aim) * recoil * 0.35
	}

	if !w.infinite && w.ammo <= 0 {
		player_drop_to_sidearm(g)
	}
}

// An empty gun is thrown away and the trusty pistol comes back out, so a run can
// never stall on a weapon that cannot shoot.
player_drop_to_sidearm :: proc(g: ^Game) {
	g.player.weapon = weapon_starter()
	g.notice = "OUT OF AMMO - SIDEARM READY"
	g.notice_timer = 2.2
}

player_take_weapon :: proc(g: ^Game, w: Weapon) {
	g.player.weapon = w
	g.player.fire_cd = 0
	g.notice = ""
	g.notice_timer = 2.6
	play(&g.assets, .Power_Up)
}

player_hurt :: proc(p: ^Player, a: ^Assets, source_x: f32) -> bool {
	if p.dead || p.invuln > 0 {
		return false
	}
	p.health -= 1
	p.invuln = INVULN_TIME
	p.vel.y = -180
	p.vel.x = p.pos.x < source_x ? -140 : 140
	if p.health <= 0 {
		player_kill(p, a)
	} else {
		animator_restart(&p.anim, &a.player.hit)
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
	p.death_timer = DEATH_DELAY
	animator_restart(&p.anim, &a.player.hit)
	play(a, .Hurt)
}

player_heal :: proc(p: ^Player, amount := 1) -> bool {
	if p.health >= p.max_health {
		return false
	}
	p.health = min(p.max_health, p.health + amount)
	return true
}

// Buying a heart container raises the ceiling and fills the new slot, so the
// purchase is felt immediately rather than only after finding a rune.
player_add_heart :: proc(p: ^Player) -> bool {
	if p.max_health >= HEALTH_CAP {
		return false
	}
	p.max_health += 1
	p.health += 1
	return true
}

player_draw :: proc(p: Player, a: ^Assets) {
	tint := rl.WHITE
	if p.invuln > 0 && !p.dead && int(p.invuln * 20) % 2 == 0 {
		tint = {255, 255, 255, 90}
	}
	if p.dead {
		tint = {255, 140, 140, 200}
	}
	animator_draw(p.anim, p.pos, p.flip, tint)
	if !p.dead {
		weapon_draw(p.weapon, a, player_hand(p), p.aim)
	}
}
