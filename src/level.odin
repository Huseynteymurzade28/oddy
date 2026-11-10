package game

import "core:fmt"
import "core:math"
import "core:strings"
import rl "../libs/raylib"

/*
The level being played: built from one `Level_Data` (see `ldtk.odin`), plus
what changes while you play it: which checkpoints are lit, and the fruit.

Gems are the little reward everywhere: lines of them trace good paths, crates
burst into them, and a run of them picked up quickly climbs the scale. Gems
and broken crates stay taken when you die; only a restart puts them back.

Fruit works the way it does in Celeste. Touch one and it follows you; it is
only yours once you have stood on solid ground with it for a moment (or
reached a checkpoint or the end). Die first and it goes back where it was.
*/

// A checkpoint is a lantern on a post. Touching it lights it, and it stays
// lit; the last one lit is where you come back.
Checkpoint :: struct {
	pos:    rl.Vector2, // the foot of the post, which is also where you respawn
	active: bool, // the one you come back to
	lit:    bool,
	flare:  f32, // the flash of lighting, fading
}

LANTERN_OFFSET :: rl.Vector2{5, -24} // from the foot of the post to the lantern

Level :: struct {
	index:       int, // into `g.levels`
	name:        cstring, // these three are borrowed from the level's data
	zone:        Zone,
	hints:       []Hint,
	spawn:       rl.Vector2,
	exit:        rl.Vector2,
	secret_exit: rl.Vector2, // zero for none
	checkpoints: [dynamic]Checkpoint,
	fruit:       [dynamic]Fruit,
	kept:        u64, // fruit kept on this attempt, bit per fruit
	gems:        [dynamic]Gem,
	gems_got:    int, // picked up, counting the ones out of crates
	gems_total:  int,
	gem_chain:   int, // gems picked up in quick succession
	gem_timer:   f32, // time left to keep the chain going
}

Gem :: struct {
	pos:   rl.Vector2,
	taken: bool,
	pop:   f32, // > 0 for the moment it flies up after being taken
}

GEMS_PER_CRATE :: 3
GEM_CHAIN_TIME :: 0.6

Fruit_State :: enum u8 {
	Waiting,
	Following,
	Kept,
}

Fruit :: struct {
	home:  rl.Vector2,
	pos:   rl.Vector2,
	state: Fruit_State,
	had:   bool, // already kept on an earlier visit: drawn as a ghost
	kind:  int,
}

// What the last clear earned, for the card that says so.
Clear_Result :: struct {
	secret:     bool, // left through the secret exit
	new_medals: Medals,
	medals:     Medals,
	fruit:      int, // kept, of
	fruit_of:   int,
	gems:       int,
	gems_of:    int,
	new_skin:   bool,
}

FRUIT_SECURE :: 0.25 // seconds on solid ground with a fruit before it is yours
FRUIT_REACH :: 11.0

CHECKPOINT_REACH :: rl.Vector2{14, 30}
EXIT_REACH :: rl.Vector2{16, 34}

level_destroy :: proc(l: ^Level) {
	delete(l.checkpoints)
	delete(l.fruit)
	delete(l.gems)
	l^ = {}
}

// The rectangle you have to touch to take a checkpoint or finish the level.
flag_rect :: proc(pos, reach: rl.Vector2) -> rl.Rectangle {
	return {pos.x - reach.x / 2, pos.y - reach.y, reach.x, reach.y}
}

// (Re)reads the levels file. If it cannot be read the game still starts, in a
// bare room whose only hint says what went wrong.
levels_reload :: proc(g: ^Game) {
	levels_destroy(&g.levels)
	levels, err := ldtk_load(LEVELS_PATH)
	if err != "" {
		fmt.eprintln("levels:", err)
		levels = fallback_levels(err)
	}
	g.levels = levels
}

@(private = "file")
fallback_levels :: proc(err: string) -> [dynamic]Level_Data {
	d := Level_Data {
		ident  = strings.clone("Fallback"),
		name   = strings.clone_to_cstring("NO LEVELS"),
		width  = 30,
		height = 12,
		spawn  = {5 * TILE, 10 * TILE},
		exit   = {26 * TILE, 10 * TILE},
	}
	d.tiles = make([]Tile, d.width * d.height)
	for x in 0 ..< d.width {
		d.tiles[10 * d.width + x] = .Rock
		d.tiles[11 * d.width + x] = .Rock
	}
	append(&d.hints, Hint{pos = {15 * TILE, 6 * TILE}, text = strings.clone_to_cstring(strings.to_upper(err, context.temp_allocator))})
	levels: [dynamic]Level_Data
	append(&levels, d)
	return levels
}

