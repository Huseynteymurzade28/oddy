package game

import "core:math/rand"
import rl "vendor:raylib"

/*
The run: everything that exists at once, the order it is updated in, and the
order it is drawn in. Each of those lists has a file of its own next to this one.
*/

Game_State :: enum {
	Title,
	Playing,
	Dead,
	Won,
}

Game :: struct {
	assets:       Assets,
	world:        World,
	map_tiles:    Tilemap,
	player:       Player,
	enemies:      [dynamic]Enemy,
	bullets:      [dynamic]Bullet,
	effects:      [dynamic]Effect,
	sparks:       [dynamic]Spark,
	pickups:      [dynamic]Pickup,
	chests:       [dynamic]Chest,
	coins_total:  int,
	state:        Game_State,
	time:         f32, // wall clock, keeps running on menus
	run_time:     f32,
	shake:        f32,
	camera:       rl.Camera2D,
	room:         [2]int, // the room the player is currently standing in
	boss_down:    bool,
	flag_pos:     rl.Vector2,

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
	game_new_run(g)
	g.state = .Title
	rl.PlayMusicStream(g.assets.music)
}

game_destroy :: proc(g: ^Game) {
	assets_unload(&g.assets)
	tilemap_destroy(&g.map_tiles)
	world_destroy(&g.world)
	delete(g.enemies)
	delete(g.bullets)
	delete(g.effects)
	delete(g.sparks)
	delete(g.pickups)
	delete(g.chests)
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
	g.notice = ""
	g.notice_timer = 0

	world_generate(g)

	g.state = .Playing
	g.room = room_coords(g.player.pos)
	g.camera = {
		zoom   = 1,
		target = g.player.pos,
	}
}

game_update :: proc(g: ^Game, dt: f32) {
	g.time += dt
	rl.UpdateMusicStream(g.assets.music)

	switch g.state {
	case .Title:
		if rl.IsKeyPressed(.SPACE) || rl.IsKeyPressed(.ENTER) {
			g.state = .Playing
		}
	case .Playing:
		g.run_time += dt
		game_update_play(g, dt)
	case .Dead, .Won:
		if rl.IsKeyPressed(.R) {
			game_new_run(g)
		}
	}

	camera_update(g, dt)
}

@(private = "file")
game_update_play :: proc(g: ^Game, dt: f32) {
	g.notice_timer = max(0, g.notice_timer - dt)

	player_update(g, dt)

	// Walking into a room reveals it on the map.
	g.room = room_coords(g.player.pos)
	if room := room_at(&g.world, g.room.x, g.room.y); room != nil {
		room.seen = true
	}

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

	if rl.IsKeyPressed(.E) {
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
		g.state = .Won
		record_run(g)
	}
	if g.player.dead && g.player.death_timer <= 0 {
		g.state = .Dead
		record_run(g)
	}
}

@(private = "file")
record_run :: proc(g: ^Game) {
	g.best_rooms = max(g.best_rooms, rooms_seen(&g.world))
	g.best_kills = max(g.best_kills, g.player.kills)
}

game_draw :: proc(g: ^Game) {
	view := camera_view(g)

	rl.BeginDrawing()
	rl.ClearBackground({14, 12, 20, 255})
	draw_background(g)

	cam := g.camera
	if g.shake > 0 {
		cam.offset += {
			rand.float32_range(-g.shake, g.shake),
			rand.float32_range(-g.shake, g.shake),
		}
	}

	rl.BeginMode2D(cam)
	tilemap_draw(&g.map_tiles, &g.assets, view, g.time)

	draw_start_flag(g)
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
	for e in g.enemies {
		enemy_draw_health(e)
	}
	shots_draw(g)
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
