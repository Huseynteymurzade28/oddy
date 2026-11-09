package game

import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:strings"
import rl "../libs/raylib"

/*
The bosses: the last level of each world. No gun, so every one of them is
beaten the platformer way, by landing on it while it is open. Each has a tell
before every move, a window where it is open, and a breather after each hit
during which it cannot hurt you; a hit also throws you clear of it. Dying
puts the boss back at full strength. The level's exit stays shut until it is
down.

  Ooze_King    (world 1) A crowned slime the size of a house. It squats, then
               hops at you; every landing sends a ripple along the floor to
               jump. Just after it lands it sags, open. Each hit shrinks it
               and makes it quicker; from the second it sheds small slimes.
  Broodmother  (world 2) A great bat sweeping the top of the arena. She
               screeches (and flushes red) as she picks her spot, then dives
               at where you were. Diving into the floor stuns her: open. From
               the second hit she calls her young.
  Warden       (world 3) A living boulder. It paws the ground, then charges
               the length of the arena; jump it. When it hits a wall it is
               dazed, open, and once it has been hit the jolt shakes rocks
               loose from the ceiling, each one marked where it will land.

Placed in LDtk as an entity named after its kind, standing on the bottom of
its rectangle (the Broodmother hovers where she is placed).
*/

Boss_Kind :: enum u8 {
	Ooze_King,
	Broodmother,
	Warden,
}

Boss_State :: enum u8 {
	Waiting, // before the fight
	Idle,
	Wind_Up, // the tell
	Attack, // hop, dive or charge
	Open, // stunned after an attack: land on it now
	Recover, // getting back to its feet (or wings): not open
	Hurt,
	Dying,
}

Boss :: struct {
	kind:    Boss_Kind,
	home:    rl.Vector2,
	pos:     rl.Vector2, // feet, centred
	vel:     rl.Vector2,
	target:  rl.Vector2,
	dir:     f32,
	hp:      int,
	max_hp:  int,
	state:   Boss_State,
	timer:   f32,
	t:       f32,
	squash:  rl.Vector2,
	anim:    Animator,
	present: bool,
	beaten:  bool,
}

// A ripple along the floor from the Ooze King's landing: low, so a hop
// clears it.
Wave :: struct {
	pos:  rl.Vector2, // on the floor
	dir:  f32,
	life: f32,
}

// A rock shaken loose by the Warden: it hangs and trembles, marked on the
// floor below, then drops.
Rock :: struct {
	pos:   rl.Vector2,
	vel:   f32,
	warn:  f32, // > 0 while it is still hanging
	floor: f32, // where it will land, for the mark
}

BOSS_HP :: 3
BOSS_HURT :: 1.0
WAVE_SPEED :: 150.0
WAVE_SIZE :: rl.Vector2{12, 9}
ROCK_R :: 6.0

OOZE_SCALE := [BOSS_HP + 1]f32{1.6, 2.0, 2.5, 3.0} // by hits left
OOZE_WAIT := [BOSS_HP + 1]f32{0.3, 0.45, 0.65, 0.9}

BROOD_SCALE :: 2.4
BROOD_DIVE_SPEED := [BOSS_HP + 1]f32{330, 330, 290, 250}

WARDEN_SCALE :: 1.6
WARDEN_SPEED := [BOSS_HP + 1]f32{260, 260, 215, 175}

boss_kind_from_name :: proc(name: string) -> (Boss_Kind, bool) {
	for k in Boss_Kind {
		if fmt.tprint(k) == name {
			return k, true
		}
	}
	return {}, false
}

boss_make :: proc(kind: Boss_Kind, foot: rl.Vector2) -> Boss {
	return {
		kind    = kind,
		home    = foot,
		pos     = foot,
		dir     = -1,
		hp      = BOSS_HP,
		max_hp  = BOSS_HP,
		state   = .Waiting,
		squash  = {1, 1},
		present = true,
	}
}

boss_name :: proc(kind: Boss_Kind) -> cstring {
	switch kind {
	case .Ooze_King:
		return "THE OOZE KING"
	case .Broodmother:
		return "THE BROODMOTHER"
	case .Warden:
		return "THE WARDEN"
	}
	return ""
}

