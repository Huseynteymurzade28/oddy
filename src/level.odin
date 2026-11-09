package game

import "core:fmt"
import "core:math"
import "core:strings"
import rl "../libs/raylib"

/*
The level being played: built from one `Level_Data` (see `ldtk.odin`), plus
what changes while you play it: which checkpoints are lit.
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
	checkpoints: [dynamic]Checkpoint,
}

// The best clear of each level this session, kept apart from the level data
// so reloading the levels file does not forget it.
Level_Best :: struct {
	cleared: bool,
	time:    f32,
	deaths:  int,
}

CHECKPOINT_REACH :: rl.Vector2{14, 30}
EXIT_REACH :: rl.Vector2{16, 34}

level_destroy :: proc(l: ^Level) {
	delete(l.checkpoints)
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
	resize(&g.best, len(g.levels))
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
		spawn = d.spawn,
		exit  = d.exit,
	}
	for c in d.checkpoints {
		append(&g.level.checkpoints, Checkpoint{pos = c})
	}
	g.bg_tint = {}
	g.exit_anim = {}
	decor_scatter(g)
	level_restart(g)
}

level_has_next :: proc(g: ^Game) -> bool {
	return g.level.index + 1 < len(g.levels)
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
	g.respawn = g.level.spawn
	g.deaths = 0
	g.level_time = 0
	g.level_intro = LEVEL_INTRO_TIME
	clear(&g.sparks)
	level_reset_things(g)
	player_init(&g.player, g.respawn)
	camera_snap(g)
}

// Checkpoints are taken by touching them; the flag at the end finishes the
// level.
level_update :: proc(g: ^Game) {
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
		spawn_burst(g, c.pos - {0, 20}, {255, 230, 140, 255}, 14, 90, 1.2)
		play(&g.assets, .Checkpoint)
		haptic(.Checkpoint)
	}
	if rl.CheckCollisionRecs(pr, flag_rect(g.level.exit, EXIT_REACH)) {
		level_clear(g)
	}
}

@(private = "file")
level_clear :: proc(g: ^Game) {
	// The fastest time and the fewest deaths are kept apart: they will be
	// separate medals, and need not come from the same clear.
	best := &g.best[g.level.index]
	if !best.cleared {
		best^ = {cleared = true, time = g.level_time, deaths = g.deaths}
	} else {
		best.time = min(best.time, g.level_time)
		best.deaths = min(best.deaths, g.deaths)
	}
	spawn_burst(g, g.level.exit - {0, 24}, {255, 214, 110, 255}, 30, 140, 1.5)
	animator_restart(&g.exit_anim, &g.assets.marks.end_pressed)
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
}

// The hints float over the level in its own small type, lit or not.
level_draw_hints :: proc(g: ^Game) {
	a := &g.assets
	for h in g.level.hints {
		w := rl.MeasureTextEx(a.font, h.text, 8, 1).x
		pos := rl.Vector2{math.round(h.pos.x - w / 2), h.pos.y - 10}
		rl.DrawTextEx(a.font, h.text, pos + {0, 1}, 8, 1, {10, 8, 16, 170})
		rl.DrawTextEx(a.font, h.text, pos, 8, 1, {236, 230, 214, 230})
	}
}
