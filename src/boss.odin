package game

import "core:fmt"
import "core:math"
import "core:strings"
import rl "../libs/raylib"

/*
The bosses: the last level of each world. No gun, so every one of them is
beaten the platformer way, by landing on it at the right moment. Each fight
has a tell for every move, a window where the boss is open, and a short
breather after each hit. Dying puts the boss back at full strength.

The level's exit stays shut until the boss is down, then opens with a shower
of confetti.

  Ooze_King   (world 1) A slime the size of a house. It squats, then hops at
              you; every landing sends a ripple along the floor to jump.
              Just after it lands it sags, and its top is open: land on it.
              Each hit shrinks it and makes it quicker; from the second hit
              on it sheds small slimes.

Placed in LDtk as an entity named after its kind, standing on the bottom of
its rectangle.
*/

Boss_Kind :: enum u8 {
	Ooze_King,
}

Boss_State :: enum u8 {
	Waiting, // before the fight: until you are in the arena
	Idle,
	Wind_Up, // the tell
	Hop,
	Sag, // just landed: the open window
	Hurt,
	Dying,
}

Boss :: struct {
	kind:    Boss_Kind,
	home:    rl.Vector2,
	pos:     rl.Vector2, // feet, centred
	vel:     rl.Vector2,
	dir:     f32,
	hp:      int,
	max_hp:  int,
	state:   Boss_State,
	timer:   f32,
	t:       f32,
	squash:  rl.Vector2, // squash and stretch of the body
	anim:    Animator,
	present: bool, // the level has a boss
	beaten:  bool,
}

// A ripple along the floor from a landing: low, so a hop clears it.
Wave :: struct {
	pos:  rl.Vector2, // on the floor
	dir:  f32,
	life: f32,
}

OOZE_HP :: 3
OOZE_SCALE := [OOZE_HP + 1]f32{1.6, 2.0, 2.5, 3.0} // by hits left
OOZE_WAIT := [OOZE_HP + 1]f32{0.3, 0.45, 0.65, 0.9}
OOZE_WIND_UP :: 0.45
OOZE_SAG :: 0.9
OOZE_HURT :: 1.0
WAVE_SPEED :: 150.0
WAVE_SIZE :: rl.Vector2{12, 9}

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
		hp      = OOZE_HP,
		max_hp  = OOZE_HP,
		state   = .Waiting,
		squash  = {1, 1},
		present = true,
	}
}

boss_name :: proc(kind: Boss_Kind) -> cstring {
	switch kind {
	case .Ooze_King:
		return "THE OOZE KING"
	}
	return ""
}

boss_rect :: proc(b: Boss) -> rl.Rectangle {
	s := OOZE_SCALE[clamp(b.hp, 0, OOZE_HP)]
	w, h := 22 * s, 15 * s
	return {b.pos.x - w / 2, b.pos.y - h, w, h}
}