// Builds level `index` and puts you at its start.
level_enter :: proc(g: ^Game, wanted: int) {
	index := clamp(wanted, 0, len(g.levels) - 1)
	d := &g.levels[index]

	level_destroy(&g.level)
	tilemap_destroy(&g.map_tiles)
	g.map_tiles = tilemap_make(d.width, d.height)
	copy(g.map_tiles.tiles, d.tiles)

	g.level = Level {
		index = index,
		name  = d.name,
		zone  = d.zone,
		hints = d.hints[:],
		spawn       = d.spawn,
		exit        = d.exit,
		secret_exit = d.secret_exit,
	}
	for c in d.checkpoints {
		append(&g.level.checkpoints, Checkpoint{pos = c})
	}
	had := save_level(&g.save, d.ident).fruit
	for f, i in d.fruit {
		append(&g.level.fruit, Fruit {
			home = f,
			pos  = f,
			had  = had & (1 << u64(i)) != 0,
			kind = (i + d.number * 3) % FRUIT_KINDS,
		})
	}
	g.exit_anim = {}
	decor_scatter(g)
	lighting_bake(g)
	level_restart(g)
}

level_has_next :: proc(g: ^Game) -> bool {
	_, ok := next_level(g, g.level.index)
	return ok
}

// Puts every trap and creature back where the level file has it. Done on
// every death, so a section plays the same way each time.
level_reset_things :: proc(g: ^Game) {
	clear(&g.things)
	clear(&g.enemies)
	clear(&g.arrows)
	clear(&g.waves)
	clear(&g.rocks)
	// The boss comes back at full strength, unless it is already beaten.
	d := &g.levels[g.level.index]
	if d.has_boss && !g.boss.beaten {
		g.boss = boss_make(d.boss, d.boss_pos)
	} else if !d.has_boss {
		g.boss = {}
	}
	for d in g.levels[g.level.index].things {
		if d.kind >= FIRST_CREATURE {
			append(&g.enemies, enemy_make(d))
		} else {
			append(&g.things, thing_make(d))
		}
	}
}

// Puts the level back the way it was at the start: checkpoints unlit, the
// clock and the death count at zero, you at the start.
level_restart :: proc(g: ^Game) {
	for &c in g.level.checkpoints {
		c.active = false
		c.lit = false
	}
	for &f in g.level.fruit {
		f.state = .Waiting
		f.pos = f.home
	}
	g.level.kept = 0
	g.boss = {} // a restart brings a beaten boss back too
	// A restart puts the crates and gems back; a death does not.
	d := &g.levels[g.level.index]
	copy(g.map_tiles.tiles, d.tiles)
	clear(&g.level.gems)
	for p in d.gems {
		append(&g.level.gems, Gem{pos = p})
	}
	g.level.gems_got = 0
	g.level.gems_total = len(d.gems) + d.crates * GEMS_PER_CRATE
	g.level.gem_chain = 0
	clear(&g.chips)
	clear(&g.confetti)
	g.fruit_safe = 0
	g.respawn = g.level.spawn
	g.deaths = 0
	g.deaths_here = 0
	g.level_time = 0
	g.level_intro = LEVEL_INTRO_TIME
	clear(&g.sparks)
	level_reset_things(g)
	player_init(&g.player, g.respawn)
	camera_snap(g)
}

// Fruit being carried is dropped when you die: back to where it was.
level_drop_fruit :: proc(g: ^Game) {
	for &f in g.level.fruit {
		if f.state == .Following {
			f.state = .Waiting
			f.pos = f.home
		}
	}
	g.fruit_safe = 0
}

@(private = "file")
keep_carried_fruit :: proc(g: ^Game) {
	for &f, i in g.level.fruit {
		if f.state != .Following {
			continue
		}
		f.state = .Kept
		g.level.kept |= 1 << u64(i)
		spawn_poof(g, &g.assets.fruit_got, f.pos)
		play(&g.assets, .Refill)
	}
}

