package game

import "core:math"
import "core:math/rand"
import rl "../libs/raylib"

/*
The thing in the vault. Each run rolls one of three, and every one of them has
two phases, a health bar across the top of the screen, and a move set where
nothing lands without a warning first:

  THE WARDEN      the golem. Armoured, it walks you down and charges; a charge
                  that ends in a wall brings the ceiling down. With the armour
                  off it leaps at you and throws shards and shockwaves.
  THE BROODMOTHER the bat grown huge. It hangs over the arena, screeches before
                  it dives, and calls its young. Hurt, it sheds rings of spit.
  THE OOZE KING   the slime grown huge. It hops after you and lobs globs, and
                  it sheds smaller slimes as it loses mass. Hurt, every landing
                  sends a wave along the floor.

The vault seals when you walk in and opens when it dies, so there is no
leaving a fight half-done and waiting for the corner of another room to heal.

Every special move is a wind-up then the move: the wind-up is when the creature
flashes, and it is long enough to react to.
*/

BOSS_INTRO_TIME :: 2.4
BOSS_PHASE_AT :: 0.5 // health fraction where the Broodmother and the Ooze King turn

Boss_Act :: enum u8 {
	None, // moving, choosing what to do next
	Wind_Up, // the warning before `queued`
	Melee,
	Charge,
	Stunned,
	Quake, // a stomp that brings rocks down
	Slam, // a stomp that sends shockwaves along the floor
	Leap,
	Dive,
	Rise,
	Recover, // standing still after a move, the window to punish it
	Enrage, // the turn into the second phase
}

is_boss :: proc(kind: Enemy_Kind) -> bool {
	return kind == .Golem || kind == .Brood || kind == .Ooze
}

@(private = "file")
Boss_Info :: struct {
	title:   cstring,
	epithet: cstring,
	colour:  rl.Color, // the health bar
	tint:    rl.Color, // laid over the borrowed sprite
}

@(private = "file")
boss_info :: proc(kind: Enemy_Kind) -> Boss_Info {
	#partial switch kind {
	case .Brood:
		return {"THE BROODMOTHER", "SHE NESTS IN THE DARK OVER THE VAULT", {198, 118, 236, 255}, {255, 176, 214, 255}}
	case .Ooze:
		return {"THE OOZE KING", "EVERYTHING THE HOLLOW ATE, STILL MOVING", {150, 232, 120, 255}, {255, 236, 150, 255}}
	}
	return {"THE WARDEN", "BUILT TO KEEP THE DEEP SEALED", {214, 170, 110, 255}, rl.WHITE}
}

boss_title :: proc(kind: Enemy_Kind) -> cstring {
	return boss_info(kind).title
}

Boss_Status :: struct {
	title:      cstring,
	epithet:    cstring,
	frac:       f32,
	frac_lag:   f32,
	phase_mark: f32,
	colour:     rl.Color,
}

// What the HUD needs to draw the fight: only once the vault has shut.
boss_status :: proc(g: ^Game) -> (Boss_Status, bool) {
	if !g.boss_sealed {
		return {}, false
	}
	for e in g.enemies {
		if !e.alive || !is_boss(e.kind) {
			continue
		}
		info := boss_info(e.kind)
		colour := info.colour
		if e.kind == .Golem && e.armoured {
			colour = {190, 200, 216, 255}
		} else if e.phase >= 2 {
			colour = {232, 92, 84, 255}
		}
		mark: f32 = e.kind == .Golem ? GOLEM_BREAK_AT : BOSS_PHASE_AT
		return {
				title = info.title,
				epithet = info.epithet,
				frac = e.health / e.max_health,
				frac_lag = e.lag,
				phase_mark = mark,
				colour = colour,
			},
			true
	}
	return {}, false
}

boss_tint :: proc(e: Enemy) -> rl.Color {
	tint := boss_info(e.kind).tint
	// The warning: a fast red flicker for as long as the wind-up lasts.
	if e.act == .Wind_Up && int(e.act_t * 18) % 2 == 0 {
		return {255, 110, 100, 255}
	}
	if e.act == .Stunned {
		return {150, 150, 170, 255}
	}
	if e.phase >= 2 && e.kind != .Golem {
		tint.g = u8(f32(tint.g) * 0.75)
		tint.b = u8(f32(tint.b) * 0.7)
	}
	return tint
}

