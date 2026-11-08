package game

import "core:math"
import "core:math/rand"
import rl "../libs/raylib"

/*
Two kinds of creature share this file. Walkers patrol a ledge until they notice
you, then close in and lunge. Flyers ignore the terrain and steer straight at
you. The three bosses are creatures too — they take damage, die and collide the
same way — but they think in `boss.odin`.
*/

Enemy_Kind :: enum u8 {
	Rat,
	Slime,
	Bat,
	Crab,
	Skull,
	Pebble,
	// The bosses. One of them guards the vault each run.
	Golem,
	Brood,
	Ooze,
}

Enemy_State :: enum u8 {
	Idle,
	Chase,
	Attack,
	Hurt,
	Shatter, // the golem losing its armour
	Dying,
}

Enemy_Traits :: struct {
	health:    f32,
	speed:     f32,
	flies:     bool,
	width:     f32,
	height:    f32,
	sight:     f32,
	reach:     f32, // how close it has to be to start a swing
	attack_cd: f32,
	lunge:     f32, // horizontal burst applied during the swing
	scale:     f32,
	tint:      rl.Color, // used for its hit and death bursts
}

TRAITS := [Enemy_Kind]Enemy_Traits {
	.Rat = {
		health = 14,
		speed = 76,
		width = 22,
		height = 20,
		sight = 155,
		reach = 20,
		attack_cd = 1.1,
		lunge = 190,
		scale = 1,
		tint = {214, 224, 236, 255},
	},
	.Slime = {
		health = 26,
		speed = 38,
		width = 30,
		height = 18,
		sight = 135,
		reach = 26,
		attack_cd = 1.5,
		lunge = 150,
		scale = 1,
		tint = {126, 232, 140, 255},
	},
	.Bat = {
		health = 12,
		speed = 68,
		flies = true,
		width = 22,
		height = 16,
		sight = 190,
		reach = 24,
		attack_cd = 1.3,
		lunge = 210,
		scale = 1,
		tint = {198, 118, 236, 255},
	},
	.Crab = {
		health = 42,
		speed = 46,
		width = 36,
		height = 24,
		sight = 150,
		reach = 24,
		attack_cd = 1.5,
		lunge = 160,
		scale = 1,
		tint = {236, 96, 84, 255},
	},
	.Skull = {
		health = 10,
		speed = 54,
		flies = true,
		width = 20,
		height = 22,
		sight = 210,
		reach = 18,
		attack_cd = 1.0,
		lunge = 150,
		scale = 1,
		tint = {228, 232, 240, 255},
	},
	.Pebble = {
		health = 30,
		speed = 86,
		flies = true,
		width = 18,
		height = 20,
		sight = 175,
		reach = 20,
		attack_cd = 1.8,
		lunge = 260,
		scale = 1,
		tint = {168, 176, 200, 255},
	},
	.Golem = {
		health = 440,
		speed = 46,
		width = 34,
		height = 36,
		sight = 600,
		reach = 40,
		attack_cd = 1.4,
		lunge = 220,
		scale = 1.3,
		tint = {150, 214, 120, 255},
	},
	.Brood = {
		health = 320,
		speed = 74,
		flies = true,
		width = 40,
		height = 26,
		sight = 600,
		reach = 30,
		attack_cd = 1.2,
		lunge = 200,
		scale = 1.4,
		tint = {198, 118, 236, 255},
	},
	.Ooze = {
		health = 400,
		speed = 52,
		width = 46,
		height = 34,
		sight = 600,
		reach = 40,
		attack_cd = 1.3,
		lunge = 160,
		scale = 1.6,
		tint = {126, 232, 140, 255},
	},
}

CORPSE_TIME :: 1.0
HURT_TIME :: 0.18
// A hit only interrupts what a creature is doing this often. Without the gap,
// anything that fires faster than HURT_TIME could hold even the golem in place
// forever, and the boss fight was just standing still with an SMG.
STAGGER_COOLDOWN :: 0.6
GOLEM_ARMOUR_SOAK :: 0.5 // fraction of incoming damage the armoured phase takes
GOLEM_BREAK_AT :: 0.55 // health fraction at which the armour shatters

