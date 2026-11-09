package game

import "core:math"
import rl "../libs/raylib"

/*
Traps and moving pieces. Each is placed in LDtk as an entity whose name is
one of `Thing_Kind`; its rectangle there is what it is read from:

  Saw               a spinning blade riding up and down a track. The
                    rectangle is the track: the saw runs along its long side,
                    end to end (a one-cell track is a saw that stays put).
                    Field `Speed`.
  Moving_Platform   a platform you can stand on, riding a track the same way.
                    Field `Speed`.
  Falling_Platform  shakes once stood on, then drops. Comes back later.
  Trampoline        bounces you high and gives the dash back.
  Fan               blows you up. The rectangle's height is how far it reaches.
  Fire              a block in the floor that lights a moment after you step
                    on it. Placed over the floor tile, flame above it.
  Arrow_Shooter     fires arrows along `Dir` every `Interval` seconds, the first
                    after `Delay`. They fly about eighteen tiles.
  Refill            a balloon that gives the dash back when it is spent, then
                    grows back.
  Spike_Head        drops on you when you are under it, then climbs back.
  Geyser            bubbles for a moment, then erupts: stand on it then and
                    it throws you high. The rectangle's height is its reach.

The creatures (`Pig` and on) are read the same way; see `enemy.odin`.

Everything here is put back as it started whenever you die, so a section
always plays the same way from its checkpoint.
*/

Thing_Kind :: enum u8 {
	Saw,
	Moving_Platform,
	Falling_Platform,
	Trampoline,
	Fan,
	Fire,
	Arrow_Shooter,
	Refill,
	Spike_Head,
	Geyser,
	// creatures, in the same order as `Enemy_Kind`
	Pig,
	Slime,
	Rino,
	Bat,
	Bee,
}

FIRST_CREATURE :: Thing_Kind.Pig

SAW_RADIUS :: 14.0
PLATFORM_W :: 32.0
PLATFORM_H :: 8.0
FALL_SHAKE :: 0.45 // from being stood on to dropping
FALL_RESPAWN :: 2.5
TRAMPOLINE_VELOCITY :: 560.0
FAN_ACCEL :: 2300.0
FAN_MAX_RISE :: 230.0
FIRE_WARN :: 0.4
FIRE_BURN :: 1.0
FIRE_REST :: 0.6
ARROW_SPEED :: 170.0
// Arrows fall away after about eighteen tiles: one that flew on until it hit
// rock could cross half a level and kill you before you ever saw it.
ARROW_RANGE :: 18 * TILE
REFILL_RESPAWN :: 2.5
GEYSER_REST :: 1.4
GEYSER_WARN :: 0.6
GEYSER_BLOW :: 1.0
GEYSER_LAUNCH :: 470.0
HEAD_SIZE :: 34.0 // the spiked block's hitbox, a little inside its spikes
HEAD_FALL_ACCEL :: 1500.0
HEAD_MAX_FALL :: 520.0
HEAD_RISE :: 60.0
HEAD_REST :: 0.7
HEAD_WARN :: 0.2 // it shudders this long before it drops: enough to run on, not to stop

Thing :: struct {
	kind:   Thing_Kind,
	data:   Thing_Data,
	pos:    rl.Vector2, // what this is depends on the kind; see `thing_rect`
	vel:    rl.Vector2,
	delta:  rl.Vector2, // how far it moved this frame, to carry a rider
	t:      f32, // place along a track, 0..1
	dir:    f32, // which way along it
	state:  int,
	timer:  f32,
	anim:   Animator,
	ridden: bool, // the player stood on it this frame
}

Arrow :: struct {
	pos:  rl.Vector2,
	vel:  rl.Vector2,
	life: f32,
}

// ------------------------------------------------------------------ setup ---