// The boss for this run: never the one the last run had.
boss_roll :: proc(last: Enemy_Kind) -> Enemy_Kind {
	kinds := [?]Enemy_Kind{.Golem, .Brood, .Ooze}
	for {
		k := rand.choice(kinds[:])
		if k != last {
			return k
		}
	}
}

// ---------------------------------------------------------------- the vault ---

// Shuts the vault behind the player once they are properly inside it — never
// while they are standing in a doorway, or the door would close on them.
boss_check_seal :: proc(g: ^Game) {
	if g.boss_sealed || g.boss_down || g.room != g.world.boss || g.player.dead {
		return
	}
	bounds := room_rect(g.world.boss)
	inner := rl.Rectangle {
		bounds.x + TILE * 3,
		bounds.y + TILE * 3,
		bounds.width - TILE * 6,
		bounds.height - TILE * 4,
	}
	if !rl.CheckCollisionRecs(player_rect(g.player), inner) {
		return
	}
	for door in g.world.boss_doors {
		tile_set(&g.map_tiles, door.x, door.y, .Gate)
	}
	g.boss_sealed = true
	g.boss_intro = BOSS_INTRO_TIME
	g.shake = max(g.shake, 6)
	play(&g.assets, .Explode)
}

@(private = "file")
boss_unseal :: proc(g: ^Game) {
	for door in g.world.boss_doors {
		tile_set(&g.map_tiles, door.x, door.y, .Empty)
	}
}

// Called from `enemy_die`. The young go with their mother.
boss_die :: proc(g: ^Game, index: int) {
	e := &g.enemies[index]
	e.corpse = 3.0
	g.boss_down = true
	g.win_delay = 2.6
	g.shake = max(g.shake, 14)
	spawn_burst(g, enemy_centre(e^), {255, 220, 140, 255}, 46, 280, 2.6)
	spawn_burst(g, enemy_centre(e^), TRAITS[e.kind].tint, 30, 200, 2.0)
	boss_unseal(g)

	room := room_coords(e.pos)
	for &other, i in g.enemies {
		if i != index && other.alive && room_coords(other.pos) == room {
			enemy_die(g, i)
		}
	}
	// Whatever it had in the air dissolves with it.
	for &b in g.bullets {
		if !b.from_player {
			b.dead = true
		}
	}
}

// ------------------------------------------------------------------ helpers ---

@(private = "file")
minions_alive :: proc(g: ^Game, room: [2]int) -> int {
	n := 0
	for e in g.enemies {
		if e.alive && !is_boss(e.kind) && room_coords(e.pos) == room {
			n += 1
		}
	}
	return n
}

@(private = "file")
start :: proc(e: ^Enemy, act: Boss_Act, time: f32 = 0) {
	e.act = act
	e.act_t = time
	e.swung = false
}

@(private = "file")
wind_up :: proc(e: ^Enemy, then: Boss_Act, time: f32) {
	start(e, .Wind_Up, time)
	e.queued = then
}

// Ready for the next special after this long.
@(private = "file")
rest :: proc(e: ^Enemy, base: f32) {
	e.act = .None
	scale: f32 = e.phase >= 2 ? 0.7 : 1
	e.next_act = base * scale + rand.float32_range(0, 0.8)
}

// Two shockwaves crawl outward along the ground, so the arena has to be crossed
// rather than camped in.
@(private = "file")
shockwaves :: proc(g: ^Game, e: ^Enemy, speed: f32) {
	g.shake = max(g.shake, 9)
	play(&g.assets, .Explode)
	for dir in ([?]f32{-1, 1}) {
		enemy_fire(g, {e.pos.x + dir * 16, e.pos.y - 5}, {dir * speed, 0}, 1, 3.0, {255, 176, 90, 255}, size = 4)
	}
	spawn_burst(g, {e.pos.x, e.pos.y - 4}, {255, 200, 120, 255}, 18, 190, 1.9)
}

