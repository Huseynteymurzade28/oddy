package game

import rl "../libs/raylib"

/*
One level: its tiles, where you start, the checkpoints along the way and the
flag at the end. For now the only level is the test course below, drawn in
text; Phase 2 replaces it with levels authored in LDtk.

  #  rock          -  one-way platform    ~  water (kills)
  ^  spikes (they point away from the rock they grow on)
  P  where you start   C  a checkpoint   E  the flag at the end
*/

Checkpoint :: struct {
	pos:    rl.Vector2, // the foot of the flag, which is also where you respawn
	active: bool,
}

Level :: struct {
	name:        cstring,
	zone:        Zone,
	spawn:       rl.Vector2,
	exit:        rl.Vector2,
	checkpoints: [dynamic]Checkpoint,
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

level_load_text :: proc(g: ^Game, name: cstring, zone: Zone, rows: []string) {
	level_destroy(&g.level)
	tilemap_destroy(&g.map_tiles)

	h := len(rows)
	w := 0
	for row in rows {
		w = max(w, len(row))
	}
	g.map_tiles = tilemap_make(w, h)
	g.level.name = name
	g.level.zone = zone

	for row, y in rows {
		for ch, x in row {
			foot := rl.Vector2{f32(x) * TILE + TILE / 2, f32(y + 1) * TILE}
			switch ch {
			case '#':
				tile_set(&g.map_tiles, x, y, .Rock)
			case '-':
				tile_set(&g.map_tiles, x, y, .Platform)
			case '~':
				tile_set(&g.map_tiles, x, y, .Water)
			case '^':
				tile_set(&g.map_tiles, x, y, .Spike)
			case 'P':
				g.level.spawn = foot
			case 'C':
				append(&g.level.checkpoints, Checkpoint{pos = foot})
			case 'E':
				g.level.exit = foot
			}
		}
	}
	decor_scatter(g)
}

level_load_test :: proc(g: ^Game) {
	level_load_text(g, "TEST COURSE", .Mossy, TEST_LEVEL[:])
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
		g.respawn = c.pos
		spawn_burst(g, c.pos - {0, 20}, {255, 230, 140, 255}, 14, 90, 1.2)
		play(&g.assets, .Coin)
	}
	if rl.CheckCollisionRecs(pr, flag_rect(g.level.exit, EXIT_REACH)) {
		level_clear(g)
	}
}

@(private = "file")
level_clear :: proc(g: ^Game) {
	if g.best_time == 0 || g.level_time < g.best_time {
		g.best_time = g.level_time
	}
	if g.best_deaths < 0 || g.deaths < g.best_deaths {
		g.best_deaths = g.deaths
	}
	spawn_burst(g, g.level.exit - {0, 24}, {255, 214, 110, 255}, 30, 140, 1.5)
	play(&g.assets, .Power_Up)
	game_set_state(g, .Cleared)
}

level_draw_flags :: proc(g: ^Game) {
	anim := &g.assets.flag
	frame := int(g.time / max(anim.frame_time, 0.01)) % max(anim.count, 1)
	for c in g.level.checkpoints {
		// An unlit checkpoint is a still, grey flag; a lit one waves.
		if c.active {
			anim_draw_frame(anim, frame, c.pos, false)
		} else {
			anim_draw_frame(anim, 0, c.pos, false, {120, 120, 140, 255})
		}
	}
	anim_draw_frame(anim, frame, g.level.exit, false, {255, 214, 110, 255})
}


@(private = "file")
TEST_LEVEL := [?]string {
	"#....................................................................................................................###################.............#",
	"#....................................................................................................................###################.............#",
	"#....................................................................................................................###################.............#",
	"#....................................................................................................................###################.............#",
	"#....................................................................................................................###################.............#",
	"#................................##...#########......................................................................###################.............#",
	"#................................##...#########......................................................................###################.............#",
	"#................................##...#########......................................................................###################.............#",
	"#................................##...#########........................############..................................###################.............#",
	"#................................##...#########........................############..................................###################.............#",
	"#................................##...#########........................############..................................###################.............#",
	"#................................##...#########........................############......................................^^^^^^^^^^..................#",
	"#................................##...#########........................############.........---.............C........................................#",
	"#................................##...#########..................C.....############......................########....................................#",
	"#.....................................###############........######################...---................########....................................#",
	"#.....................................###############........######################...............---....########........^^^^^^^^^^.............E....#",
	"#..............................C......###############........######################......................#############################################",
	"#............############....########################........######################......................#############################################",
	"#...P........############....########################........######################~~~~~~~~~~~~~~~~~~~~~~#############################################",
	"#########################....########################^^^^^^^^######################~~~~~~~~~~~~~~~~~~~~~~#############################################",
	"#########################....######################################################~~~~~~~~~~~~~~~~~~~~~~#############################################",
	"#########################^^^^#########################################################################################################################",
	"######################################################################################################################################################",
	"######################################################################################################################################################",
}