thing_make :: proc(d: Thing_Data) -> Thing {
	t := Thing {
		kind = d.kind,
		data = d,
		dir  = 1,
	}
	r := d.rect
	switch d.kind {
	case .Saw, .Moving_Platform:
		t.pos = track_point(t)
	case .Falling_Platform:
		t.pos = {r.x, r.y}
	case .Trampoline, .Fire:
		t.pos = {r.x + r.width / 2, r.y + r.height} // bottom centre
	case .Geyser:
		t.pos = {r.x + r.width / 2, r.y + r.height}
		t.timer = d.delay
	case .Fan:
		t.pos = {r.x + r.width / 2, r.y + r.height}
	case .Arrow_Shooter, .Refill, .Spike_Head:
		t.pos = {r.x + r.width / 2, r.y + r.height / 2}
		t.timer = d.delay
	case .Pig, .Slime, .Rino, .Bat, .Bee:
	}
	return t
}

// Where along its track a saw or a platform is: the track's long axis, inset
// by half the thing so it never pokes past the end.
@(private = "file")
track_point :: proc(t: Thing) -> rl.Vector2 {
	r := t.data.rect
	inset: f32 = t.kind == .Saw ? TILE / 2 : PLATFORM_W / 2
	c := rl.Vector2{r.x + r.width / 2, r.y + r.height / 2}
	if r.width >= r.height {
		a := r.x + min(inset, r.width / 2)
		b := r.x + r.width - min(inset, r.width / 2)
		return {a + (b - a) * ease(t.t), c.y}
	}
	a := r.y + min(inset, r.height / 2)
	b := r.y + r.height - min(inset, r.height / 2)
	return {c.x, a + (b - a) * ease(t.t)}
}

@(private = "file")
track_length :: proc(t: Thing) -> f32 {
	r := t.data.rect
	inset: f32 = t.kind == .Saw ? TILE : PLATFORM_W
	return max(max(r.width, r.height) - inset, 1)
}

// Slows a little into each end, so a platform does not jerk you off it.
@(private = "file")
ease :: proc(x: f32) -> f32 {
	return x * x * (3 - 2 * x) * 0.35 + x * 0.65
}

// The rectangle that is solid to stand on, for things you can ride.
platform_rect :: proc(t: Thing) -> (rl.Rectangle, bool) {
	#partial switch t.kind {
	case .Moving_Platform:
		return {t.pos.x - PLATFORM_W / 2, t.pos.y - PLATFORM_H / 2, PLATFORM_W, PLATFORM_H}, true
	case .Falling_Platform:
		if t.state == 3 {
			return {}, false // gone, waiting to come back
		}
		return {t.pos.x, t.pos.y, 32, 10}, true
	}
	return {}, false
}

// ----------------------------------------------------------------- update ---