boss_rect :: proc(b: Boss) -> rl.Rectangle {
	w, h: f32
	switch b.kind {
	case .Ooze_King:
		s := OOZE_SCALE[clamp(b.hp, 0, BOSS_HP)]
		w, h = 22 * s, 15 * s
	case .Broodmother:
		w, h = 40, 26
	case .Warden:
		w, h = 40, 42
	}
	return {b.pos.x - w / 2, b.pos.y - h, w, h}
}

// ---------------------------------------------------------------- update ---

boss_update :: proc(g: ^Game, dt: f32) {
	b := &g.boss
	if !b.present || b.beaten {
		return
	}
	p := &g.player
	b.t += dt
	b.timer -= dt
	b.squash += (rl.Vector2{1, 1} - b.squash) * min(1, dt * 10)

	if b.state == .Waiting {
		// It wakes a moment into the level, or sooner if you walk up to it.
		if !p.dead && (abs(p.pos.x - b.pos.x) < view_size().x * 0.6 || g.level_time > 1.0) {
			b.state = .Idle
			b.timer = 1.2
			g.boss_intro = BOSS_INTRO_TIME
			g.shake = max(g.shake, 3)
			play(&g.assets, .Slam)
		}
		return
	}
	if b.state == .Hurt {
		if b.kind != .Broodmother {
			fall(&g.map_tiles, b, dt)
		}
		if b.timer <= 0 {
			if b.hp <= 0 {
				boss_defeat(g)
				return
			}
			b.state = b.kind == .Broodmother ? .Recover : .Idle
			b.timer = 0.6
		}
	} else {
		switch b.kind {
		case .Ooze_King:
			ooze_update(g, b, dt)
		case .Broodmother:
			brood_update(g, b, dt)
		case .Warden:
			warden_update(g, b, dt)
		}
	}
	a := &g.assets
	anims: ^Creature_Anims
	switch b.kind {
	case .Ooze_King:
		anims = &a.enemy[.Slime]
	case .Broodmother:
		anims = &a.enemy[.Bat]
	case .Warden:
		anims = &a.warden
	}
	body := &anims.run
	if b.state == .Hurt || (b.state == .Open && b.kind == .Warden) {
		body = &anims.hit
	} else if b.kind == .Warden && (b.state == .Idle || b.state == .Recover) {
		body = &anims.idle
	}
	animator_play(&b.anim, body)
	animator_update(&b.anim, dt)
	boss_touch_player(g)
}

@(private = "file")
ooze_update :: proc(g: ^Game, b: ^Boss, dt: f32) {
	m := &g.map_tiles
	p := &g.player
	switch b.state {
	case .Idle, .Recover:
		fall(m, b, dt)
		b.dir = p.pos.x < b.pos.x ? -1 : 1
		if b.timer <= 0 {
			b.state = .Wind_Up
			b.timer = 0.45
		}
	case .Wind_Up:
		b.squash = {1.25, 0.75}
		if b.timer <= 0 {
			b.state = .Attack
			dist := clamp(p.pos.x - b.pos.x, -150, 150)
			b.vel = {dist * 1.4 + b.dir * 30, -360 - f32(BOSS_HP - b.hp) * 30}
			b.squash = {0.75, 1.3}
		}
	case .Attack:
		r := boss_rect(b^)
		moved, hit := move_x(m, r, b.vel.x * dt)
		b.pos.x = moved.x + r.width / 2
		if hit {
			b.vel.x = -b.vel.x * 0.5
		}
		b.vel.y = min(b.vel.y + GRAVITY * dt, MAX_FALL)
		r = boss_rect(b^)
		moved2, landed, _ := move_y(m, r, b.vel.y * dt)
		b.pos.y = moved2.y + r.height
		if landed && b.vel.y > 0 {
			b.vel = {}
			b.state = .Open
			b.timer = 0.9
			b.squash = {1.4, 0.65}
			landing(g, b, {150, 230, 140, 255})
			for d in ([2]f32{-1, 1}) {
				append(&g.waves, Wave{pos = b.pos + {d * boss_rect(b^).width / 2, 0}, dir = d, life = 3})
			}
			if b.hp < BOSS_HP {
				append(&g.enemies, enemy_make({kind = .Slime, rect = {b.pos.x - 8 + b.dir * 20, b.pos.y - 16, 16, 16}}))
			}
		}
	case .Open:
		fall(m, b, dt)
		b.squash = {1.15 + 0.05 * math.sin(b.t * 20), 0.85}
		if b.timer <= 0 {
			b.state = .Idle
			b.timer = OOZE_WAIT[b.hp]
		}
	case .Waiting, .Hurt, .Dying:
	}
}