@(private = "file")
fruit_update :: proc(g: ^Game, dt: f32) {
	p := &g.player
	pr := player_rect(p^)
	carried := 0
	for &f in g.level.fruit {
		switch f.state {
		case .Waiting:
			f.pos = f.home + {0, math.sin(g.time * 2.5 + f.home.x) * 2}
			if !p.dead && rl.CheckCollisionCircleRec(f.pos, FRUIT_REACH / 2, pr) {
				f.state = .Following
				spawn_burst(g, f.pos, {255, 240, 200, 255}, 6, 60, 0.9)
				play(&g.assets, .Menu_Move)
			}
		case .Following:
			// A little train behind your head, each one a step further back.
			carried += 1
			behind: f32 = p.flip ? 1 : -1
			want := player_centre(p^) + {behind * f32(8 + carried * 10), -14 - f32(carried) * 2}
			f.pos += (want - f.pos) * min(1, dt * 7)
		case .Kept:
		}
	}
	// Standing still on rock (not a platform, which may be about to drop)
	// makes it yours.
	if carried > 0 && p.grounded && p.riding < 0 && !p.dead {
		g.fruit_safe += dt
		if g.fruit_safe >= FRUIT_SECURE {
			keep_carried_fruit(g)
			g.fruit_safe = 0
		}
	} else {
		g.fruit_safe = 0
	}
}

@(private = "file")
take_gem :: proc(g: ^Game, pos: rl.Vector2, count: int) {
	l := &g.level
	l.gems_got += count
	// Quick pickups climb the scale, a semitone at a time, up to an octave.
	pitch := math.pow(f32(1.0595), f32(min(l.gem_chain, 12)))
	play_pitched(&g.assets, .Gem, pitch)
	l.gem_chain += 1
	l.gem_timer = GEM_CHAIN_TIME
	spawn_burst(g, pos, {160, 240, 255, 255}, 4, 50, 0.8)
}

@(private = "file")
gems_update :: proc(g: ^Game, dt: f32) {
	l := &g.level
	l.gem_timer -= dt
	if l.gem_timer <= 0 {
		l.gem_chain = 0
	}
	if g.player.dead {
		return
	}
	pr := player_rect(g.player)
	for &gem in l.gems {
		gem.pop = max(0, gem.pop - dt)
		if !gem.taken && rl.CheckCollisionCircleRec(gem.pos, 7, pr) {
			gem.taken = true
			gem.pop = 0.3
			take_gem(g, gem.pos, 1)
		}
	}
}

// Breaks the crate at a tile, if there is one: splinters, a thump, and its
// gems straight into your count. Returns whether it broke anything.
crate_break :: proc(g: ^Game, tx, ty: int, push: rl.Vector2) -> bool {
	if tile_at(&g.map_tiles, tx, ty) != .Crate {
		return false
	}
	tile_set(&g.map_tiles, tx, ty, .Empty)
	centre := rl.Vector2{f32(tx) * TILE + TILE / 2, f32(ty) * TILE + TILE / 2}
	spawn_chips(g, centre, push)
	spawn_burst(g, centre, {255, 240, 200, 255}, 8, 90, 1.0)
	spawn_popup(g, centre - {0, 10}, {160, 240, 255, 255}, strings.clone_to_cstring(fmt.tprintf("+%v", GEMS_PER_CRATE)))
	play(&g.assets, .Crate)
	take_gem(g, centre, GEMS_PER_CRATE)
	g.shake = max(g.shake, 2.5)
	g.freeze = max(g.freeze, 0.025)
	haptic(.Stomp)
	return true
}

// Breaks every crate the rectangle overlaps. Used with the player's box
// nudged a pixel toward where it was going.
crates_break_in :: proc(g: ^Game, r: rl.Rectangle, push: rl.Vector2) -> bool {
	broke := false
	x0, y0 := int(math.floor(r.x / TILE)), int(math.floor(r.y / TILE))
	x1, y1 := int(math.floor((r.x + r.width - 0.01) / TILE)), int(math.floor((r.y + r.height - 0.01) / TILE))
	for ty in y0 ..= y1 {
		for tx in x0 ..= x1 {
			if crate_break(g, tx, ty, push) {
				broke = true
			}
		}
	}
	return broke
}

level_draw_gems :: proc(g: ^Game) {
	anim := &g.assets.gem
	for gem, i in g.level.gems {
		if gem.taken && gem.pop <= 0 {
			continue
		}
		frame := (int(g.time / anim.frame_time) + i * 2) % anim.count
		pos := gem.pos + {0, math.sin(g.time * 3 + f32(i) * 0.6) * 1.5}
		if gem.taken {
			// Flies up and fades as it is taken.
			k := gem.pop / 0.3
			pos.y -= (1 - k) * 14
			anim_draw_frame(anim, frame, pos, false, {255, 255, 255, u8(255 * k)})
			continue
		}
		anim_draw_frame(anim, frame, pos, false)
	}
}