boss_update :: proc(g: ^Game, dt: f32) {
	b := &g.boss
	if !b.present || b.beaten {
		return
	}
	m := &g.map_tiles
	p := &g.player
	a := &g.assets
	b.t += dt
	b.timer -= dt
	b.squash += (rl.Vector2{1, 1} - b.squash) * min(1, dt * 10)

	switch b.state {
	case .Waiting:
		// It wakes a moment into the level, or sooner if you walk up to it.
		if !p.dead && (abs(p.pos.x - b.pos.x) < view_size().x * 0.6 || g.level_time > 1.0) {
			b.state = .Idle
			b.timer = 1.2
			g.boss_intro = BOSS_INTRO_TIME
			g.shake = max(g.shake, 3)
			play(a, .Slam)
		}
	case .Idle:
		fall(m, b, dt)
		b.dir = p.pos.x < b.pos.x ? -1 : 1
		if b.timer <= 0 {
			b.state = .Wind_Up
			b.timer = OOZE_WIND_UP
		}
	case .Wind_Up:
		// Squats down, shivering: the tell for the hop.
		b.squash = {1.25, 0.75}
		if b.timer <= 0 {
			b.state = .Hop
			dist := clamp(p.pos.x - b.pos.x, -150, 150)
			b.vel = {dist * 1.4 + b.dir * 30, -360 - f32(OOZE_HP - b.hp) * 30}
			b.squash = {0.75, 1.3}
		}
	case .Hop:
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
			b.state = .Sag
			b.timer = OOZE_SAG
			b.squash = {1.4, 0.65}
			g.shake = max(g.shake, 5)
			play(a, .Slam)
			haptic(.Stomp)
			spawn_burst(g, b.pos, {150, 230, 140, 255}, 14, 110, 1.3)
			for d in ([2]f32{-1, 1}) {
				append(&g.waves, Wave{pos = b.pos + {d * boss_rect(b^).width / 2, 0}, dir = d, life = 3})
			}
			if b.hp < OOZE_HP {
				// Sheds a little slime from the second hit on.
				append(&g.enemies, enemy_make({kind = .Slime, rect = {b.pos.x - 8 + b.dir * 20, b.pos.y - 16, 16, 16}}))
			}
		}
	case .Sag:
		fall(m, b, dt)
		b.squash = {1.15 + 0.05 * math.sin(b.t * 20), 0.85}
		if b.timer <= 0 {
			b.state = .Idle
			b.timer = OOZE_WAIT[b.hp]
		}
	case .Hurt:
		fall(m, b, dt)
		if b.timer <= 0 {
			if b.hp <= 0 {
				boss_defeat(g)
				return
			}
			b.state = .Idle
			b.timer = OOZE_WAIT[b.hp]
		}
	case .Dying:
	}

	animator_play(&b.anim, b.state == .Hurt ? &a.enemy[.Slime].hit : &a.enemy[.Slime].run)
	animator_update(&b.anim, dt)
	boss_touch_player(g)
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

// Its top is open while it sags after a landing, and while it stands idle;
// it is all danger while it squats to hop or is in the air. A hit gives it
// a moment to recover, during which it cannot hurt you.
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
	open := b.state == .Sag || b.state == .Idle
	from_above := p.vel.y > 0 && p.pos.y - p.vel.y * (1.0 / 60) <= br.y + 8
	if open && from_above {
		b.hp -= 1
		b.state = .Hurt
		b.timer = OOZE_HURT
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
	spawn_burst(g, b.pos - {0, 20}, {150, 230, 140, 255}, 40, 200, 1.8)
	spawn_poof(g, &g.assets.player.disappear, b.pos)
	spawn_confetti(g, b.pos - {0, 30}, 80)
	spawn_popup(g, g.level.exit - {0, 50}, {255, 230, 120, 255}, strings.clone_to_cstring("THE WAY IS OPEN"))
	play(&g.assets, .Clear)
	haptic(.Clear)
	// The small slimes go with it.
	for &e in g.enemies {
		if e.alive {
			e.alive = false
			e.dying = 1
			e.vel = {0, -120}
		}
	}
}

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
}

boss_draw :: proc(g: ^Game) {
	b := g.boss
	for w in g.waves {
		// A green crest rolling along the floor.
		for k in 0 ..< 3 {
			h := WAVE_SIZE.y * (1 - f32(k) * 0.25)
			x := w.pos.x - w.dir * f32(k) * 4
			rl.DrawEllipse(i32(x), i32(w.pos.y - h / 2), 5 - f32(k), h / 2, {120 + u8(k) * 40, 220, 120, u8(240 - k * 50)})
		}
	}
	if !b.present || b.beaten || b.anim.anim == nil {
		return
	}
	s := OOZE_SCALE[clamp(b.hp, 0, OOZE_HP)]
	tint := rl.WHITE
	switch {
	case b.state == .Hurt && int(b.timer * 16) % 2 == 0:
		tint = {255, 140, 140, 255}
	case b.state == .Wind_Up:
		tint = {255, 220, 180, 255}
	case b.state == .Sag:
		tint = {220, 255, 220, 255} // open: a little brighter
	}
	a := b.anim.anim
	dest := rl.Rectangle{b.pos.x, b.pos.y + 1, a.frame_w * s * b.squash.x, a.frame_h * s * b.squash.y}
	origin := rl.Vector2{dest.width / 2, a.anchor_y * s * b.squash.y}
	rl.DrawTexturePro(a.texture, anim_source(a, b.anim.frame, b.dir > 0), dest, origin, 0, tint)
	// A crown, so there is no mistaking who this is.
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