@(private = "file")
brood_update :: proc(g: ^Game, b: ^Boss, dt: f32) {
	m := &g.map_tiles
	p := &g.player
	switch b.state {
	case .Idle:
		// Sweeping back and forth along the top of the arena.
		b.pos.x += (b.home.x + math.sin(b.t * 0.9) * 120 - b.pos.x) * min(1, dt * 4)
		b.pos.y += (b.home.y + math.sin(b.t * 2.3) * 6 - b.pos.y) * min(1, dt * 4)
		b.dir = math.cos(b.t * 0.9) > 0 ? 1 : -1
		if b.timer <= 0 {
			b.state = .Wind_Up
			b.timer = 0.7
			b.target = p.pos
			play(&g.assets, .Slam)
			if b.hp < BOSS_HP {
				young := 0
				for e in g.enemies {
					if e.alive && e.kind == .Bat {
						young += 1
					}
				}
				if young < 2 {
					append(&g.enemies, enemy_make({kind = .Bat, rect = {b.pos.x - 8, b.pos.y - 30, 16, 16}}))
				}
			}
		}
	case .Wind_Up:
		// Hangs, shivering, and keeps watching you till the last moment.
		b.target = p.pos
		b.squash = {1.1 + 0.08 * math.sin(b.t * 40), 0.9}
		if b.timer <= 0 {
			b.state = .Attack
			d := rl.Vector2Normalize(b.target - b.pos)
			b.vel = d * BROOD_DIVE_SPEED[b.hp]
			if abs(d.x) > 0.05 {
				b.dir = math.sign(d.x)
			}
		}
	case .Attack:
		r := boss_rect(b^)
		moved, hit_x := move_x(m, r, b.vel.x * dt)
		b.pos.x = moved.x + r.width / 2
		r = boss_rect(b^)
		moved2, landed, _ := move_y(m, r, b.vel.y * dt)
		b.pos.y = moved2.y + r.height
		if landed || hit_x || b.pos.y > b.target.y + 40 {
			b.vel = {}
			b.state = .Open
			b.timer = 1.5
			b.squash = {1.3, 0.7}
			landing(g, b, {200, 200, 230, 255})
		}
	case .Open:
		b.squash = {1.1, 0.9 + 0.05 * math.sin(b.t * 18)}
		if b.timer <= 0 {
			b.state = .Recover
		}
	case .Recover:
		// Flaps back up to her perch.
		up := rl.Vector2{b.home.x + math.sin(b.t * 0.9) * 120, b.home.y} - b.pos
		if rl.Vector2Length(up) < 6 {
			b.state = .Idle
			b.timer = 1.6 - f32(BOSS_HP - b.hp) * 0.3
		} else {
			b.pos += rl.Vector2Normalize(up) * 110 * dt
		}
	case .Waiting, .Hurt, .Dying:
	}
}

