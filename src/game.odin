package game

import "core:math/rand"
import rl "../libs/raylib"

/*
Everything that exists at once, the order it is updated in, and the order it
is drawn in. Each of those lists has a file of its own next to this one.
*/

Game_State :: enum {
	Title,
	Map, // the world map: picking a level
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
	levels:       [dynamic]Level_Data, // every level in the file, in order
	save:         Save,
	world_map:    World_Map,
	clear:        Clear_Result, // what the last clear earned
	fruit_safe:   f32, // how long you have stood on rock carrying fruit
	level:        Level,
	map_tiles:    Tilemap,
	player:       Player,
	sparks:       [dynamic]Spark,
	poofs:        [dynamic]Poof,
	popups:       [dynamic]Popup,
	confetti:     [dynamic]Confetti,
	chips:        [dynamic]Chip,
	things:       [dynamic]Thing, // traps and moving pieces
	enemies:      [dynamic]Enemy,
	arrows:       [dynamic]Arrow,
	decor:        [dynamic]Decor, // torches, roots, crystals: drawn in code, mostly lit
	motes:        [dynamic]Mote, // what drifts through the air
	liquid_glows: [dynamic]rl.Vector2, // points along lava that light the level
	lighting:     Lighting,
	state:        Game_State,
	time:         f32, // wall clock, keeps running on menus
	shake:        f32,
	freeze:       f32, // a few hundredths of a second where nothing moves
	camera:       rl.Camera2D,
	camera_lead:  f32, // how far the camera runs ahead, eased toward the speed
	exit_anim:    Animator, // the trophy at the end, once pressed

	// this attempt at the level
	respawn:      rl.Vector2, // the last checkpoint touched, or the start
	deaths:       int,
	level_time:   f32,
	level_intro:  f32, // the level's name, fading out
}

game_init :: proc(g: ^Game) {
	assets_load(&g.assets)
	touch_init(&g.touch)
	save_load(&g.save)
	assets_use_skin(&g.assets, g.save.skin)
	levels_reload(g)
	level_enter(g, 0)
	world_map_init(g)
	game_set_state(g, .Title)
	rl.PlayMusicStream(g.assets.music)
}

game_destroy :: proc(g: ^Game) {
	assets_unload(&g.assets)
	touch_destroy(&g.touch)
	tilemap_destroy(&g.map_tiles)
	level_destroy(&g.level)
	levels_destroy(&g.levels)
	save_destroy(&g.save)
	delete(g.sparks)
	delete(g.poofs)
	for p in g.popups {
		delete(p.text)
	}
	delete(g.popups)
	delete(g.confetti)
	delete(g.chips)
	delete(g.things)
	delete(g.enemies)
	delete(g.arrows)
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

	// F5 reads the levels file again and restarts the level you are on, so
	// a change saved in LDtk can be played a second later.
	when !IS_MOBILE {
		if rl.IsKeyPressed(.F5) {
			levels_reload(g)
			level_enter(g, g.level.index)
		}
	}

	// A phone going to sleep, or a window losing focus, pauses the level
	// rather than letting it run on while nobody is looking.
	if g.state == .Playing && (g.input.pause || !rl.IsWindowFocused()) {
		game_set_state(g, .Paused)
		return
	}

	switch g.state {
	case .Map:
		world_map_update(g, dt)
		motes_update(g, dt)
	case .Title, .Paused, .Cleared:
		menu_update(g)
		if g.state != .Paused {
			motes_update(g, dt) // the menus sit over a live, drifting level
			sparks_update(g, dt)
			confetti_update(g, dt)
			popups_update(g, dt)
			chips_update(g, dt)
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
	things_update(g, dt)
	player_update(g, dt)
	enemies_update(g, dt)
	level_update(g, dt)
	sparks_update(g, dt)
	poofs_update(g, dt)
	popups_update(g, dt)
	confetti_update(g, dt)
	chips_update(g, dt)
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
	things_draw(g)
	enemies_draw(g)
	level_draw_fruit(g)
	level_draw_gems(g)
	player_draw(g.player, &g.assets)
	poofs_draw(g)
	rl.EndMode2D()

	// Everything so far sits in the dark; what comes after it is light itself,
	// or has to stay readable whatever the dark is doing.
	lighting_apply(g)

	rl.BeginMode2D(cam)
	atmosphere_draw(g, view)
	motes_draw(g)
	sparks_draw(g)
	chips_draw(g)
	if g.state != .Cleared {
		confetti_draw(g)
	}
	level_draw_hints(g)
	popups_draw(g)
	draw_vignette(g, view)
	rl.EndMode2D()

	hud_draw(g)
	rl.EndDrawing()
}