Enemy :: struct {
	kind:       Enemy_Kind,
	pos:        rl.Vector2, // at the feet for walkers, at the belly for flyers
	vel:        rl.Vector2,
	home:       rl.Vector2,
	dir:        f32, // -1 or +1
	health:     f32,
	max_health: f32,
	state:      Enemy_State,
	timer:      f32,
	attack_cd:  f32,
	hurt:       f32,
	stagger_cd: f32, // until the next hit is allowed to interrupt it
	bob:        f32,
	alive:      bool,
	corpse:     f32,
	swung:      bool, // the current swing has already connected
	armoured:   bool, // golem only
	anim:       Animator,

	// Bosses only; see `boss.odin`.
	phase:      int,
	act:        Boss_Act,
	queued:     Boss_Act, // what a wind-up turns into
	act_t:      f32,
	next_act:   f32, // until the next special move
	target:     rl.Vector2,
	count:      int,
	lag:        f32, // the health bar's trailing edge
}

enemy_flies :: proc(kind: Enemy_Kind) -> bool {
	return TRAITS[kind].flies
}

enemy_make :: proc(kind: Enemy_Kind, spawn: rl.Vector2) -> Enemy {
	t := TRAITS[kind]
	return {
		kind = kind,
		pos = spawn,
		home = spawn,
		dir = rand.float32() < 0.5 ? -1 : 1,
		health = t.health,
		max_health = t.health,
		alive = true,
		armoured = kind == .Golem,
		bob = rand.float32_range(0, math.TAU),
		phase = 1,
		lag = 1,
		next_act = 2.5,
	}
}

enemy_rect :: proc(e: Enemy) -> rl.Rectangle {
	t := TRAITS[e.kind]
	return {e.pos.x - t.width / 2, e.pos.y - t.height, t.width, t.height}
}

enemy_centre :: proc(e: Enemy) -> rl.Vector2 {
	return {e.pos.x, e.pos.y - TRAITS[e.kind].height / 2}
}

// The golem swaps its whole animation set when its armour comes off. The other
// two bosses are the bat and the slime grown huge, so they borrow their sheets.
anims_for :: proc(a: ^Assets, e: Enemy) -> ^Creature_Anims {
	#partial switch e.kind {
	case .Golem:
		return e.armoured ? &a.golem.armor : &a.golem.broken
	case .Brood:
		return &a.enemy[.Bat]
	case .Ooze:
		return &a.enemy[.Slime]
	}
	return &a.enemy[e.kind]
}

approach_f32 :: proc(current, target, delta: f32) -> f32 {
	return current < target ? min(current + delta, target) : max(current - delta, target)
}

// ------------------------------------------------------------------- damage ---

enemy_damage :: proc(g: ^Game, index: int, amount: f32, push: rl.Vector2) {
	e := &g.enemies[index]
	if !e.alive || e.state == .Shatter {
		return
	}
	t := TRAITS[e.kind]

	taken := amount
	if e.kind == .Golem && e.armoured {
		taken *= GOLEM_ARMOUR_SOAK
	}
	e.health -= taken
	e.hurt = HURT_TIME
	spawn_burst(g, enemy_centre(e^), t.tint, 5, 130, 1.3)

	// Heavy creatures are barely nudged; light ones get thrown.
	mass := max(1, t.health / 16)
	e.vel += push / mass
	if !t.flies {
		e.vel.y = min(e.vel.y, -40 / mass)
	}

	if e.health <= 0 {
		enemy_die(g, index)
		return
	}
	if e.kind == .Golem && e.armoured && e.health <= e.max_health * GOLEM_BREAK_AT {
		e.state = .Shatter
		e.act = .None
		e.timer = 0
		animator_restart(&e.anim, &g.assets.golem.armor.death)
		spawn_burst(g, enemy_centre(e^), {200, 210, 220, 255}, 26, 220, 2.0)
		g.shake = max(g.shake, 8)
		play(&g.assets, .Explode)
		return
	}
	// A boss flinches (the flash) but is never knocked out of what it is doing:
	// its attacks are the fight, and interrupting them would make it a target.
	if is_boss(e.kind) {
		play(&g.assets, .Hurt)
		return
	}
	if e.state != .Attack && e.stagger_cd <= 0 {
		e.state = .Hurt
		e.timer = HURT_TIME
		e.stagger_cd = STAGGER_COOLDOWN
		animator_restart(&e.anim, &anims_for(&g.assets, e^).hit)
	}
	play(&g.assets, .Hurt)
}