@(private = "file")
warden_update :: proc(g: ^Game, b: ^Boss, dt: f32) {
	m := &g.map_tiles
	p := &g.player
	switch b.state {
	case .Idle, .Recover:
		fall(m, b, dt)
		b.dir = p.pos.x < b.pos.x ? -1 : 1
		if b.timer <= 0 {
			b.state = .Wind_Up
			b.timer = 0.6
		}
	case .Wind_Up:
		// Paws the ground, kicking up dust behind it.
		fall(m, b, dt)
		b.squash = {1.1, 0.92 + 0.04 * math.sin(b.t * 30)}
		if int(b.t * 20) % 3 == 0 {
			spawn_spark(g, b.pos - {b.dir * 20, 2}, {-b.dir, -0.6}, {200, 170, 150, 255}, 60, 1)
		}
		if b.timer <= 0 {
			b.state = .Attack
		}
	case .Attack:
		r := boss_rect(b^)
		moved, hit := move_x(m, r, b.dir * WARDEN_SPEED[b.hp] * dt)
		b.pos.x = moved.x + r.width / 2
		fall(m, b, dt)
		if int(b.t * 30) % 2 == 0 {
			spawn_spark(g, b.pos + {-b.dir * 18, -2}, {-b.dir, -0.4}, {220, 190, 160, 255}, 50, 1)
		}
		if hit {
			b.state = .Open
			b.timer = 2.6 // long enough to run the arena's length
			b.squash = {0.8, 1.15}
			landing(g, b, {200, 170, 150, 255})
			// The jolt shakes rocks loose: one straight over you, the rest
			// behind you, away from the Warden. Stepping out from under them
			// takes you toward it, so dodging and attacking are one move.
			// None before the first hit: learn the stomp first.
			count := b.hp < BOSS_HP ? 2 + (BOSS_HP - b.hp) : 0
			away: f32 = p.pos.x < b.pos.x ? -1 : 1
			offsets := [4]f32{0, 44, 88, 132}
			shift := rand.float32_range(-4, 4)
			for i in 0 ..< min(count, 4) {
				x := p.pos.x + away * offsets[i] + shift
				// Never on top of itself: its back stays clear to land on.
				if abs(x - b.pos.x) < 40 {
					continue
				}
				drop_rock(g, x)
			}
		}
	case .Open:
		fall(m, b, dt)
		if b.timer <= 0 {
			b.state = .Recover
			b.timer = 0.9
			b.dir = -b.dir
		}
	case .Waiting, .Hurt, .Dying:
	}
}

// A boss hitting the ground or a wall: dust, a thump, a shake.
@(private = "file")
landing :: proc(g: ^Game, b: ^Boss, colour: rl.Color) {
	g.shake = max(g.shake, 5)
	play(&g.assets, .Slam)
	haptic(.Stomp)
	spawn_burst(g, b.pos, colour, 14, 110, 1.3)
}

@(private = "file")
drop_rock :: proc(g: ^Game, x: f32) {
	m := &g.map_tiles
	tx := int(math.floor(x / TILE))
	if tx < 1 || tx >= m.width - 1 {
		return
	}
	// Hangs under the ceiling above that spot (or a few tiles over you).
	ty := int(math.floor(g.player.pos.y / TILE)) - 2
	for k := 0; k < 7 && ty > 0 && !is_blocking(tile_at(m, tx, ty - 1)); k += 1 {
		ty -= 1
	}
	floor := f32(m.height) * TILE
	for fy := ty; fy < m.height; fy += 1 {
		if is_blocking(tile_at(m, tx, fy)) {
			floor = f32(fy) * TILE
			break
		}
	}
	append(&g.rocks, Rock{pos = {x, f32(ty) * TILE + ROCK_R}, warn = 0.7, floor = floor})
}

@(private = "file")
fall :: proc(m: ^Tilemap, b: ^Boss, dt: f32) {
	b.vel.y = min(b.vel.y + GRAVITY * dt, MAX_FALL)
	r := boss_rect(b^)
	moved, landed, _ := move_y(m, r, b.vel.y * dt)
	b.pos.y = moved.y + r.height
	if landed {
		b.vel.y = 0
	}
}

// From above while it is open, a hit. While it is stunned, or recovering from
// a hit, bumping into it does nothing; any other touch is a death.
@(private = "file")
boss_touch_player :: proc(g: ^Game) {
	b := &g.boss
	p := &g.player
	if p.dead || b.state == .Waiting || b.state == .Hurt || b.state == .Dying {
		return
	}
	pr := player_rect(p^)
	br := boss_rect(b^)
	if !rl.CheckCollisionRecs(pr, br) {
		return
	}
	open := b.state == .Open || (b.kind == .Ooze_King && b.state == .Idle)
	from_above := p.vel.y > 0 && p.pos.y - p.vel.y * (1.0 / 60) <= br.y + 8
	if (b.state == .Open || (b.kind == .Broodmother && b.state == .Recover)) && !from_above {
		return // stunned, or flapping home: bumping into it is harmless
	}
	if b.state == .Recover && from_above {
		// Landing on it just as it shakes off the daze: no hit, but no
		// death either; you bounce off and away.
		p.pos.y = br.y
		player_bounce(g, STOMP_BOUNCE)
		p.vel.x = (p.pos.x < b.pos.x ? -1 : 1) * 170
		p.wall_stick = 0.35
		return
	}
	if open && from_above {
		b.hp -= 1
		b.state = .Hurt
		b.timer = BOSS_HURT
		b.squash = {1.5, 0.55}
		g.freeze = 0.08
		g.shake = max(g.shake, 6)
		p.pos.y = br.y
		player_bounce(g, STOMP_BOUNCE * 1.25)
		// Thrown clear to the side you were on, so you never come down on it.
		side: f32 = p.pos.x < b.pos.x ? -1 : 1
		p.vel.x = side * 170
		p.wall_stick = 0.35
		spawn_burst(g, {b.pos.x, br.y}, {255, 255, 255, 255}, 18, 150, 1.5)
		spawn_popup(g, {b.pos.x, br.y - 14}, {255, 230, 120, 255}, strings.clone_to_cstring(b.hp > 0 ? fmt.tprintf("%v LEFT", b.hp) : "DOWN!"))
		play(&g.assets, .Stomp)
		haptic(.Death)
		return
	}
	player_kill(g)
}