things_update :: proc(g: ^Game, dt: f32) {
	p := &g.player
	pr := player_rect(p^)
	for &t in g.things {
		before := t.pos
		switch t.kind {
		case .Saw, .Moving_Platform:
			if t.data.rect.width > TILE * 1.5 || t.data.rect.height > TILE * 1.5 {
				t.t += t.dir * t.data.speed / track_length(t) * dt
				if t.t >= 1 || t.t <= 0 {
					t.t = clamp(t.t, 0, 1)
					t.dir = -t.dir
				}
				t.pos = track_point(t)
			}
			if t.kind == .Saw && !p.dead && circle_hits(t.pos, SAW_RADIUS - 3, pr) {
				player_kill(g)
			}

		case .Falling_Platform:
			switch t.state {
			case 0:
				if t.ridden {
					t.state = 1
					t.timer = FALL_SHAKE
				}
			case 1:
				t.timer -= dt
				if t.timer <= 0 {
					t.state = 2
					t.vel = {}
				}
			case 2:
				t.vel.y = min(t.vel.y + GRAVITY * 0.8 * dt, MAX_FALL)
				t.pos.y += t.vel.y * dt
				if t.pos.y > tilemap_bounds(&g.map_tiles).y + 32 {
					t.state = 3
					t.timer = FALL_RESPAWN
				}
			case 3:
				t.timer -= dt
				if t.timer <= 0 {
					t.state = 0
					t.pos = {t.data.rect.x, t.data.rect.y}
					t.timer = 0.3 // fades back in
				}
			}

		case .Trampoline:
			// Touching the pad at all launches you: running into a trampoline
			// is as good as landing on it.
			pad := rl.Rectangle{t.pos.x - 10, t.pos.y - 11, 20, 11}
			if !p.dead && p.vel.y >= 0 && rl.CheckCollisionRecs(pr, pad) {
				player_bounce(g, TRAMPOLINE_VELOCITY)
				animator_restart(&t.anim, &g.assets.traps.trampoline_jump)
			}

		case .Fan:
			column := fan_rect(t)
			if !p.dead && p.dash_time <= 0 && rl.CheckCollisionRecs(pr, column) {
				// Strongest at the bottom, fading toward the top of its reach.
				k := clamp((t.pos.y - p.pos.y) / max(column.height, 1), 0, 1)
				p.vel.y = max(p.vel.y - FAN_ACCEL * (1.2 - k) * dt, -FAN_MAX_RISE)
				p.coyote = 0
			}

		case .Fire:
			base := rl.Rectangle{t.pos.x - 8, t.pos.y - 16, 16, 16}
			flame := rl.Rectangle{t.pos.x - 5, t.pos.y - 29, 10, 13}
			standing := p.grounded && !p.dead && abs(p.pos.y - base.y) < 2 &&
				pr.x < base.x + base.width && pr.x + pr.width > base.x
			t.timer -= dt
			switch t.state {
			case 0:
				if standing && t.timer <= 0 {
					t.state = 1
					t.timer = FIRE_WARN
				}
			case 1:
				if t.timer <= 0 {
					t.state = 2
					t.timer = FIRE_BURN
				}
			case 2:
				if !p.dead && rl.CheckCollisionRecs(pr, flame) {
					player_kill(g)
				}
				if t.timer <= 0 {
					t.state = 0
					t.timer = FIRE_REST
				}
			}

		case .Arrow_Shooter:
			t.timer -= dt
			if t.timer <= 0 {
				t.timer += t.data.interval
				d := rl.Vector2{f32(t.data.dir.x), f32(t.data.dir.y)}
				append(&g.arrows, Arrow{pos = t.pos + d * 8, vel = d * ARROW_SPEED, life = ARROW_RANGE / ARROW_SPEED})
				if near_player(g, t.pos) {
					play(&g.assets, .Arrow)
				}
			}

		case .Refill:
			switch t.state {
			case 0:
				if !p.dead && p.dashes == 0 && circle_hits(t.pos, 9, pr) {
					player_refill_dash(p)
					t.state = 1
					t.timer = REFILL_RESPAWN
					animator_restart(&t.anim, &g.assets.traps.refill_pop)
					spawn_burst(g, t.pos, {255, 240, 200, 255}, 10, 90, 1.1)
					play(&g.assets, .Refill)
				}
			case 1:
				t.timer -= dt
				if t.timer <= 0 {
					t.state = 0
					spawn_burst(g, t.pos, {200, 230, 255, 255}, 6, 40, 0.8)
				}
			}

		case .Spike_Head:
			spike_head_update(g, &t, dt)

		case .Geyser:
			t.timer -= dt
			switch t.state {
			case 0:
				if t.timer <= 0 {
					t.state = 1
					t.timer = GEYSER_WARN
				}
			case 1:
				if int(g.time * 30) % 3 == 0 {
					spawn_spark(g, t.pos + {f32(int(g.time * 97) % 9) - 4, -2}, {0, -1}, {255, 200, 120, 255}, 50, 1)
				}
				if t.timer <= 0 {
					t.state = 2
					t.timer = GEYSER_BLOW
					if rl.Vector2Distance(t.pos, p.pos) < view_size().x * 0.7 {
						play(&g.assets, .Bounce)
					}
				}
			case 2:
				column := rl.Rectangle{t.pos.x - 9, t.pos.y - geyser_reach(t), 18, geyser_reach(t)}
				if !p.dead && p.dash_time <= 0 && rl.CheckCollisionRecs(pr, column) && p.vel.y > -GEYSER_LAUNCH * 0.8 {
					player_bounce(g, GEYSER_LAUNCH)
				}
				if t.timer <= 0 {
					t.state = 0
					t.timer = GEYSER_REST
				}
			}

		case .Pig, .Slime, .Rino, .Bat, .Bee:
		}
		t.delta = t.pos - before
		t.ridden = false
		animator_update(&t.anim, dt)
	}

	arrows_update(g, dt)
}