enemy_die :: proc(g: ^Game, index: int) {
	e := &g.enemies[index]
	if !e.alive {
		return
	}
	t := TRAITS[e.kind]
	e.alive = false
	e.state = .Dying
	e.corpse = CORPSE_TIME
	e.vel = {}
	animator_restart(&e.anim, &anims_for(&g.assets, e^).death)
	spawn_burst(g, enemy_centre(e^), t.tint, 14, 190, 1.6)
	g.player.kills += 1

	if is_boss(e.kind) {
		boss_die(g, index)
	}
	play(&g.assets, .Explode)
}

// ----------------------------------------------------------------- movement ---

walk_terrain :: proc(g: ^Game, e: ^Enemy, dt: f32, chasing: bool) {
	m := &g.map_tiles
	t := TRAITS[e.kind]
	e.vel.y = min(e.vel.y + GRAVITY * dt, MAX_FALL)

	r := enemy_rect(e^)
	wall_hit: bool
	r, wall_hit = move_x(m, r, e.vel.x * dt)
	if wall_hit {
		e.dir = -e.dir
		e.vel.x = 0
	}

	grounded: bool
	r, grounded, _ = move_y(m, r, e.vel.y * dt)
	if grounded {
		e.vel.y = 0
	}
	e.pos = {r.x + t.width / 2, r.y + t.height}

	// Walkers stop at a ledge or at the lip of water. While chasing they will
	// still step off a ledge, but never into a hazard.
	if grounded {
		probe := rl.Rectangle {
			e.pos.x + e.dir * (t.width / 2 + 1) - 1,
			e.pos.y - t.height,
			2,
			t.height + 3,
		}
		if tilemap_touches_hazard(m, probe) || (!chasing && !on_ground(m, probe)) {
			e.dir = -e.dir
			e.vel.x = 0
		}
	}

	if tilemap_touches_hazard(m, enemy_rect(e^)) {
		e.health = 0
	}
}

fly_toward :: proc(e: ^Enemy, target: rl.Vector2, speed, accel, dt: f32) {
	to := target - e.pos
	if rl.Vector2LengthSqr(to) > 1 {
		want := rl.Vector2Normalize(to) * speed
		e.vel += (want - e.vel) * min(1, accel * dt)
	}
	e.pos += e.vel * dt
}

// ------------------------------------------------------------------- update ---

enemy_update :: proc(g: ^Game, index: int, dt: f32) {
	e := &g.enemies[index]
	a := &g.assets
	t := TRAITS[e.kind]
	anims := anims_for(a, e^)

	if !e.alive {
		e.corpse -= dt
		animator_update(&e.anim, dt)
		return
	}

	e.hurt = max(0, e.hurt - dt)
	e.stagger_cd = max(0, e.stagger_cd - dt)
	e.attack_cd = max(0, e.attack_cd - dt)
	e.bob += dt

	// Creatures only wake up while the player is in their room. Otherwise a
	// fight you cannot see would still be draining your health.
	if room_coords(e.pos) != room_coords(g.player.pos) {
		// Whatever it was doing settles back to idling. A swing left running
		// would otherwise wait on an animation that is about to be swapped
		// out from under it, and never end.
		if e.state == .Chase || e.state == .Attack || e.state == .Hurt {
			e.state = .Idle
		}
		if !t.flies {
			e.vel.x = 0
			walk_terrain(g, e, dt, false)
		}
		// The armour coming apart is the one thing that has to keep playing,
		// or the golem would be stuck untouchable until it finished.
		if e.state != .Shatter {
			animator_play(&e.anim, &anims.idle)
		}
		animator_update(&e.anim, dt)
		enemy_check_drowned(g, index)
		return
	}

	if is_boss(e.kind) {
		boss_update(g, index, dt)
		return
	}

	to_player := player_centre(g.player) - enemy_centre(e^)
	distance := rl.Vector2Length(to_player)
	awake := !g.player.dead && distance < t.sight

	switch e.state {
	case .Hurt:
		e.timer -= dt
		if t.flies {
			e.vel *= 1 - min(1, 4 * dt)
			e.pos += e.vel * dt
		} else {
			e.vel.x = approach_f32(e.vel.x, 0, 400 * dt)
			walk_terrain(g, e, dt, false)
		}
		if e.timer <= 0 {
			e.state = awake ? .Chase : .Idle
		}

	case .Shatter:
	case .Idle:
		if awake {
			e.state = .Chase
			break
		}
		if t.flies {
			// Drift in a slow circle around the spot it was placed.
			target := e.home + {math.cos(e.bob * 0.7) * 20, math.sin(e.bob) * 12}
			fly_toward(e, target, t.speed * 0.5, 3, dt)
		} else {
			e.vel.x = e.dir * t.speed * 0.35
			walk_terrain(g, e, dt, false)
		}
		animator_play(&e.anim, t.flies ? &anims.run : &anims.idle)

	case .Chase:
		if !awake {
			e.state = .Idle
			break
		}
		if distance < t.reach && e.attack_cd <= 0 {
			e.state = .Attack
			e.timer = 0
			e.swung = false
			e.attack_cd = t.attack_cd
			animator_restart(&e.anim, &anims.attack)
			break
		}
		if t.flies {
			// Aim slightly above the player so flyers dive at you instead of
			// grinding along the floor.
			fly_toward(e, player_centre(g.player) - {0, 6}, t.speed, 2.2, dt)
			e.dir = to_player.x < 0 ? -1 : 1
		} else {
			e.dir = to_player.x < 0 ? -1 : 1
			e.vel.x = e.dir * t.speed
			walk_terrain(g, e, dt, true)
		}
		animator_play(&e.anim, &anims.run)

	case .Attack:
		e.timer += dt
		if t.flies {
			e.pos += e.vel * dt
			e.vel *= 1 - min(1, 2 * dt)
		} else {
			walk_terrain(g, e, dt, true)
		}
		// The middle of the animation is the committed part of the swing: the
		// lunge happens there, and it is the only window that can hurt you.
		if !e.swung && animator_progress(e.anim) >= 0.45 {
			e.swung = true
			enemy_strike(g, index)
		}
		// Some creatures swing with a looping sheet (the skull and the pebble
		// just fly at you), which never reports `finished`, so one full pass
		// of the animation is the swing's length either way.
		if e.anim.finished || e.timer >= anim_length(e.anim.anim) {
			e.state = .Chase
		}

	case .Dying:
	}

	animator_update(&e.anim, dt)
	enemy_check_drowned(g, index)
}

