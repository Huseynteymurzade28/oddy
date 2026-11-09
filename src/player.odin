package game

import "core:math"
import rl "../libs/raylib"

PLAYER_W :: 10
PLAYER_H :: 22

RUN_SPEED :: 128.0
GROUND_ACCEL :: 1500.0
AIR_ACCEL :: 1000.0
GROUND_FRICTION :: 1800.0
AIR_FRICTION :: 400.0
// Going faster than a run (after a dash or a super jump) bleeds off slowly in
// the air, so momentum is something you can carry and use.
AIR_OVERSPEED_DRAG :: 260.0
GRAVITY :: 950.0
FALL_GRAVITY :: 1.2 // gravity is a little stronger on the way down: jumps feel less floaty
// Near the top of a held jump gravity halves, which gives the apex a moment of
// hang time to line up a dash.
APEX_GRAVITY :: 0.5
APEX_WINDOW :: 40.0
MAX_FALL :: 430.0

// A jump clears 4.5 tiles and about 6 across at a run.
JUMP_VELOCITY :: 375.0
JUMP_CUT :: 0.5 // fraction of upward speed kept when jump is released early
MIN_JUMP_HOLD :: 0.08 // a tap shorter than this still gives a short hop, not nothing
COYOTE_TIME :: 0.1 // grace period for jumping after walking off a ledge
JUMP_BUFFER :: 0.12 // how early a jump press still counts on landing
LEDGE_ASSIST :: 9 // pixels: a jump that ends just short of a ledge is lifted onto it
CORNER_NUDGE :: 5 // pixels: a head that clips a corner slides past it instead

WALL_SLIDE_SPEED :: 62.0
WALL_JUMP_X :: 200.0
WALL_JUMP_Y :: 340.0
WALL_STICK_TIME :: 0.14 // how long a wall jump overrides the steering input
WALL_JUMP_REACH :: 3 // pixels: a wall this close still counts for a wall jump

// The dash: a fixed burst in one of eight directions, with gravity switched
// off for its length. One per time in the air, refilled by standing on
// ground. It covers about four tiles on its own.
DASH_SPEED :: 320.0
DASH_TIME :: 0.15
DASH_END_SPEED :: 180.0 // what is left of it afterwards
DASH_BUFFER :: 0.1
DASH_FREEZE :: 0.045 // the world stops for a beat when a dash starts
DASH_REFILL_DELAY :: 0.05 // a dash along the floor does not refill itself at once

// Jumping out of a dash that is touching the ground: a super jump from a
// sideways dash, a lower and longer hyper from a diagonal one down.
SUPER_X :: 260.0
HYPER_X :: 320.0
HYPER_Y_SCALE :: 0.55

DEATH_TIME :: 0.5 // from the hit to being back at the checkpoint
RESPAWN_TIME :: 0.3 // the pop of arriving back
FALL_DEATH_MARGIN :: 32.0 // how far under the level counts as fallen out of it

TRAIL_LEN :: 6
TRAIL_GAP :: 0.025

Afterimage :: struct {
	pos:   rl.Vector2,
	flip:  bool,
	anim:  ^Anim,
	frame: int,
	life:  f32,
}

Player :: struct {
	pos:          rl.Vector2, // at the feet, horizontally centred
	vel:          rl.Vector2,
	flip:         bool,
	grounded:     bool,
	coyote:       f32,
	jump_buffer:  f32,
	holding_jump: bool,
	jump_time:    f32, // since the last jump started
	wall_dir:     f32, // which side the wall is on while sliding: -1, 0 or +1
	wall_stick:   f32,

	dashes:       int, // dashes left before touching ground again
	dash_time:    f32, // > 0 while dashing
	dash_dir:     rl.Vector2,
	dash_buffer:  f32,
	since_dash:   f32,
	trail:        [TRAIL_LEN]Afterimage,
	trail_timer:  f32,
	flash:        f32, // the white flash when a dash comes back

	riding:       int, // the platform in `g.things` stood on, or -1

	dead:         bool,
	death_timer:  f32,
	respawn_time: f32,
	anim:         Animator,
}

player_init :: proc(p: ^Player, spawn: rl.Vector2) {
	p^ = Player {
		pos          = spawn,
		dashes       = 1,
		since_dash   = 1,
		respawn_time = RESPAWN_TIME,
		riding       = -1,
	}
}