@(private = "file")
spike_head_update :: proc(g: ^Game, t: ^Thing, dt: f32) {
	p := &g.player
	m := &g.map_tiles
	home := rl.Vector2{t.data.rect.x + t.data.rect.width / 2, t.data.rect.y + t.data.rect.height / 2}
	switch t.state {
	case 0: // waiting, blinking now and then
		t.timer -= dt
		if t.timer <= 0 {
			animator_restart(&t.anim, &g.assets.traps.spike_head_blink)
			t.timer = 2 + f32(int(t.pos.x) % 3)
		}
		below := p.pos.y > t.pos.y && abs(p.pos.x - t.pos.x) < HEAD_SIZE / 2
		if !p.dead && below && clear_column(m, t.pos, p.pos.y) {
			t.state = 4
			t.timer = HEAD_WARN
			t.vel = {}
		}
	case 4: // shuddering
		if t.timer <= 0 {
			t.state = 1
		}
	case 1: // falling
		t.vel.y = min(t.vel.y + HEAD_FALL_ACCEL * dt, HEAD_MAX_FALL)
		r := head_rect(t^)
		moved, landed, _ := move_y(m, r, t.vel.y * dt)
		t.pos.y = moved.y + HEAD_SIZE / 2
		if landed {
			t.state = 2
			t.timer = HEAD_REST
			g.shake = max(g.shake, 4)
			if near_player(g, t.pos) {
				play(&g.assets, .Slam)
			}
			animator_restart(&t.anim, &g.assets.traps.spike_head_hit)
			spawn_burst(g, {t.pos.x, t.pos.y + HEAD_SIZE / 2}, {200, 190, 170, 255}, 10, 80, 1.0)
		}
		if t.pos.y > tilemap_bounds(m).y + 64 {
			t.state = 3
		}
	case 2: // resting where it landed
		t.timer -= dt
		if t.timer <= 0 {
			t.state = 3
		}
	case 3: // climbing back
		t.pos.y = max(t.pos.y - HEAD_RISE * dt, home.y)
		if t.pos.y <= home.y {
			t.state = 0
		}
	}
	if !p.dead && rl.CheckCollisionRecs(player_rect(p^), head_rect(t^)) {
		player_kill(g)
	}
}

// Only what is on or near the screen is heard; a level full of shooters
// would otherwise be a wall of clicks.
@(private = "file")
near_player :: proc(g: ^Game, pos: rl.Vector2) -> bool {
	return rl.Vector2Distance(pos, g.player.pos) < view_size().x * 0.7
}

geyser_reach :: proc(t: Thing) -> f32 {
	return max(t.data.rect.height, TILE * 2)
}

head_rect :: proc(t: Thing) -> rl.Rectangle {
	return {t.pos.x - HEAD_SIZE / 2, t.pos.y - HEAD_SIZE / 2, HEAD_SIZE, HEAD_SIZE}
}

// Is there open air straight down from `from` to the height `to`?
@(private = "file")
clear_column :: proc(m: ^Tilemap, from: rl.Vector2, to: f32) -> bool {
	tx := int(math.floor(from.x / TILE))
	for ty := int(from.y / TILE) + 2; f32(ty) * TILE < to; ty += 1 {
		if is_blocking(tile_at(m, tx, ty)) {
			return false
		}
	}
	return true
}

fan_rect :: proc(t: Thing) -> rl.Rectangle {
	h := max(t.data.rect.height, TILE)
	return {t.pos.x - 11, t.pos.y - h, 22, h}
}

@(private = "file")
circle_hits :: proc(c: rl.Vector2, radius: f32, r: rl.Rectangle) -> bool {
	return rl.CheckCollisionCircleRec(c, radius, r)
}

