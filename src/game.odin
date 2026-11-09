package game

import "core:math/rand"
import rl "../libs/raylib"

/*
Everything that exists at once, the order it is updated in, and the order it
is drawn in. Each of those lists has a file of its own next to this one.
*/

Game_State :: enum {
	Title,
	Playing,
	Paused,
	Cleared, // reached the flag at the end of the level
}

LEVEL_INTRO_TIME :: 2.2

Game :: struct {
	assets:       Assets,
	input:        Input, // this frame's, from whichever device
	touch:        Touch_State,
	ui:           Ui_State,
	state_time:   f32, // how long the current state has lasted
	quit:         bool, // asked to leave from the title
	level:        Level,
	map_tiles:    Tilemap,
	player:       Player,
	sparks:       [dynamic]Spark,
	decor:        [dynamic]Decor, // torches, roots, crystals: drawn in code, mostly lit
	motes:        [dynamic]Mote, // what drifts through the air
	liquid_glows: [dynamic]rl.Vector2, // points along lava that light the level
	lighting:     Lighting,
	bg_tint:      rl.Color,
	state:        Game_State,
	time:         f32, // wall clock, keeps running on menus
	shake:        f32,
	freeze:       f32, // a few hundredths of a second where nothing moves
	camera:       rl.Camera2D,

	// this attempt at the level
	respawn:      rl.Vector2, // the last checkpoint touched, or the start
	deaths:       int,
	level_time:   f32,
	level_intro:  f32, // the level's name, fading out

	// the best clears so far this session
	best_time:    f32, // 0 until the level has been cleared once
	best_deaths:  int, // -1 until then
}

game_init :: proc(g: ^Game) {
	assets_load(&g.assets)
	touch_init(&g.touch)
	g.best_deaths = -1
	level_load_test(g)
	level_restart(g)
	game_set_state(g, .Title)
	rl.PlayMusicStream(g.assets.music)
}

game_destroy :: proc(g: ^Game) {
	assets_unload(&g.assets)
	touch_destroy(&g.touch)
	tilemap_destroy(&g.map_tiles)
	level_destroy(&g.level)
	delete(g.sparks)
	delete(g.decor)
	delete(g.motes)
	delete(g.liquid_glows)
	lighting_destroy(&g.lighting)
}

game_update :: proc(g: ^Game, dt: f32) {
	g.time += dt
	g.state_time += dt
	rl.UpdateMusicStream(g.assets.music)
	g.input = input_poll(g)

	// A phone going to sleep, or a window losing focus, pauses the level
	// rather than letting it run on while nobody is looking.
	if g.state == .Playing && (g.input.pause || !rl.IsWindowFocused()) {
		game_set_state(g, .Paused)
		return
	}

	switch g.state {
	case .Title, .Paused, .Cleared:
		menu_update(g)
		if g.state != .Paused {
			motes_update(g, dt) // the menus sit over a live, drifting level
			sparks_update(g, dt)
		}
	case .Playing:
		game_update_play(g, dt)
		motes_update(g, dt)
	}

	camera_update(g, dt)
	lighting_update(g, dt)
}

@(private = "file")
game_update_play :: proc(g: ^Game, dt: f32) {
	g.shake = max(0, g.shake - dt * 18)
	// The hit-stop: a dash or a death holds the world still for a beat, which
	// is most of what makes either feel like it landed.
	if g.freeze > 0 {
		g.freeze -= dt
		return
	}
	g.level_intro = max(0, g.level_intro - dt)
	if !g.player.dead {
		g.level_time += dt
	}
	player_update(g, dt)
	level_update(g)
	sparks_update(g, dt)
}

game_set_state :: proc(g: ^Game, state: Game_State) {
	g.state = state
	g.state_time = 0
	g.ui.focus = 0
	g.ui.press = -1
	g.ui.how_to = false
	// The pointer is only for the menus.
	when !TOUCH_CONTROLS {
		if state == .Playing {
			rl.HideCursor()
		} else {
			rl.ShowCursor()
		}
	}
}

game_draw :: proc(g: ^Game) {
	view := camera_view(g)

	shake: rl.Vector2
	if g.shake > 0 {
		shake = {rand.float32_range(-g.shake, g.shake), rand.float32_range(-g.shake, g.shake)}
	}
	cam := g.camera
	cam.offset += shake

	// The light map is its own render pass, so it goes first.
	lighting_render(g, shake)

	rl.BeginDrawing()
	rl.ClearBackground({40, 52, 62, 255})
	draw_background(g)

	rl.BeginMode2D(cam)
	tilemap_draw(g, view)
	decor_draw(g)
	level_draw_flags(g)
	player_draw(g.player, &g.assets)
	rl.EndMode2D()

	// Everything so far sits in the dark; what comes after it is light itself,
	// or has to stay readable whatever the dark is doing.
	lighting_apply(g)

	rl.BeginMode2D(cam)
	atmosphere_draw(g, view)
	motes_draw(g)
	sparks_draw(g)
	draw_vignette(g, view)
	rl.EndMode2D()

	hud_draw(g)
	rl.EndDrawing()
}