// Rocks come loose along the ceiling, mostly over the player. Each one shivers
// in place before it drops, and the gap between them is the way through.
@(private = "file")
rockfall :: proc(g: ^Game, count: int) {
	bounds := room_rect(g.room)
	left := bounds.x + TILE * 2
	right := bounds.x + bounds.width - TILE * 2
	for i in 0 ..< count {
		x := clamp(g.player.pos.x + rand.float32_range(-110, 110), left, right)
		if i == 0 {
			x = clamp(g.player.pos.x, left, right) // one is always right overhead
		}
		pos := rl.Vector2{x, bounds.y + TILE * 1.6}
		enemy_fire(
			g,
			pos,
			{0, 30},
			1,
			3.0,
			{176, 164, 150, 255},
			gravity = 520,
			delay = 0.55 + f32(i) * 0.12,
			size = 4,
		)
		spawn_burst(g, pos, {150, 140, 130, 255}, 4, 50, 1.0)
	}
}

// Aimed shots in a fan, centred on the player.
@(private = "file")
volley :: proc(g: ^Game, from: rl.Vector2, count: int, spread, speed: f32, tint: rl.Color) {
	to := player_centre(g.player) - from
	base := math.atan2(to.y, to.x)
	for i in 0 ..< count {
		off: f32 = count > 1 ? (f32(i) / f32(count - 1) - 0.5) * spread : 0
		a := base + off
		enemy_fire(g, from, {math.cos(a), math.sin(a)} * speed, 1, 3.0, tint, size = 3)
	}
	play(&g.assets, .Shoot)
}

@(private = "file")
ring_of_shots :: proc(g: ^Game, from: rl.Vector2, count: int, offset, speed: f32, tint: rl.Color) {
	for i in 0 ..< count {
		a := offset + f32(i) / f32(count) * math.TAU
		enemy_fire(g, from, {math.cos(a), math.sin(a)} * speed, 1, 4.0, tint, size = 3)
	}
	play(&g.assets, .Shoot)
}

// Globs thrown up and over, landing around the player.
@(private = "file")
lob :: proc(g: ^Game, from: rl.Vector2, count: int, tint: rl.Color) {
	dx := g.player.pos.x - from.x
	for i in 0 ..< count {
		spread := (f32(i) - f32(count - 1) / 2) * 34
		flight := rand.float32_range(0.9, 1.15)
		vy := -rand.float32_range(230, 290)
		enemy_fire(g, from, {(dx + spread) / flight, vy}, 1, 3.5, tint, gravity = 480, size = 3.5)
	}
	play(&g.assets, .Shoot)
}

// A swing at whatever is in front of it.
@(private = "file")
melee_hit :: proc(g: ^Game, e: ^Enemy) {
	t := TRAITS[e.kind]
	hitbox := enemy_rect(e^)
	hitbox.x += e.dir * t.reach * 0.6
	hitbox.y -= 6
	hitbox.height += 10
	if !g.player.dead && rl.CheckCollisionRecs(hitbox, player_rect(g.player)) {
		if player_hurt(&g.player, &g.assets, e.pos.x) {
			g.shake = max(g.shake, 7)
		}
	}
	spawn_burst(g, {e.pos.x + e.dir * t.reach * 0.8, e.pos.y - t.height * 0.4}, {230, 220, 200, 255}, 8, 140, 1.4)
}

@(private = "file")
grounded :: proc(g: ^Game, e: ^Enemy) -> bool {
	return e.vel.y >= 0 && on_ground(&g.map_tiles, enemy_rect(e^))
}

// A leap that lands where the player was standing when it left the ground.
@(private = "file")
leap_at :: proc(g: ^Game, e: ^Enemy, height: f32) {
	air := 2 * height / GRAVITY
	e.vel.y = -height
	e.vel.x = clamp((g.player.pos.x - e.pos.x) / air, -320, 320)
	e.dir = e.vel.x < 0 ? -1 : 1
	start(e, .Leap)
	play(&g.assets, .Jump)
}

// -------------------------------------------------------------------- update ---