@(private = "file")
arrows_update :: proc(g: ^Game, dt: f32) {
	pr := player_rect(g.player)
	live := 0
	for &a in g.arrows {
		a.life -= dt
		a.pos += a.vel * dt
		tile := tile_at(&g.map_tiles, int(math.floor(a.pos.x / TILE)), int(math.floor(a.pos.y / TILE)))
		if a.life <= 0 || is_blocking(tile) {
			if is_blocking(tile) {
				spawn_burst(g, a.pos, {210, 190, 150, 255}, 3, 40, 0.7)
			}
			continue
		}
		if !g.player.dead && rl.CheckCollisionPointRec(a.pos, pr) {
			player_kill(g)
			continue
		}
		g.arrows[live] = a
		live += 1
	}
	resize(&g.arrows, live)
}

// ------------------------------------------------------------------- draw ---

things_draw :: proc(g: ^Game) {
	a := &g.assets.traps
	for t in g.things {
		switch t.kind {
		case .Saw:
			draw_track(g, t)
			frame := int(g.time / 0.04) % 8
			anim_draw_rotated(&a.saw, frame, t.pos, 0)
		case .Moving_Platform:
			// Two boards of the world's own bridge, ends lashed with rope.
			draw_track(g, t)
			tex := g.assets.terrain[g.level.zone]
			top := rl.Vector2{math.round(t.pos.x - PLATFORM_W / 2), math.round(t.pos.y - PLATFORM_H / 2)}
			rl.DrawTexturePro(tex, terrain_source(0, ROW_PLATFORM), {top.x, top.y, TILE, TILE}, {}, 0, rl.WHITE)
			rl.DrawTexturePro(tex, terrain_source(3, ROW_PLATFORM), {top.x + TILE, top.y, TILE, TILE}, {}, 0, rl.WHITE)
		case .Falling_Platform:
			if t.state == 3 {
				continue
			}
			pos := t.pos + {16, 10}
			tint := rl.WHITE
			if t.state == 1 {
				pos.x += math.sin(g.time * 70) * 1.2
			}
			if t.state == 0 && t.timer > 0 {
				tint.a = u8(255 * (1 - t.timer / 0.3))
			}
			frame := int(g.time / 0.06) % 4
			if t.state == 0 {
				frame = 0
			}
			anim_draw_frame(&a.falling_platform, frame, pos, false, tint)
		case .Trampoline:
			if t.anim.anim != nil && !t.anim.finished {
				animator_draw(t.anim, t.pos, false)
			} else {
				anim_draw_frame(&a.trampoline, 0, t.pos, false)
			}
		case .Fan:
			// Streaks of air rising through the column, so you can see how far
			// it reaches.
			column := fan_rect(t)
			for i in 0 ..< 5 {
				k := f32(i) / 5
				rise := math.mod(g.time * 90 + k * column.height * 1.7, column.height)
				x := column.x + 3 + math.mod(k * 37, column.width - 6)
				y := column.y + column.height - rise
				alpha := u8(90 * math.sin(rise / column.height * math.PI))
				rl.DrawLineEx({x, y}, {x, y + 7}, 1, {220, 240, 255, alpha})
			}
			frame := int(g.time / 0.03) % 4
			anim_draw_frame(&a.fan, frame, t.pos, false)
		case .Fire:
			switch t.state {
			case 1:
				anim_draw_frame(&a.fire_hit, int(g.time / 0.08) % 4, t.pos, false)
			case 2:
				anim_draw_frame(&a.fire_on, int(g.time / 0.07) % 3, t.pos, false)
			case:
				anim_draw_frame(&a.fire_off, 0, t.pos, false)
			}
		case .Arrow_Shooter:
			draw_shooter(t)
		case .Refill:
			if t.state == 0 {
				bob := math.sin(g.time * 3 + t.pos.x) * 2
				frame := int(g.time / 0.07) % 10
				anim_draw_frame(&a.refill, frame, t.pos + {0, 9 + bob}, false)
			} else if t.anim.anim != nil && !t.anim.finished {
				animator_draw(t.anim, t.pos + {0, 9}, false)
			} else {
				// A faint outline of where it will grow back.
				rl.DrawCircleLinesV(t.pos, 5 * (1 - t.timer / REFILL_RESPAWN) + 1, {255, 255, 255, 60})
			}
		case .Geyser:
			draw_geyser(g, t)
		case .Spike_Head:
			pos := t.pos + {0, 26}
			if t.state == 4 {
				pos.x += math.sin(g.time * 90) * 1.5
			}
			if t.anim.anim != nil && !t.anim.finished {
				animator_draw(t.anim, pos, false)
			} else {
				anim_draw_frame(&a.spike_head, 0, pos, false)
			}
		case .Pig, .Slime, .Rino, .Bat, .Bee:
		}
	}
	for ar in g.arrows {
		draw_arrow(ar)
	}
}