// Checkpoints are taken by touching them; the flag at the end finishes the
// level, and a secret exit finishes it too, opening a hidden level.
level_update :: proc(g: ^Game, dt: f32) {
	fruit_update(g, dt)
	gems_update(g, dt)
	if g.player.dead {
		return
	}
	pr := player_rect(g.player)
	for &c in g.level.checkpoints {
		if c.active || !rl.CheckCollisionRecs(pr, flag_rect(c.pos, CHECKPOINT_REACH)) {
			continue
		}
		for &other in g.level.checkpoints {
			other.active = false
		}
		c.active = true
		c.lit = true
		g.deaths_here = 0
		c.flare = 1
		g.respawn = c.pos
		keep_carried_fruit(g)
		spawn_burst(g, c.pos + LANTERN_OFFSET, {255, 230, 140, 255}, 16, 90, 1.2)
		play(&g.assets, .Checkpoint)
		haptic(.Checkpoint)
	}
	exit_open := !g.boss.present || g.boss.beaten
	if exit_open && rl.CheckCollisionRecs(pr, flag_rect(g.level.exit, EXIT_REACH)) {
		level_clear(g, false)
	} else if g.level.secret_exit != {} && rl.CheckCollisionRecs(pr, flag_rect(g.level.secret_exit, EXIT_REACH)) {
		level_clear(g, true)
	}
}

@(private = "file")
level_clear :: proc(g: ^Game, secret: bool) {
	keep_carried_fruit(g)
	d := &g.levels[g.level.index]
	index := g.level.index
	medals_before := level_medals(g, index)
	skins_before: [Skin]bool
	for s in Skin {
		skins_before[s] = skin_unlocked(g, s)
	}

	save_record_clear(&g.save, d.ident, g.level_time, g.deaths, g.level.kept, g.level.gems_got)
	if secret && d.unlocks != "" {
		save_find_secret(&g.save, d.unlocks)
	}
	save_write(&g.save)

	medals := level_medals(g, index)
	g.clear = Clear_Result {
		secret     = secret,
		medals     = medals,
		new_medals = medals - medals_before,
		fruit      = fruit_count(save_level(&g.save, d.ident).fruit),
		fruit_of   = len(d.fruit),
		gems       = g.level.gems_got,
		gems_of    = g.level.gems_total,
	}
	for s in Skin {
		if !skins_before[s] && skin_unlocked(g, s) {
			g.clear.new_skin = true
		}
	}

	at := secret ? g.level.secret_exit : g.level.exit
	colour := secret ? rl.Color{200, 150, 255, 255} : rl.Color{255, 214, 110, 255}
	spawn_burst(g, at - {0, 24}, colour, 30, 140, 1.5)
	if !secret {
		animator_restart(&g.exit_anim, &g.assets.marks.end_pressed)
	}
	spawn_confetti(g, at - {0, 30}, 60)
	// And a shower from the top of the screen, over the card.
	view := camera_view(g)
	for i in 0 ..< 6 {
		spawn_confetti(g, {view.x + view.width * (f32(i) + 0.5) / 6, view.y - 6}, 12)
	}
	play(&g.assets, .Clear)
	haptic(.Clear)
	game_set_state(g, .Cleared)
}

level_draw_flags :: proc(g: ^Game) {
	m := &g.assets.marks
	for &c in g.level.checkpoints {
		c.flare = max(0, c.flare - rl.GetFrameTime() * 1.5)
		draw_lantern(g, c)
	}
	if g.exit_anim.anim != nil {
		animator_update(&g.exit_anim, rl.GetFrameTime())
		animator_draw(g.exit_anim, g.level.exit, false)
	} else if g.boss.present && !g.boss.beaten {
		// Shut until the boss is down: a grey, sleeping trophy.
		anim_draw_frame(&m.end, 0, g.level.exit, false, {110, 104, 130, 160})
	} else {
		anim_draw_frame(&m.end, 0, g.level.exit, false)
	}
	// The secret exit is the same trophy in another colour, pulsing.
	if g.level.secret_exit != {} {
		pulse := u8(200 + 55 * math.sin(g.time * 4))
		anim_draw_frame(&m.end, 0, g.level.secret_exit, false, {190, 140, pulse, 255})
	}
}