player_rect :: proc(p: Player) -> rl.Rectangle {
	return {p.pos.x - PLAYER_W / 2, p.pos.y - PLAYER_H, PLAYER_W, PLAYER_H}
}

player_centre :: proc(p: Player) -> rl.Vector2 {
	return {p.pos.x, p.pos.y - PLAYER_H / 2}
}

@(private = "file")
approach :: proc(current, target, delta: f32) -> f32 {
	return current < target ? min(current + delta, target) : max(current - delta, target)
}

// Snaps whatever the stick or the keys say to one of eight directions. With no
// direction held, a dash goes the way you are facing.
@(private = "file")
dash_direction :: proc(p: ^Player, in_: Input) -> rl.Vector2 {
	d := rl.Vector2{in_.move, in_.move_y}
	if rl.Vector2Length(d) < 0.35 {
		return {p.flip ? -1 : 1, 0}
	}
	angle := math.round(math.atan2(d.y, d.x) / (math.PI / 4)) * (math.PI / 4)
	dir := rl.Vector2{math.cos(angle), math.sin(angle)}
	// Rounding leaves tiny leftovers on the zero axis.
	if abs(dir.x) < 0.01 {
		dir.x = 0
	}
	if abs(dir.y) < 0.01 {
		dir.y = 0
	}
	return dir
}

