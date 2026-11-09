package game

import "core:fmt"
import "core:math"
import "core:strings"
import rl "../libs/raylib"

/*
The level being played: built from one `Level_Data` (see `ldtk.odin`), plus
what changes while you play it: which checkpoints are lit, and the fruit.

Fruit works the way it does in Celeste. Touch one and it follows you; it is
only yours once you have stood on solid ground with it for a moment (or
reached a checkpoint or the end). Die first and it goes back where it was.
*/

Checkpoint :: struct {
	pos:    rl.Vector2, // the foot of the flag, which is also where you respawn
	active: bool,
	anim:   Animator, // the flag going up, then flying
}

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
}

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
	new_skin:   bool,
}

FRUIT_SECURE :: 0.25 // seconds on solid ground with a fruit before it is yours
FRUIT_REACH :: 11.0

CHECKPOINT_REACH :: rl.Vector2{14, 30}
EXIT_REACH :: rl.Vector2{16, 34}

level_destroy :: proc(l: ^Level) {
	delete(l.checkpoints)
	delete(l.fruit)
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
	}
	for &f in g.level.fruit {
		f.state = .Waiting
		f.pos = f.home
	}
	g.level.kept = 0
	g.fruit_safe = 0
	g.respawn = g.level.spawn
	g.deaths = 0
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

// Checkpoints are taken by touching them; the flag at the end finishes the
// level, and a secret exit finishes it too, opening a hidden level.
level_update :: proc(g: ^Game, dt: f32) {
	fruit_update(g, dt)
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
		animator_restart(&c.anim, &g.assets.marks.flag_out)
		g.respawn = c.pos
		keep_carried_fruit(g)
		spawn_burst(g, c.pos - {0, 20}, {255, 230, 140, 255}, 14, 90, 1.2)
		play(&g.assets, .Checkpoint)
		haptic(.Checkpoint)
	}
	if rl.CheckCollisionRecs(pr, flag_rect(g.level.exit, EXIT_REACH)) {
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

	save_record_clear(&g.save, d.ident, g.level_time, g.deaths, g.level.kept)
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
	play(&g.assets, .Clear)
	haptic(.Clear)
	game_set_state(g, .Cleared)
}

level_draw_flags :: proc(g: ^Game) {
	m := &g.assets.marks
	for &c in g.level.checkpoints {
		// The pole stands 8px left of the middle of its 64px cell.
		pos := c.pos + {8, 0}
		switch {
		case !c.active:
			anim_draw_frame(&m.pole, 0, pos, false)
		case c.anim.anim == &m.flag_out && !c.anim.finished:
			animator_update(&c.anim, rl.GetFrameTime())
			animator_draw(c.anim, pos, false)
		case:
			frame := int(g.time / 0.07) % 10
			anim_draw_frame(&m.flag, frame, pos, false)
		}
	}
	if g.exit_anim.anim != nil {
		animator_update(&g.exit_anim, rl.GetFrameTime())
		animator_draw(g.exit_anim, g.level.exit, false)
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