level_draw_fruit :: proc(g: ^Game) {
	for f in g.level.fruit {
		if f.state == .Kept {
			continue
		}
		anim := &g.assets.fruit[f.kind]
		frame := int(g.time / anim.frame_time) % anim.count
		tint := rl.WHITE
		if f.had && f.state == .Waiting {
			tint = {255, 255, 255, 110} // kept on an earlier visit
		}
		anim_draw_frame(anim, frame, f.pos, false, tint)
	}
}

// A post with an arm, and a little lantern hanging from it: dim glass while
// it is waiting, a flickering flame and warm light once lit, with fireflies
// drifting round it.
@(private = "file")
draw_lantern :: proc(g: ^Game, c: Checkpoint) {
	wood := rl.Color{122, 82, 52, 255}
	dark := rl.Color{61, 36, 24, 255}
	foot := c.pos
	// The post and its arm.
	rl.DrawRectangleV({foot.x - 2, foot.y - 30}, {3, 30}, dark)
	rl.DrawRectangleV({foot.x - 1, foot.y - 30}, {1, 30}, wood)
	rl.DrawRectangleV({foot.x - 2, foot.y - 31}, {9, 2}, dark)
	rl.DrawRectangleV({foot.x - 4, foot.y - 1}, {7, 1}, dark)
	lantern := foot + LANTERN_OFFSET
	sway := math.sin(g.time * 1.7 + foot.x * 0.05) * (c.lit ? 0.6 : 0.3)
	lantern.x += sway
	rl.DrawLineV({foot.x + 5, foot.y - 29}, lantern - {0, 4}, dark) // the hook
	body := rl.Rectangle{lantern.x - 3.5, lantern.y - 4, 7, 9}
	if c.lit {
		flicker := 0.85 + 0.15 * math.sin(g.time * 13 + foot.x)
		rl.BeginBlendMode(.ADDITIVE)
		glow := u8(60 * flicker + 80 * c.flare)
		rl.DrawCircleGradient(lantern + {0, 0.5}, 18 + 10 * c.flare, {255, 190, 100, glow}, {0, 0, 0, 0})
		rl.EndBlendMode()
		rl.DrawRectangleRec(body, {255, 214, 130, 255})
		rl.DrawRectangleV({lantern.x - 1.5, lantern.y - 1 + (1 - flicker) * 2}, {3, 4}, {255, 250, 220, 255})
	} else {
		rl.DrawRectangleRec(body, {110, 106, 120, 255})
		rl.DrawRectangleV({lantern.x - 2.5, lantern.y - 3}, {2, 3}, {150, 146, 160, 255})
	}
	rl.DrawRectangleLinesEx(body, 1, dark)
	rl.DrawRectangleV({lantern.x - 4.5, lantern.y - 5}, {9, 2}, dark) // cap
	rl.DrawRectangleV({lantern.x - 2.5, lantern.y + 5}, {5, 1.5}, dark) // base
	if c.lit {
		// Fireflies keep it company.
		rl.BeginBlendMode(.ADDITIVE)
		for i in 0 ..< 3 {
			t := g.time * 0.8 + f32(i) * 2.1 + foot.x
			pos := lantern + {math.cos(t) * (10 + f32(i) * 3), math.sin(t * 1.3) * 7 - 2}
			a := u8(120 + 100 * math.sin(t * 4))
			rl.DrawCircleV(pos, 1, {240, 255, 150, a})
			rl.DrawCircleV(pos, 2.5, {240, 255, 150, a / 4})
		}
		rl.EndBlendMode()
	}
}

// The hints float over the level in its own small type, lit or not.
level_draw_hints :: proc(g: ^Game) {
	a := &g.assets
	for h in g.level.hints {
		w := rl.MeasureTextEx(a.font, h.text, 8, 1).x
		pos := rl.Vector2{math.round(h.pos.x - w / 2), h.pos.y - 10}
		// A dark outline all round: readable over sky, grass and rock alike.
		ink := rl.Color{40, 26, 34, 230}
		for d in ([8]rl.Vector2{{-1, 0}, {1, 0}, {0, -1}, {0, 1}, {-1, -1}, {1, -1}, {-1, 1}, {1, 1}}) {
			rl.DrawTextEx(a.font, h.text, pos + d, 8, 1, ink)
		}
		rl.DrawTextEx(a.font, h.text, pos + {0, 2}, 8, 1, ink)
		rl.DrawTextEx(a.font, h.text, pos, 8, 1, {255, 250, 232, 255})
	}
}
