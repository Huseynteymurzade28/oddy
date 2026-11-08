package game

import "core:math/rand"
import rl "../libs/raylib"

/*
The run: everything that exists at once, the order it is updated in, and the
order it is drawn in. Each of those lists has a file of its own next to this one.
*/

Game_State :: enum {
	Title,
	Playing,
	Paused,
	Dead,
	Won,
}

Game :: struct {
	assets:       Assets,
	input:        Input, // this frame's, from whichever device
	touch:        Touch_State,
	ui:           Ui_State,
	state_time:   f32, // how long the current state has lasted
	quit:         bool, // asked to leave from the pause card
	world:        World,
	map_tiles:    Tilemap,
	player:       Player,
	enemies:      [dynamic]Enemy,
	bullets:      [dynamic]Bullet,
	effects:      [dynamic]Effect,
	sparks:       [dynamic]Spark,
	pickups:      [dynamic]Pickup,
	chests:       [dynamic]Chest,
	shop:         Shop, // one stall per run, in the room that rolled it
	props:        [dynamic]Prop, // scenery, rolled once per run and never updated
	decor:        [dynamic]Decor, // torches, roots, crystals: drawn in code, mostly lit
	motes:        [dynamic]Mote, // what drifts through the air
	liquid_glows: [dynamic]rl.Vector2, // points along lava that light the room
	lighting:     Lighting,
	bg_tint:      rl.Color,
	coins_total:  int,
	state:        Game_State,
	time:         f32, // wall clock, keeps running on menus
	run_time:     f32,
	shake:        f32,
	camera:       rl.Camera2D,
	room:         [2]int, // the room the player is currently standing in
	flag_pos:     rl.Vector2,

	// the vault
	boss_kind:    Enemy_Kind, // which of the three guards it this run
	boss_sealed:  bool, // the doors shut behind you
	boss_intro:   f32, // the name card, counting down
	boss_down:    bool,
	win_delay:    f32, // the death is worth watching before the card covers it

	// what to do next, shown under the map for a while whenever it changes
	objective:       cstring,
	objective_timer: f32,

	// a one-line message across the middle of the screen
	notice:       string,
	notice_timer: f32,

	// carried between runs, for the death screen
	runs:         int,
	best_rooms:   int,
	best_kills:   int,
}

game_init :: proc(g: ^Game) {
	assets_load(&g.assets)
	touch_init(&g.touch)
	game_new_run(g)
	game_set_state(g, .Title)
	rl.PlayMusicStream(g.assets.music)
}

game_destroy :: proc(g: ^Game) {
	assets_unload(&g.assets)
	touch_destroy(&g.touch)
	tilemap_destroy(&g.map_tiles)
	world_destroy(&g.world)
	delete(g.enemies)
	delete(g.bullets)
	delete(g.effects)
	delete(g.sparks)
	delete(g.pickups)
	delete(g.chests)
	delete(g.props)
	delete(g.decor)
	delete(g.motes)
	delete(g.liquid_glows)
	lighting_destroy(&g.lighting)
}

// Throws the whole world away and builds a new one. Nothing except the records
// on the death screen survives a run.
game_new_run :: proc(g: ^Game) {
	tilemap_destroy(&g.map_tiles)
	world_destroy(&g.world)

	g.runs += 1
	g.run_time = 0
	g.shake = 0
	g.boss_down = false
	g.boss_sealed = false
	g.boss_intro = 0
	g.win_delay = 0
	g.boss_kind = boss_roll(g.boss_kind)
	g.objective = ""
	g.notice = ""
	g.notice_timer = 0

	world_generate(g)

	game_set_state(g, .Playing)
	g.room = room_coords(g.player.pos)
	g.camera = {
		zoom   = 1,
		target = g.player.pos,
	}
}

game_update :: proc(g: ^Game, dt: f32) {
	g.time += dt
	g.state_time += dt
	rl.UpdateMusicStream(g.assets.music)
	g.input = input_poll(g)

	// A phone going to sleep, or a window losing focus, should never cost a
	// life while nobody is looking.
	if g.state == .Playing && (g.input.pause || !rl.IsWindowFocused()) {
		game_set_state(g, .Paused)
		return
	}

	switch g.state {
	case .Title, .Paused, .Dead, .Won:
		menu_update(g)
		if g.state == .Title {
			motes_update(g, dt) // the title sits over a live, drifting room
		}
	case .Playing:
		g.run_time += dt
		game_update_play(g, dt)
		motes_update(g, dt)
	}

	camera_update(g, dt)
	lighting_update(g, dt)
}