// A vent in the rock: a dark mouth with a glowing rim. Bubbling, it sends up
// sparks; erupting, a column of hot spray to the top of its reach.
@(private = "file")
draw_geyser :: proc(g: ^Game, t: Thing) {
	base := t.pos
	rl.DrawEllipse(i32(base.x), i32(base.y - 1), 9, 3, {60, 30, 40, 255})
	rl.DrawEllipse(i32(base.x), i32(base.y - 1), 6, 1.8, t.state == 0 ? rl.Color{150, 70, 50, 255} : rl.Color{255, 170, 80, 255})
	if t.state != 2 {
		return
	}
	reach := geyser_reach(t)
	k := clamp(t.timer / GEYSER_BLOW, 0, 1)
	for i in 0 ..< 14 {
		f := f32(i) / 14
		y := base.y - reach * f
		w := 6 + 3 * math.sin(g.time * 20 + f32(i)) + (1 - f) * 2
		col := lerp_color({255, 240, 170, 255}, {255, 110, 60, 0}, f)
		col.a = u8(f32(col.a) * (0.4 + 0.6 * k))
		rl.DrawEllipse(i32(base.x + math.sin(g.time * 13 + f32(i) * 0.7) * 2), i32(y), w, 6, col)
	}
}

// Chain dots along the track, so you can see where a saw or platform goes.
@(private = "file")
draw_track :: proc(g: ^Game, t: Thing) {
	r := t.data.rect
	if r.width <= TILE * 1.5 && r.height <= TILE * 1.5 {
		return
	}
	saved := t
	saved.t = 0
	a := track_point(saved)
	saved.t = 1
	b := track_point(saved)
	steps := int(rl.Vector2Distance(a, b) / 10)
	for i in 0 ..= steps {
		pos := a + (b - a) * (f32(i) / f32(max(steps, 1)))
		rl.DrawTextureV(g.assets.traps.chain, pos - {4, 4}, {255, 255, 255, 170})
	}
}

@(private = "file")
draw_shooter :: proc(t: Thing) {
	d := rl.Vector2{f32(t.data.dir.x), f32(t.data.dir.y)}
	body := rl.Rectangle{t.pos.x - 7, t.pos.y - 7, 14, 14}
	rl.DrawRectangleRec(body, {92, 84, 104, 255})
	rl.DrawRectangleLinesEx(body, 1, {40, 34, 50, 255})
	rl.DrawRectangleRec({body.x + 2, body.y + 2, 10, 3}, {130, 122, 142, 255})
	// The mouth, on the side it fires from.
	mouth := t.pos + d * 5
	side := rl.Vector2{-d.y, d.x}
	tri(mouth + side * 3, mouth - side * 3, mouth + d * 3, {30, 24, 36, 255})
	tri(mouth + side * 3 - d * 2, mouth - side * 3 - d * 2, mouth + side * 3, {30, 24, 36, 255})
}

@(private = "file")
draw_arrow :: proc(a: Arrow) {
	d := rl.Vector2Normalize(a.vel)
	side := rl.Vector2{-d.y, d.x}
	tail := a.pos - d * 9
	rl.DrawLineEx(tail, a.pos, 1.5, {200, 170, 120, 255})
	tri(a.pos + d * 3, a.pos + side * 2.5, a.pos - side * 2.5, {220, 224, 236, 255})
	tri(tail, tail - d * 3 + side * 2.5, tail - d * 1, {230, 90, 80, 255})
	tri(tail, tail - d * 3 - side * 2.5, tail - d * 1, {230, 90, 80, 255})
}
