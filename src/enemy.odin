package game

import "core:math"
import rl "../libs/raylib"

/*
The creatures, all from Pixel Adventure 2. Touching one kills you, except from
above: land on it while falling and it dies instead, bouncing you up and
giving the dash back, so a creature is as often a step as a threat.

  Pig     walks back and forth, turning at walls and edges.
  Slime   the same, slower.
  Rino    stands still until you are level with it and in front, then
          charges until it hits a wall, where it is dazed for a moment.
  Bat     swings slowly back and forth, three tiles either side of where it
          was placed. It does not chase: one that hung over you would make
          every jump a death, and a creature you cannot get above is one
          you cannot beat.
  Bee     bobs up and down where it was placed.

They are placed in LDtk like the traps (see `things.odin`), standing on their
rectangle's bottom edge (Pig, Slime, Rino) or centred in it (Bat, Bee).
*/

Enemy_Kind :: enum u8 {
	Pig,
	Slime,
	Rino,
	Bat,
	Bee,
}

Enemy_Traits :: struct {
	size:  rl.Vector2, // hitbox, standing on `pos`
	speed: f32,
	flies: bool,
}

ENEMY_TRAITS := [Enemy_Kind]Enemy_Traits {
	.Pig   = {{20, 18}, 42, false},
	.Slime = {{26, 14}, 22, false},
	.Rino  = {{30, 22}, 170, false},
	.Bat   = {{18, 14}, 0, true},
	.Bee   = {{16, 16}, 0, true},
}

STOMP_BOUNCE :: 415.0
STOMP_MARGIN :: 7.0 // feet this far into the top of a creature still count as above it
RINO_SIGHT :: 170.0
RINO_WIND_UP :: 0.35
RINO_DAZE :: 0.9
BAT_SWING :: 3 * TILE
BAT_PERIOD :: 3.2

Enemy :: struct {
	kind:  Enemy_Kind,
	pos:   rl.Vector2, // feet, horizontally centred
	home:  rl.Vector2,
	vel:   rl.Vector2,
	dir:   f32, // -1 left, +1 right
	state: int,
	timer: f32,
	t:     f32,
	alive: bool,
	dying: f32, // > 0 while it tumbles away after a stomp
	anim:  Animator,
}

enemy_make :: proc(d: Thing_Data) -> Enemy {
	kind := Enemy_Kind(int(d.kind) - int(FIRST_CREATURE))
	r := d.rect
	pos := rl.Vector2{r.x + r.width / 2, r.y + r.height}
	if ENEMY_TRAITS[kind].flies {
		// Centred in the rectangle; `pos` is still the bottom of the body.
		pos = {r.x + r.width / 2, r.y + r.height / 2 + ENEMY_TRAITS[kind].size.y / 2}
	}
	return {kind = kind, pos = pos, home = pos, dir = -1, alive = true}
}

enemy_rect :: proc(e: Enemy) -> rl.Rectangle {
	s := ENEMY_TRAITS[e.kind].size
	return {e.pos.x - s.x / 2, e.pos.y - s.y, s.x, s.y}
}

enemies_update :: proc(g: ^Game, dt: f32) {
	m := &g.map_tiles
	p := &g.player
	a := &g.assets
	for &e in g.enemies {
		anims := &a.enemy[e.kind]
		if !e.alive {
			// Knocked off the level, spinning.
			e.dying -= dt
			e.vel.y += GRAVITY * dt
			e.pos += e.vel * dt
			animator_update(&e.anim, dt)
			continue
		}
		t := ENEMY_TRAITS[e.kind]
		e.t += dt
		e.timer -= dt
		body := &anims.run

		switch e.kind {
		case .Pig, .Slime:
			walk(m, &e, t.speed, dt)
		case .Rino:
			switch e.state {
			case 0: // watching
				body = &anims.idle
				e.vel.x = 0
				fall(m, &e, dt)
				to := p.pos - e.pos
				if !p.dead && abs(to.y) < 24 && abs(to.x) < RINO_SIGHT && line_clear(m, e.pos - {0, 8}, p.pos - {0, 8}) {
					e.dir = math.sign(to.x)
					e.state = 1
					e.timer = RINO_WIND_UP
				}
			case 1: // pawing the ground
				body = &anims.idle
				if e.timer <= 0 {
					e.state = 2
				}
			case 2: // charging
				r := enemy_rect(e)
				moved, hit := move_x(m, r, e.dir * t.speed * dt)
				e.pos.x = moved.x + r.width / 2
				fall(m, &e, dt)
				if hit {
					e.state = 3
					e.timer = RINO_DAZE
					g.shake = max(g.shake, 3)
					spawn_burst(g, e.pos + {e.dir * 14, -10}, {220, 210, 190, 255}, 8, 80, 1.0)
					animator_restart(&e.anim, &anims.hit)
				} else if !ground_ahead(m, e) {
					e.state = 0 // stops dead at an edge rather than going over
				}
			case 3: // dazed
				body = &anims.hit
				if e.timer <= 0 {
					e.state = 0
					e.dir = -e.dir
				}
			}
		case .Bat:
			phase := e.t * math.TAU / BAT_PERIOD
			e.pos.x = e.home.x + math.sin(phase) * BAT_SWING
			e.pos.y = e.home.y + math.sin(phase * 2) * 3
			e.dir = math.cos(phase) > 0 ? 1 : -1
		case .Bee:
			body = &anims.idle
			e.pos.y = e.home.y + math.sin(e.t * 2.2) * 14
			e.dir = p.pos.x > e.pos.x ? 1 : -1
		}

		if e.anim.anim != &anims.hit || e.anim.finished {
			animator_play(&e.anim, body)
		}
		animator_update(&e.anim, dt)
		enemy_touch_player(g, &e)
	}
}