@(private = "file")
game_update_play :: proc(g: ^Game, dt: f32) {
	g.notice_timer = max(0, g.notice_timer - dt)
	g.boss_intro = max(0, g.boss_intro - dt)
	g.objective_timer = max(0, g.objective_timer - dt)
	if obj := objective_text(g); obj != g.objective {
		g.objective = obj
		g.objective_timer = 5
	}

	player_update(g, dt)

	// Walking into a room reveals it on the map.
	g.room = room_coords(g.player.pos)
	if room := room_at(&g.world, g.room.x, g.room.y); room != nil {
		room.seen = true
	}
	boss_check_seal(g)

	for i in 0 ..< len(g.enemies) {
		enemy_update(g, i, dt)
	}
	bullets_update(g, dt)
	effects_update(g, dt)
	sparks_update(g, dt)

	for &p in g.pickups {
		pickup_update(&p, &g.assets, dt)
	}
	for i in 0 ..< len(g.chests) {
		chest_update(g, i, dt)
	}

	// One key for everything you can stand in front of. The stall gets first
	// refusal, so a chest in the same room can never swallow a purchase.
	if g.input.interact && !shop_interact(g) {
		chests_interact(g)
	}
	pickups_collect(g)

	// Touching anything alive costs a heart; the invulnerability window is what
	// makes brawling at close range survivable rather than instant death.
	if !g.player.dead {
		pr := player_rect(g.player)
		for e in g.enemies {
			if !e.alive || !rl.CheckCollisionRecs(pr, enemy_rect(e)) {
				continue
			}
			if player_hurt(&g.player, &g.assets, e.pos.x) {
				g.shake = max(g.shake, 5)
			}
			break
		}
	}

	// Corpses are dropped once they have faded out.
	live := 0
	for e in g.enemies {
		if e.alive || e.corpse > 0 {
			g.enemies[live] = e
			live += 1
		}
	}
	resize(&g.enemies, live)

	g.shake = max(0, g.shake - dt * 18)

	if g.boss_down && g.state == .Playing {
		g.win_delay -= dt
		if g.win_delay <= 0 {
			game_set_state(g, .Won)
			record_run(g)
		}
	}
	if g.player.dead && g.player.death_timer <= 0 {
		game_set_state(g, .Dead)
		record_run(g)
	}
}

game_set_state :: proc(g: ^Game, state: Game_State) {
	g.state = state
	g.state_time = 0
	g.ui.focus = 0
	g.ui.press = -1
	g.ui.how_to = false
}

@(private = "file")
record_run :: proc(g: ^Game) {
	g.best_rooms = max(g.best_rooms, rooms_seen(&g.world))
	g.best_kills = max(g.best_kills, g.player.kills)
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
	// Scenery straddles the tilemap: the silhouettes go under it so the rock
	// overlaps them, the floor clutter over it, and the grass over the player.
	props_draw(g, .Behind)
	tilemap_draw(g, view)
	decor_draw(g)
	props_draw(g, .Level)

	draw_start_flag(g)
	shop_draw(g)
	for p in g.pickups {
		pickup_draw(p, &g.assets)
	}
	for c in g.chests {
		chest_draw(c, &g.assets, g.time)
	}
	for e in g.enemies {
		enemy_draw(e, &g.assets)
	}
	player_draw(g.player, &g.assets)
	props_draw(g, .Front)
	rl.EndMode2D()

	// Everything so far sits in the dark; what comes after it is light itself,
	// or has to stay readable whatever the dark is doing.
	lighting_apply(g)

	rl.BeginMode2D(cam)
	atmosphere_draw(g, view)
	motes_draw(g)
	draw_trapdoor_hints(g)
	draw_aim_guide(g)
	shots_draw(g)
	for e in g.enemies {
		enemy_draw_health(e)
	}
	draw_vignette(g, view)
	rl.EndMode2D()

	hud_draw(g)
	rl.EndDrawing()
}

@(private = "file")
draw_start_flag :: proc(g: ^Game) {
	anim := &g.assets.flag
	frame := int(g.time / max(anim.frame_time, 0.01)) % max(anim.count, 1)
	anim_draw_frame(anim, frame, g.flag_pos, false)
}