@(private = "file")
boss_defeat :: proc(g: ^Game) {
	b := &g.boss
	b.beaten = true
	b.state = .Dying
	g.shake = max(g.shake, 8)
	spawn_burst(g, b.pos - {0, 20}, {255, 240, 200, 255}, 40, 200, 1.8)
	spawn_poof(g, &g.assets.player.disappear, b.pos)
	spawn_confetti(g, b.pos - {0, 30}, 80)
	spawn_popup(g, g.level.exit - {0, 50}, {255, 230, 120, 255}, strings.clone_to_cstring("THE WAY IS OPEN"))
	play(&g.assets, .Clear)
	haptic(.Clear)
	clear(&g.rocks)
	clear(&g.waves)
	for &e in g.enemies {
		if e.alive {
			e.alive = false
			e.dying = 1
			e.vel = {0, -120}
		}
	}
}

// ------------------------------------------------------- waves and rocks ---

waves_update :: proc(g: ^Game, dt: f32) {
	m := &g.map_tiles
	pr := player_rect(g.player)
	live := 0
	for &w in g.waves {
		w.life -= dt
		w.pos.x += w.dir * WAVE_SPEED * dt
		ahead := tile_at(m, int(math.floor((w.pos.x + w.dir * 4) / TILE)), int(math.floor((w.pos.y - 4) / TILE)))
		below := tile_at(m, int(math.floor(w.pos.x / TILE)), int(math.floor((w.pos.y + 2) / TILE)))
		if w.life <= 0 || is_blocking(ahead) || !is_blocking(below) {
			spawn_burst(g, w.pos - {0, 4}, {150, 230, 140, 255}, 4, 50, 0.9)
			continue
		}
		r := rl.Rectangle{w.pos.x - WAVE_SIZE.x / 2, w.pos.y - WAVE_SIZE.y, WAVE_SIZE.x, WAVE_SIZE.y}
		if !g.player.dead && rl.CheckCollisionRecs(pr, r) {
			player_kill(g)
		}
		g.waves[live] = w
		live += 1
	}
	resize(&g.waves, live)

	live = 0
	for &r in g.rocks {
		if r.warn > 0 {
			r.warn -= dt
		} else {
			r.vel = min(r.vel + GRAVITY * dt, MAX_FALL)
			r.pos.y += r.vel * dt
		}
		if r.pos.y + ROCK_R >= r.floor {
			spawn_burst(g, {r.pos.x, r.floor - 2}, {190, 170, 160, 255}, 6, 70, 1.0)
			continue
		}
		if !g.player.dead && r.warn <= 0 && rl.CheckCollisionCircleRec(r.pos, ROCK_R - 1, pr) {
			player_kill(g)
		}
		g.rocks[live] = r
		live += 1
	}
	resize(&g.rocks, live)
}

// ----------------------------------------------------------------- draw ---