// Walkers that end up in water — knocked in by a shot, or lunging off a ledge —
// have had their health zeroed by `walk_terrain`; this is where that becomes a
// death rather than a creature wandering around with an empty health bar.
enemy_check_drowned :: proc(g: ^Game, index: int) {
	e := &g.enemies[index]
	if e.alive && e.health <= 0 {
		enemy_die(g, index)
	}
}

// The damaging half of an attack.
@(private = "file")
enemy_strike :: proc(g: ^Game, index: int) {
	e := &g.enemies[index]
	t := TRAITS[e.kind]

	e.vel.x = e.dir * t.lunge
	if !t.flies {
		e.vel.y = min(e.vel.y, -70)
	}

	// A swing only lands if the player is still inside it when it connects.
	hitbox := enemy_rect(e^)
	hitbox.x += e.dir * t.reach * 0.5
	hitbox.width += t.reach * 0.5
	hitbox.y -= 4
	hitbox.height += 8
	if !g.player.dead && rl.CheckCollisionRecs(hitbox, player_rect(g.player)) {
		if player_hurt(&g.player, &g.assets, e.pos.x) {
			g.shake = max(g.shake, 6)
		}
	}
}

// ------------------------------------------------------------------ drawing ---

enemy_draw :: proc(e: Enemy, a: ^Assets) {
	if !e.alive && e.corpse <= 0 {
		return
	}
	t := TRAITS[e.kind]

	pos := e.pos
	if t.flies && e.alive {
		pos.y += math.sin(e.bob * 3) * 1.5
	}

	tint := is_boss(e.kind) ? boss_tint(e) : rl.WHITE
	if !e.alive {
		tint.a = u8(clamp(e.corpse / CORPSE_TIME, 0, 1) * 255)
	} else if e.hurt > 0 {
		tint = {255, 190, 190, 255} // flash on the frames right after a hit
	}

	animator_draw(e.anim, pos, e.dir > 0, tint, t.scale)
}

// A slim health bar, only over things tough enough to need one.
enemy_draw_health :: proc(e: Enemy) {
	if !e.alive || e.health >= e.max_health || e.max_health < 30 || is_boss(e.kind) {
		return
	}
	t := TRAITS[e.kind]
	width := max(t.width, 18) * t.scale
	x := e.pos.x - width / 2
	y := e.pos.y - t.height * t.scale - 6
	rl.DrawRectangleV({x, y}, {width, 2}, {20, 16, 24, 200})

	colour := rl.Color{226, 96, 96, 255}
	rl.DrawRectangleV({x, y}, {width * clamp(e.health / e.max_health, 0, 1), 2}, colour)
}