boss_update :: proc(g: ^Game, index: int, dt: f32) {
	e := &g.enemies[index]
	a := &g.assets
	anims := anims_for(a, e^)
	t := TRAITS[e.kind]

	frac := e.health / e.max_health
	e.lag = max(frac, e.lag - dt * 0.3)
	if e.act != .None {
		e.act_t -= dt
	} else {
		e.next_act -= dt
	}

	// Before the doors shut, and during the introduction, it only postures.
	if !g.boss_sealed || g.boss_intro > 0 || g.player.dead {
		if t.flies {
			fly_toward(e, e.home + {0, math.sin(e.bob * 1.5) * 6}, t.speed * 0.5, 3, dt)
		} else {
			e.vel.x = 0
			walk_terrain(g, e, dt, false)
		}
		if e.state != .Shatter {
			animator_play(&e.anim, t.flies ? &anims.run : &anims.idle)
		}
		animator_update(&e.anim, dt)
		return
	}

	// The armour coming apart is the Warden's turn into its second phase.
	if e.state == .Shatter {
		e.vel.x = 0
		walk_terrain(g, e, dt, false)
		if e.anim.finished {
			e.armoured = false
			e.state = .Chase
			e.phase = 2
			e.attack_cd = 0.6
			rest(e, 1.0)
			animator_restart(&e.anim, &a.golem.broken.idle)
		}
		animator_update(&e.anim, dt)
		return
	}

	// The Broodmother and the Ooze King turn at half health.
	if e.kind != .Golem && e.phase == 1 && frac <= BOSS_PHASE_AT && e.act != .Leap && e.act != .Dive {
		e.phase = 2
		start(e, .Enrage, 1.0)
		e.vel = {}
		g.shake = max(g.shake, 10)
		spawn_burst(g, enemy_centre(e^), {255, 120, 100, 255}, 30, 240, 2.2)
		play(&g.assets, .Explode)
	}

	switch e.kind {
	case .Golem:
		warden_update(g, index, dt)
	case .Brood:
		brood_update(g, index, dt)
	case .Ooze:
		ooze_update(g, index, dt)
	case .Rat, .Slime, .Bat, .Crab, .Skull, .Pebble:
	}

	// The Broodmother and the Ooze King append their young to `g.enemies`,
	// which can move it.
	e = &g.enemies[index]
	animator_update(&e.anim, dt)
	enemy_check_drowned(g, index)
}

// ---------------------------------------------------------------- the Warden ---