// From above it is a step; from anywhere else it is a death.
@(private = "file")
enemy_touch_player :: proc(g: ^Game, e: ^Enemy) {
	p := &g.player
	if p.dead {
		return
	}
	pr := player_rect(p^)
	er := enemy_rect(e^)
	if !rl.CheckCollisionRecs(pr, er) {
		return
	}
	falling := p.vel.y > 0 || (p.dash_time > 0 && p.dash_dir.y > 0)
	if falling && p.pos.y - p.vel.y * (1.0 / 60) <= er.y + STOMP_MARGIN {
		e.alive = false
		e.dying = 2
		e.vel = {p.vel.x * 0.3, -160}
		animator_restart(&e.anim, &g.assets.enemy[e.kind].hit)
		spawn_burst(g, {e.pos.x, er.y}, {255, 255, 255, 255}, 10, 110, 1.2)
		g.shake = max(g.shake, 2)
		g.freeze = 0.03
		play(&g.assets, .Stomp)
		haptic(.Stomp)
		p.pos.y = er.y
		player_bounce(g, STOMP_BOUNCE)
		return
	}
	player_kill(g)
}

// Walkers: on, until a wall or the edge of their footing, then back.
@(private = "file")
walk :: proc(m: ^Tilemap, e: ^Enemy, speed, dt: f32) {
	r := enemy_rect(e^)
	moved, hit := move_x(m, r, e.dir * speed * dt)
	e.pos.x = moved.x + r.width / 2
	fall(m, e, dt)
	if hit || !ground_ahead(m, e^) {
		e.dir = -e.dir
	}
}

@(private = "file")
fall :: proc(m: ^Tilemap, e: ^Enemy, dt: f32) {
	e.vel.y = min(e.vel.y + GRAVITY * dt, MAX_FALL)
	r := enemy_rect(e^)
	moved, grounded, _ := move_y(m, r, e.vel.y * dt)
	e.pos.y = moved.y + r.height
	if grounded {
		e.vel.y = 0
	}
}

@(private = "file")
ground_ahead :: proc(m: ^Tilemap, e: Enemy) -> bool {
	r := enemy_rect(e)
	if !on_ground(m, r) {
		return true // in the air: nothing to turn back from yet
	}
	probe := r
	probe.x += e.dir * (r.width / 2 + 2)
	return on_ground(m, probe)
}

// Is there no rock between two points? Sampled every half tile.
@(private = "file")
line_clear :: proc(m: ^Tilemap, a, b: rl.Vector2) -> bool {
	d := b - a
	steps := int(rl.Vector2Length(d) / (TILE / 2)) + 1
	for i in 1 ..< steps {
		q := a + d * (f32(i) / f32(steps))
		if is_blocking(tile_at(m, int(math.floor(q.x / TILE)), int(math.floor(q.y / TILE)))) {
			return false
		}
	}
	return true
}

enemies_draw :: proc(g: ^Game) {
	for e in g.enemies {
		if !e.alive && e.dying <= 0 {
			continue
		}
		tint := rl.WHITE
		if !e.alive {
			tint.a = u8(clamp(e.dying, 0, 1) * 255)
		}
		pos := e.pos
		if e.kind == .Bat && e.alive {
			pos.y += math.sin(e.t * 9) * 1.2
		}
		animator_draw(e.anim, pos, e.dir > 0, tint)
	}
}