player_update :: proc(g: ^Game, dt: f32) {
	p := &g.player
	a := &g.assets
	m := &g.map_tiles

	trail_update(p, dt)
	p.flash = max(0, p.flash - dt)

	if p.dead {
		p.death_timer -= dt
		if p.death_timer <= 0 {
			player_respawn(g)
		}
		return
	}
	p.respawn_time = max(0, p.respawn_time - dt)

	// A platform you are standing on takes you with it.
	if p.riding >= 0 && p.riding < len(g.things) {
		p.pos += g.things[p.riding].delta
	}
	p.riding = -1

	in_ := g.input
	move := in_.move
	if abs(move) < 0.2 {
		move = 0
	} else {
		move = math.sign(move)
	}

	p.wall_stick = max(0, p.wall_stick - dt)
	p.since_dash += dt
	if in_.jump {
		p.jump_buffer = JUMP_BUFFER
	}
	if in_.dash {
		p.dash_buffer = DASH_BUFFER
	}
	p.jump_buffer = max(0, p.jump_buffer - dt)
	p.dash_buffer = max(0, p.dash_buffer - dt)
	p.coyote = max(0, p.coyote - dt)
	p.jump_time += dt

	if move != 0 && p.dash_time <= 0 && p.wall_stick <= 0 {
		p.flip = move < 0
	}

	r := player_rect(p^)

	// --- dash ----------------------------------------------------------------
	if p.dash_buffer > 0 && p.dashes > 0 && p.dash_time <= 0 {
		p.dash_buffer = 0
		p.dashes -= 1
		p.dash_dir = dash_direction(p, in_)
		p.dash_time = DASH_TIME
		p.since_dash = 0
		p.vel = p.dash_dir * DASH_SPEED
		p.holding_jump = false
		p.wall_stick = 0
		if p.dash_dir.x != 0 {
			p.flip = p.dash_dir.x < 0
		}
		g.freeze = DASH_FREEZE
		g.shake = max(g.shake, 2.5)
		spawn_burst(g, player_centre(p^), {200, 230, 255, 255}, 8, 90, 1.0)
		animator_restart(&p.anim, &a.player.double_jump)
		play(a, .Dash)
	}

	dashing := p.dash_time > 0
	if dashing {
		p.dash_time -= dt
		p.vel = p.dash_dir * DASH_SPEED
		if p.dash_time <= 0 {
			// Most of the speed goes when the dash ends; an upward dash keeps
			// less of its lift so it cannot be chained into a flight.
			p.vel = p.dash_dir * DASH_END_SPEED
			if p.dash_dir.y < 0 {
				p.vel.y *= 0.75
			}
		}
		p.trail_timer -= dt
		if p.trail_timer <= 0 {
			p.trail_timer = TRAIL_GAP
			trail_push(p)
		}
	}

	// --- horizontal ----------------------------------------------------------
	// A wall jump owns the horizontal velocity briefly; without that, holding
	// the stick back into the wall would cancel the push immediately.
	if !dashing && p.wall_stick <= 0 {
		target := move * RUN_SPEED
		switch {
		case !p.grounded && abs(p.vel.x) > RUN_SPEED && math.sign(p.vel.x) == move:
			p.vel.x = approach(p.vel.x, target, AIR_OVERSPEED_DRAG * dt)
		case move != 0:
			accel: f32 = p.grounded ? GROUND_ACCEL : AIR_ACCEL
			p.vel.x = approach(p.vel.x, target, accel * dt)
		case:
			friction: f32 = p.grounded ? GROUND_FRICTION : AIR_FRICTION
			p.vel.x = approach(p.vel.x, 0, friction * dt)
		}
	}

	// --- walls ---------------------------------------------------------------
	touching := wall_side(m, r)
	sliding := !dashing && !p.grounded && p.vel.y > 0 && touching != 0 && move == touching
	p.wall_dir = sliding ? touching : 0

	// --- jumping -------------------------------------------------------------
	if p.jump_buffer > 0 {
		near_wall := wall_side(m, grow_x(r, WALL_JUMP_REACH))
		switch {
		case dashing && (p.grounded || p.coyote > 0) && p.dash_dir.y >= 0 && p.dash_dir.x != 0:
			// Super (sideways dash) or hyper (diagonal down): the dash turns
			// into a long, fast jump and gives the dash straight back.
			p.dash_time = 0
			dashing = false
			p.vel.x = p.dash_dir.x * (p.dash_dir.y > 0 ? HYPER_X : SUPER_X)
			p.vel.y = -JUMP_VELOCITY * (p.dash_dir.y > 0 ? HYPER_Y_SCALE : 1)
			start_jump(p)
			p.dashes = 1
			spawn_burst(g, p.pos, {230, 240, 255, 255}, 6, 80, 1.0)
			play(a, .Jump)
		case !dashing && (p.grounded || p.coyote > 0):
			p.vel.y = -JUMP_VELOCITY
			start_jump(p)
			spawn_burst(g, p.pos, {200, 220, 190, 255}, 4, 50, 0.8)
			play(a, .Jump)
		case near_wall != 0 && !p.grounded:
			// A wall jump cancels a dash that is still running, so you can
			// dash into a wall and kick straight off it.
			p.dash_time = 0
			dashing = false
			p.vel = {-near_wall * WALL_JUMP_X, -WALL_JUMP_Y}
			p.wall_stick = WALL_STICK_TIME
			p.wall_dir = 0
			p.flip = near_wall > 0
			start_jump(p)
			spawn_burst(g, {p.pos.x + near_wall * PLAYER_W / 2, p.pos.y - PLAYER_H / 2}, {200, 220, 190, 255}, 4, 50, 0.8)
			play(a, .Jump)
		}
	}
	// Letting go early makes a short hop. On a touch screen every jump is a
	// full one: a thumb on glass cannot judge a few hundredths of a second.
	when !TOUCH_CONTROLS {
		if p.holding_jump && !in_.jump_held && p.jump_time >= MIN_JUMP_HOLD {
			if p.vel.y < 0 {
				p.vel.y *= JUMP_CUT
			}
			p.holding_jump = false
		}
	}
	if p.vel.y >= 0 {
		p.holding_jump = false
	}

	if !dashing {
		gravity: f32 = GRAVITY
		switch {
		case abs(p.vel.y) < APEX_WINDOW && in_.jump_held:
			gravity *= APEX_GRAVITY
		case p.vel.y > 0:
			gravity *= FALL_GRAVITY
		}
		p.vel.y = min(p.vel.y + gravity * dt, MAX_FALL)
		if p.wall_dir != 0 {
			p.vel.y = min(p.vel.y, WALL_SLIDE_SPEED)
		}
	}

	// --- move and collide ----------------------------------------------------
	wall_hit: bool
	before := r
	r, wall_hit = move_x(m, r, p.vel.x * dt)
	if wall_hit && !p.grounded && (dashing || (move != 0 && (move > 0) == (p.vel.x > 0))) {
		// Ledge assist: the feet came up just short of the top of the wall
		// being pushed into. Lift them over rather than slide back down.
		if lifted, ok := ledge_lift(m, before, p.vel.x * dt); ok {
			r = lifted
			wall_hit = false
			p.vel.y = min(p.vel.y, 0)
		}
	}
	if wall_hit {
		p.vel.x = 0
	}

	was_airborne := !p.grounded
	falling_speed := p.vel.y
	grounded, bumped_head: bool
	pre := r
	r, grounded, bumped_head = move_y(m, r, p.vel.y * dt, in_.down && !dashing)
	if !grounded && p.vel.y >= 0 && !in_.down {
		if top, index, ok := platform_landing(g, pre.y + PLAYER_H, r); ok {
			r.y = top - PLAYER_H
			grounded = true
			p.riding = index
			g.things[index].ridden = true
		}
	}
	if bumped_head {
		// Corner nudge: a head that only clipped the edge of a tile slides
		// sideways past it and the jump carries on.
		if nudged, ok := corner_nudge(m, pre, p.vel.y * dt, in_.down); ok {
			r = nudged
			bumped_head = false
		}
	}
	if grounded {
		if was_airborne && falling_speed > 220 {
			spawn_burst(g, {r.x + PLAYER_W / 2, r.y + PLAYER_H}, {200, 220, 190, 255}, 5, 70, 1.0)
		}
		p.vel.y = 0
		if dashing && p.dash_dir.x == 0 {
			// A dash straight down stops on the floor; a diagonal one turns
			// into a slide along it.
			p.dash_time = 0
			p.vel = {}
		}
	} else if p.vel.y >= 0 {
		// Nothing moved down this frame (a sideways dash has no gravity), so
		// ask for the ground directly.
		grounded = on_ground(m, r)
		if !grounded && !in_.down {
			probe := r
			probe.y += 1
			if _, index, ok := platform_landing(g, r.y + PLAYER_H, probe); ok {
				grounded = true
				p.riding = index
				g.things[index].ridden = true
			}
		}
	}
	if bumped_head {
		p.vel.y = 0
	}
	if grounded {
		p.coyote = COYOTE_TIME
	}
	p.grounded = grounded
	if p.grounded && p.since_dash > DASH_REFILL_DELAY && p.dashes < 1 && p.dash_time <= 0 {
		player_refill_dash(p)
	}
	p.pos = {r.x + PLAYER_W / 2, r.y + PLAYER_H}

	if tilemap_touches_hazard(m, player_rect(p^)) || p.pos.y > tilemap_bounds(m).y + FALL_DEATH_MARGIN {
		player_kill(g)
		return
	}

	// --- animation -----------------------------------------------------------
	body := &a.player.idle
	switch {
	case p.dash_time > 0:
		body = &a.player.double_jump
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
start_jump :: proc(p: ^Player) {
	p.grounded = false
	p.coyote = 0
	p.jump_buffer = 0
	p.holding_jump = true
	p.jump_time = 0
}

// Moving and falling platforms are one-way: they catch feet that were at or
// above their top before this frame's move, and nothing else.
@(private = "file")
platform_landing :: proc(g: ^Game, feet_before: f32, r: rl.Rectangle) -> (top: f32, index: int, ok: bool) {
	for t, i in g.things {
		pr, solid := platform_rect(t)
		if !solid || r.x >= pr.x + pr.width || r.x + r.width <= pr.x {
			continue
		}
		if feet_before <= pr.y + 1 + max(0, -t.delta.y) && r.y + r.height >= pr.y {
			return pr.y, i, true
		}
	}
	return 0, -1, false
}

// Thrown upward by something: a trampoline, or a creature underfoot. It is a
// full-height launch however jump is held, and the dash comes back with it.
player_bounce :: proc(g: ^Game, speed: f32) {
	p := &g.player
	p.vel.y = -speed
	p.dash_time = 0
	p.grounded = false
	p.coyote = 0
	p.holding_jump = false
	p.jump_buffer = 0
	p.riding = -1
	p.dashes = 0
	player_refill_dash(p)
	animator_restart(&p.anim, &g.assets.player.double_jump)
	spawn_burst(g, p.pos, {230, 240, 255, 255}, 6, 70, 1.0)
	play(&g.assets, .Jump)
}

// Gives the dash back, with a flash so you can see it happen.
player_refill_dash :: proc(p: ^Player) {
	if p.dashes >= 1 {
		return
	}
	p.dashes = 1
	p.flash = 0.12
}

@(private = "file")
grow_x :: proc(r: rl.Rectangle, by: f32) -> rl.Rectangle {
	return {r.x - by, r.y, r.width + by * 2, r.height}
}

@(private = "file")
corner_nudge :: proc(m: ^Tilemap, r: rl.Rectangle, dy: f32, down: bool) -> (rl.Rectangle, bool) {
	for off in 1 ..= CORNER_NUDGE {
		for side in ([2]f32{-1, 1}) {
			t := r
			t.x += f32(off) * side
			if tilemap_overlaps_solid(m, t) {
				continue
			}
			moved, _, bumped := move_y(m, t, dy, down)
			if !bumped {
				return moved, true
			}
		}
	}
	return r, false
}

@(private = "file")
ledge_lift :: proc(m: ^Tilemap, r: rl.Rectangle, dx: f32) -> (rl.Rectangle, bool) {
	for up in 1 ..= LEDGE_ASSIST {
		t := r
		t.y -= f32(up)
		if tilemap_overlaps_solid(m, t) {
			return r, false // a ceiling in the way
		}
		moved, hit := move_x(m, t, dx)
		if !hit {
			return moved, true
		}
	}
	return r, false
}

// --------------------------------------------------------------- the trail ---

@(private = "file")
trail_push :: proc(p: ^Player) {
	for i := TRAIL_LEN - 1; i > 0; i -= 1 {
		p.trail[i] = p.trail[i - 1]
	}
	p.trail[0] = {
		pos   = p.pos,
		flip  = p.flip,
		anim  = p.anim.anim,
		frame = p.anim.frame,
		life  = 0.22,
	}
}

@(private = "file")
trail_update :: proc(p: ^Player, dt: f32) {
	for &t in p.trail {
		t.life = max(0, t.life - dt)
	}
}

// ------------------------------------------------------------ life and death ---

// One hit is a death. The body bursts, and a moment later you are back at the
// last checkpoint you touched.
player_kill :: proc(g: ^Game) {
	p := &g.player
	if p.dead {
		return
	}
	p.dead = true
	p.death_timer = DEATH_TIME
	p.dash_time = 0
	g.deaths += 1
	g.shake = max(g.shake, 6)
	g.freeze = 0.06
	c := player_centre(p^)
	spawn_burst(g, c, {255, 255, 255, 255}, 18, 170, 1.6)
	spawn_burst(g, c, {255, 120, 120, 255}, 12, 110, 1.2)
	play(&g.assets, .Hurt)
}

@(private = "file")
player_respawn :: proc(g: ^Game) {
	level_reset_things(g)
	player_init(&g.player, g.respawn)
	spawn_burst(g, player_centre(g.player), {200, 230, 255, 255}, 12, 80, 1.0)
}

// While the dash is spent the body is tinted cooler, which is the only way to
// tell at a glance whether you still have it.
SPENT_TINT :: rl.Color{150, 170, 255, 255}
DASH_TRAIL_TINT :: rl.Color{120, 180, 255, 255}

player_draw :: proc(p: Player, a: ^Assets) {
	for t in p.trail {
		if t.life <= 0 || t.anim == nil {
			continue
		}
		c := DASH_TRAIL_TINT
		c.a = u8(170 * t.life / 0.22)
		anim_draw_frame(t.anim, t.frame, t.pos, t.flip, c)
	}
	if p.dead {
		return
	}
	tint := rl.WHITE
	if p.dashes == 0 {
		tint = SPENT_TINT
	}
	scale: f32 = 1
	if p.respawn_time > 0 {
		// Arriving back: a quick grow from nothing.
		k := 1 - p.respawn_time / RESPAWN_TIME
		scale = 0.4 + 0.6 * k
	}
	if p.anim.anim != nil {
		anim_draw_frame(p.anim.anim, p.anim.frame, p.pos, p.flip, tint, scale)
		if p.flash > 0 {
			rl.BeginBlendMode(.ADDITIVE)
			anim_draw_frame(p.anim.anim, p.anim.frame, p.pos, p.flip, {255, 255, 255, u8(p.flash / 0.12 * 200)}, scale)
			rl.EndBlendMode()
		}
	}
}