@(private = "file")
warden_update :: proc(g: ^Game, index: int, dt: f32) {
	e := &g.enemies[index]
	a := &g.assets
	anims := anims_for(a, e^)
	t := TRAITS[e.kind]
	to_p := player_centre(g.player) - enemy_centre(e^)
	speed := t.speed * (e.phase >= 2 ? 1.4 : 1)

	switch e.act {
	case .None, .Enrage:
		e.dir = to_p.x < 0 ? -1 : 1
		if abs(to_p.x) < t.reach && abs(to_p.y) < 44 && e.attack_cd <= 0 {
			start(e, .Melee)
			e.attack_cd = t.attack_cd
			animator_restart(&e.anim, &anims.attack)
			break
		}
		if e.next_act <= 0 {
			roll := rand.float32()
			if e.phase == 1 {
				if roll < 0.6 {
					wind_up(e, .Charge, 0.7)
				} else {
					start(e, .Quake)
					animator_restart(&e.anim, &anims.attack)
				}
			} else {
				switch {
				case roll < 0.45:
					wind_up(e, .Leap, 0.45)
				case roll < 0.75:
					start(e, .Slam)
					animator_restart(&e.anim, &a.golem.slam)
				case:
					wind_up(e, .Recover, 0.4)
					e.count = 1 // a wind-up into a shard volley
				}
			}
			break
		}
		e.vel.x = abs(to_p.x) < 12 ? 0 : e.dir * speed
		walk_terrain(g, e, dt, true)
		animator_play(&e.anim, abs(e.vel.x) > 1 ? &anims.run : &anims.idle)

	case .Wind_Up:
		e.vel.x = approach_f32(e.vel.x, 0, 900 * dt)
		walk_terrain(g, e, dt, true)
		e.dir = to_p.x < 0 ? -1 : 1
		animator_play(&e.anim, &anims.idle)
		if rand.float32() < 0.3 {
			spawn_spark(g, e.pos + {rand.float32_range(-12, 12), -2}, {0, -1}, {170, 160, 150, 255}, 60, 1.2)
		}
		if e.act_t > 0 {
			break
		}
		#partial switch e.queued {
		case .Charge:
			start(e, .Charge, 2.2)
			play(&g.assets, .Explode)
		case .Leap:
			leap_at(g, e, 430)
		case .Recover:
			if e.count == 1 {
				e.count = 0
				volley(g, enemy_centre(e^), 5, 0.9, 170, {200, 190, 170, 255})
				volley(g, enemy_centre(e^), 4, 0.6, 130, {200, 190, 170, 255})
			}
			start(e, .Recover, 0.5)
		case:
			rest(e, 2.5)
		}

	case .Charge:
		before := e.dir
		e.vel.x = e.dir * (e.phase >= 2 ? 330 : 290)
		walk_terrain(g, e, dt, true)
		animator_play(&e.anim, &anims.run)
		if rand.float32() < 0.6 {
			spawn_spark(g, e.pos - {e.dir * 10, 2}, {-e.dir, -0.4}, {170, 160, 150, 255}, 80, 1.3)
		}
		// `walk_terrain` turns a walker round when it meets a wall: that is the
		// impact.
		if e.dir != before {
			e.dir = before
			start(e, .Stunned, 1.4)
			g.shake = max(g.shake, 11)
			play(&g.assets, .Explode)
			spawn_burst(g, e.pos + {e.dir * 16, -16}, {200, 190, 170, 255}, 20, 200, 1.8)
			rockfall(g, 4)
		} else if e.act_t <= 0 {
			rest(e, 2.0)
		}

	case .Stunned:
		e.vel.x = 0
		walk_terrain(g, e, dt, true)
		animator_play(&e.anim, &anims.idle)
		if e.act_t <= 0 {
			rest(e, 2.0)
		}

	case .Melee, .Quake, .Slam:
		e.vel.x = approach_f32(e.vel.x, 0, 700 * dt)
		walk_terrain(g, e, dt, true)
		if !e.swung && animator_progress(e.anim) >= 0.45 {
			e.swung = true
			switch e.act {
			case .Melee:
				e.vel.x = e.dir * 140
				melee_hit(g, e)
			case .Quake:
				g.shake = max(g.shake, 8)
				play(&g.assets, .Explode)
				spawn_burst(g, e.pos, {170, 160, 150, 255}, 16, 160, 1.6)
				rockfall(g, 3)
			case .Slam:
				shockwaves(g, e, 160)
			case .None, .Wind_Up, .Charge, .Stunned, .Leap, .Dive, .Rise, .Recover, .Enrage:
			}
		}
		if e.anim.finished || e.act_t < -anim_length(e.anim.anim) {
			if e.act == .Melee {
				e.act = .None
			} else {
				rest(e, 2.4)
			}
		}

	case .Leap:
		walk_terrain(g, e, dt, true)
		animator_play(&e.anim, &anims.run)
		if e.act_t < -0.15 && grounded(g, e) {
			e.vel.x = 0
			shockwaves(g, e, 170)
			start(e, .Recover, 0.6)
		}

	case .Recover:
		e.vel.x = approach_f32(e.vel.x, 0, 900 * dt)
		walk_terrain(g, e, dt, true)
		animator_play(&e.anim, &anims.idle)
		if e.act_t <= 0 {
			rest(e, 2.2)
		}

	case .Dive, .Rise:
		rest(e, 1)
	}
}

// ---------------------------------------------------------- the Broodmother ---