boss_draw :: proc(g: ^Game) {
	b := g.boss
	for w in g.waves {
		for k in 0 ..< 3 {
			h := WAVE_SIZE.y * (1 - f32(k) * 0.25)
			x := w.pos.x - w.dir * f32(k) * 4
			rl.DrawEllipse(i32(x), i32(w.pos.y - h / 2), 5 - f32(k), h / 2, {120 + u8(k) * 40, 220, 120, u8(240 - k * 50)})
		}
	}
	for r in g.rocks {
		// The mark where it will land, darkening as it comes.
		k: f32 = r.warn > 0 ? 1 - r.warn / 0.7 : 1
		rl.DrawEllipse(i32(r.pos.x), i32(r.floor - 1), 4 + 4 * k, 1.5, {40, 20, 30, u8(90 + 100 * k)})
		shake: f32 = r.warn > 0 ? math.sin(g.time * 60) : 0
		c := r.pos + {shake, 0}
		rl.DrawCircleV(c, ROCK_R + 1, {40, 26, 34, 255})
		rl.DrawCircleV(c, ROCK_R, {150, 120, 130, 255})
		rl.DrawCircleV(c - {2, 2}, ROCK_R * 0.45, {200, 175, 180, 255})
	}
	if !b.present || b.beaten || b.anim.anim == nil {
		return
	}
	tint := rl.WHITE
	switch {
	case b.state == .Hurt && int(b.timer * 16) % 2 == 0:
		tint = {255, 140, 140, 255}
	case b.state == .Wind_Up:
		tint = b.kind == .Broodmother ? rl.Color{255, 120, 120, 255} : rl.Color{255, 210, 170, 255}
	case b.state == .Open:
		tint = {225, 255, 225, 255} // open: a little brighter
	}
	scale: f32
	switch b.kind {
	case .Ooze_King:
		scale = OOZE_SCALE[clamp(b.hp, 0, BOSS_HP)]
	case .Broodmother:
		scale = BROOD_SCALE
	case .Warden:
		scale = WARDEN_SCALE
	}
	a := b.anim.anim
	dest := rl.Rectangle{b.pos.x, b.pos.y + 1, a.frame_w * scale * b.squash.x, a.frame_h * scale * b.squash.y}
	origin := rl.Vector2{dest.width / 2, a.anchor_y * scale * b.squash.y}
	rl.DrawTexturePro(a.texture, anim_source(a, b.anim.frame, b.dir > 0), dest, origin, 0, tint)

	if b.state == .Open {
		// Stars circling its head say "now".
		top := boss_rect(b).y - 6
		for i in 0 ..< 3 {
			angle := g.time * 5 + f32(i) * math.TAU / 3
			pos := rl.Vector2{b.pos.x + math.cos(angle) * 14, top + math.sin(angle) * 4}
			rl.DrawPoly(pos, 4, 2.5, angle * 30, {255, 230, 120, 255})
		}
	}
	if b.kind == .Ooze_King {
		draw_crown(b, scale)
	}
}

@(private = "file")
draw_crown :: proc(b: Boss, s: f32) {
	top := b.pos.y - boss_rect(b).height * b.squash.y - 4
	crown := rl.Color{255, 214, 80, 255}
	cx := b.pos.x
	w := 6 * s
	tri({cx - w, top}, {cx - w * 0.5, top - 6 * s * 0.6}, {cx - w * 0.2, top}, crown)
	tri({cx - w * 0.3, top}, {cx, top - 8 * s * 0.6}, {cx + w * 0.3, top}, crown)
	tri({cx + w * 0.2, top}, {cx + w * 0.5, top - 6 * s * 0.6}, {cx + w, top}, crown)
	rl.DrawRectangleV({cx - w, top}, {w * 2, 2.5}, crown)
	rl.DrawCircleV({cx, top - 5 * s * 0.6}, 1.2, {255, 90, 120, 255})
}

BOSS_INTRO_TIME :: 2.4

// The boss's name across the screen when it wakes, then its hits left as
// hearts at the top.
boss_hud_draw :: proc(g: ^Game) {
	b := g.boss
	if !b.present || b.state == .Waiting {
		return
	}
	a := &g.assets
	view := view_size()
	if g.boss_intro > 0 {
		t := g.boss_intro
		alpha := u8(clamp(min(t, BOSS_INTRO_TIME - t) * 3, 0, 1) * 255)
		draw_text_outlined_centered(a, boss_name(b.kind), 64, 16, {255, 214, 110, alpha}, {255, 240, 170, alpha})
	}
	if b.beaten {
		return
	}
	for i in 0 ..< b.max_hp {
		x := view.x / 2 - f32(b.max_hp) * 6 + f32(i) * 12
		draw_heart(x, 8, {40, 26, 34, 200})
		draw_heart(x, 7, i < b.hp ? rl.Color{255, 110, 130, 255} : rl.Color{90, 80, 100, 200})
	}
}