@(private = "file")
brood_update :: proc(g: ^Game, index: int, dt: f32) {
	e := &g.enemies[index]
	a := &g.assets
	anims := anims_for(a, e^)
	t := TRAITS[e.kind]
	bounds := room_rect(g.room)
	to_p := player_centre(g.player) - enemy_centre(e^)
	e.dir = to_p.x < 0 ? -1 : 1

	// Where she hangs between moves: high, over the player, never quite still.
	perch := rl.Vector2 {
		clamp(g.player.pos.x + math.sin(e.bob * 0.8) * 70, bounds.x + 48, bounds.x + bounds.width - 48),
		bounds.y + 116 + math.sin(e.bob * 1.7) * 10,
	}
	speed := t.speed * (e.phase >= 2 ? 1.3 : 1)

	switch e.act {
	case .None:
		fly_toward(e, perch, speed, 2.4, dt)
		animator_play(&e.anim, &anims.run)
		if e.next_act > 0 {
			break
		}
		roll := rand.float32()
		young := minions_alive(g, g.room)
		switch {
		case roll < 0.4:
			wind_up(e, .Dive, e.phase >= 2 ? 0.5 : 0.65)
		case roll < 0.6 && young < 3:
			// Calling the young: a screech, then two of them.
			for i in 0 ..< 2 {
				kind: Enemy_Kind = e.phase >= 2 && i == 1 ? .Skull : .Bat
				m := enemy_make(kind, enemy_centre(e^) + {f32(i * 2 - 1) * 22, 6})
				m.vel = {f32(i * 2 - 1) * 90, -40}
				append(&g.enemies, m)
			}
			e = &g.enemies[index] // the append may have moved her
			spawn_burst(g, enemy_centre(e^), {198, 118, 236, 255}, 18, 160, 1.6)
			play(&g.assets, .Power_Up)
			animator_restart(&e.anim, &anims.attack)
			start(e, .Recover, 0.7)
		case roll < 0.8 || e.phase == 1:
			animator_restart(&e.anim, &anims.attack)
			volley(g, enemy_centre(e^), e.phase >= 2 ? 5 : 3, 0.7, 150, {226, 120, 220, 255})
			start(e, .Recover, 0.6)
		case:
			wind_up(e, .Recover, 0.5)
			e.count = 2 // two rings
		}

	case .Wind_Up:
		e.vel *= 1 - min(1, 6 * dt)
		e.pos += e.vel * dt
		e.target = player_centre(g.player)
		animator_play(&e.anim, &anims.attack)
		if e.act_t > 0 {
			break
		}
		if e.queued == .Dive {
			start(e, .Dive, 1.1)
			play(&g.assets, .Jump)
		} else {
			start(e, .Recover, 0.9)
		}

	case .Dive:
		// Straight at where you were when the screech ended, and through it.
		dive := e.phase >= 2 ? f32(360) : 320
		fly_toward(e, e.target + {0, 8}, dive, 7, dt)
		animator_play(&e.anim, &anims.run)
		if rand.float32() < 0.5 {
			spawn_spark(g, enemy_centre(e^), -e.vel, {198, 118, 236, 255}, 60, 1.4)
		}
		if rl.Vector2Distance(e.pos, e.target) < 14 || e.act_t <= 0 {
			start(e, .Rise, 0.8)
		}

	case .Rise:
		fly_toward(e, perch, speed * 1.6, 3, dt)
		animator_play(&e.anim, &anims.run)
		if e.act_t <= 0 {
			rest(e, 1.8)
		}

	case .Recover:
		e.vel *= 1 - min(1, 4 * dt)
		e.pos += e.vel * dt
		// A pending ring of spit goes off at the start of the pause, and again
		// halfway through.
		if e.count > 0 && (e.count == 2 || e.act_t < 0.45) {
			offset := f32(e.count) * math.PI / 14
			ring_of_shots(g, enemy_centre(e^), 14, offset, 105, {226, 120, 220, 255})
			e.count -= 1
		}
		if e.act_t <= 0 {
			rest(e, 1.8)
		}

	case .Enrage:
		e.vel = {}
		animator_play(&e.anim, &anims.attack)
		if e.act_t <= 0 {
			wind_up(e, .Recover, 0.3)
			e.count = 2
		}

	case .Melee, .Charge, .Stunned, .Quake, .Slam, .Leap:
		rest(e, 1)
	}

	// She stays inside the vault however hard a dive overshoots.
	e.pos.x = clamp(e.pos.x, bounds.x + 24, bounds.x + bounds.width - 24)
	// The camera sits low in the vault, so "high" has to stay on screen.
	e.pos.y = clamp(e.pos.y, bounds.y + 90, bounds.y + bounds.height - TILE * 2)
}

// ------------------------------------------------------------- the Ooze King ---

@(private = "file")
OOZE_SPLITS := [?]f32{0.8, 0.6, 0.35, 0.15}

@(private = "file")
ooze_update :: proc(g: ^Game, index: int, dt: f32) {
	e := &g.enemies[index]
	a := &g.assets
	anims := anims_for(a, e^)
	to_p := player_centre(g.player) - enemy_centre(e^)
	tint := rl.Color{150, 232, 120, 255}

	// It sheds a pair of slimes at each mark it passes.
	if e.count < len(OOZE_SPLITS) && e.health / e.max_health <= OOZE_SPLITS[e.count] {
		e.count += 1
		pos := e.pos
		for side in ([?]f32{-1, 1}) {
			m := enemy_make(.Slime, pos + {side * 22, -4})
			m.vel = {side * 120, -160}
			m.dir = side
			append(&g.enemies, m)
		}
		e = &g.enemies[index]
		spawn_burst(g, enemy_centre(e^), tint, 20, 180, 1.8)
	}

	on_floor := grounded(g, e)

	switch e.act {
	case .None:
		e.dir = to_p.x < 0 ? -1 : 1
		e.vel.x = approach_f32(e.vel.x, 0, 500 * dt)
		walk_terrain(g, e, dt, true)
		animator_play(&e.anim, &anims.idle)
		if !on_floor {
			break
		}
		if e.next_act <= 0 {
			if e.phase >= 2 && rand.float32() < 0.45 {
				wind_up(e, .Leap, 0.5)
			} else {
				wind_up(e, .Recover, 0.5) // into a lob
			}
			break
		}
		if e.attack_cd <= 0 {
			// The hop: its way of walking.
			e.vel.y = e.phase >= 2 ? -330 : -280
			e.vel.x = e.dir * (e.phase >= 2 ? 150 : 115)
			e.attack_cd = e.phase >= 2 ? 0.75 : 1.2
			start(e, .Charge) // a hop, as far as the state machine cares
			animator_restart(&e.anim, &anims.run)
		}

	case .Charge:
		walk_terrain(g, e, dt, true)
		if e.act_t < -0.1 && on_floor {
			e.vel.x = 0
			g.shake = max(g.shake, 3)
			spawn_burst(g, e.pos, tint, 8, 110, 1.4)
			if e.phase >= 2 {
				shockwaves(g, e, 130)
			}
			e.act = .None
		}

	case .Wind_Up:
		e.vel.x = approach_f32(e.vel.x, 0, 900 * dt)
		walk_terrain(g, e, dt, true)
		animator_play(&e.anim, &anims.attack)
		if e.act_t > 0 {
			break
		}
		if e.queued == .Leap {
			leap_at(g, e, 470)
		} else {
			lob(g, enemy_centre(e^) - {0, 10}, e.phase >= 2 ? 7 : 5, tint)
			start(e, .Recover, 0.6)
		}

	case .Leap:
		walk_terrain(g, e, dt, true)
		animator_play(&e.anim, &anims.run)
		if e.act_t < -0.15 && on_floor {
			e.vel.x = 0
			shockwaves(g, e, 180)
			rockfall(g, 2)
			start(e, .Recover, 0.7)
		}

	case .Recover, .Enrage:
		e.vel.x = approach_f32(e.vel.x, 0, 900 * dt)
		walk_terrain(g, e, dt, true)
		animator_play(&e.anim, e.act == .Enrage ? &anims.attack : &anims.idle)
		if e.act_t <= 0 {
			rest(e, 2.0)
		}

	case .Melee, .Stunned, .Quake, .Slam, .Dive, .Rise:
		rest(e, 1)
	}
}
