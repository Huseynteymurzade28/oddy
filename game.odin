package game

import "core:math"
import "core:math/rand"
import rl "vendor:raylib"

// The game is rendered at a fixed virtual height and scaled up to the window,
// so it always shows the same amount of world regardless of resolution.
// 240 tall shows about fifteen tiles, which is enough of a room to see a flyer
// coming without shrinking the player into a dot.
PIXEL_HEIGHT :: 240.0
CAMERA_LOOKUP :: 14.0 // how far above the feet the camera aims
CAMERA_SMOOTH :: 10.0
AIM_LEAD :: 30.0 // how far the camera leans toward where you are aiming

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
	seen := 0
	for y in 0 ..< GRID_H {
		for x in 0 ..< GRID_W {
			if g.world.rooms[y][x].seen {
				seen += 1
			}
		}
	}
	g.best_rooms = max(g.best_rooms, seen)
	g.best_kills = max(g.best_kills, g.player.kills)
}

view_size :: proc() -> rl.Vector2 {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	return {sw / (sh / PIXEL_HEIGHT), PIXEL_HEIGHT}
}

@(private = "file")
camera_update :: proc(g: ^Game, dt: f32) {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	g.camera.zoom = sh / PIXEL_HEIGHT
	g.camera.offset = {sw / 2, sh / 2}

	view := view_size()
	half := view / 2

	// Lean toward the crosshair, which buys a little more warning about what you
	// are shooting at without letting the player leave the frame.
	lead := rl.Vector2{math.cos(g.player.aim), math.sin(g.player.aim)} * AIM_LEAD
	wanted := g.player.pos - {0, CAMERA_LOOKUP} + lead
	g.camera.target += (wanted - g.camera.target) * min(1, CAMERA_SMOOTH * dt)

	// The camera stays inside the room the player is in: crossing a doorway is
	// what moves it on, which is what makes the map read as separate places.
	bounds := room_rect(g.room)
	if bounds.width > view.x {
		g.camera.target.x = clamp(
			g.camera.target.x,
			bounds.x + half.x,
			bounds.x + bounds.width - half.x,
		)
	} else {
		g.camera.target.x = bounds.x + bounds.width / 2
	}
	if bounds.height > view.y {
		g.camera.target.y = clamp(
			g.camera.target.y,
			bounds.y + half.y,
			bounds.y + bounds.height - half.y,
		)
	} else {
		g.camera.target.y = bounds.y + bounds.height / 2
	}
}

// The world-space rectangle the camera currently shows.
camera_view :: proc(g: ^Game) -> rl.Rectangle {
	view := view_size()
	return {g.camera.target.x - view.x / 2, g.camera.target.y - view.y / 2, view.x, view.y}
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
	bullets_draw(g)
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

// Everything is underground, so the far edges of the view fall off into dark.
@(private = "file")
draw_vignette :: proc(g: ^Game, view: rl.Rectangle) {
	edge := rl.Color{10, 8, 16, 120}
	clear := rl.Color{10, 8, 16, 0}
	band := view.height * 0.22
	rl.DrawRectangleGradientV(
		i32(view.x),
		i32(view.y),
		i32(view.width),
		i32(band),
		edge,
		clear,
	)
	rl.DrawRectangleGradientV(
		i32(view.x),
		i32(view.y + view.height - band),
		i32(view.width),
		i32(band),
		clear,
		edge,
	)
}

// Five parallax layers of forest seen through the cave mouth. They are drawn in
// screen space, tiled horizontally, and darkened as they come closer so the
// nearest one reads as a silhouette.
@(private = "file")
draw_background :: proc(g: ^Game) {
	view := view_size()
	s := f32(rl.GetScreenHeight()) / PIXEL_HEIGHT
	layer_w: f32 = PIXEL_HEIGHT * 16 / 9

	for i in 0 ..< BG_LAYERS {
		tex := g.assets.layers[i]
		if tex.id == 0 {
			continue
		}
		depth := f32(i) / f32(BG_LAYERS - 1)
		factor := 0.06 + depth * 0.24

		ox := -g.camera.target.x * factor
		ox -= math.floor(ox / layer_w) * layer_w // wrap into [0, layer_w)

		// Each copy is drawn taller than the screen and its vertical drift is
		// capped, so descending never slides an edge of the artwork into view.
		height: f32 = PIXEL_HEIGHT * 1.6
		drift := clamp(-g.camera.target.y * factor * 0.22, -PIXEL_HEIGHT * 0.4, 0)
		oy := -(height - PIXEL_HEIGHT) / 2 + drift

		shade := u8(118 - depth * 74)
		tint := rl.Color{shade, u8(f32(shade) * 1.06), u8(f32(shade) * 1.18), 255}
		src := rl.Rectangle{0, 0, f32(tex.width), f32(tex.height)}

		for c in 0 ..< int(view.x / layer_w) + 3 {
			dest := rl.Rectangle {
				(ox - layer_w + f32(c) * layer_w) * s,
				oy * s,
				layer_w * s,
				height * s,
			}
			rl.DrawTexturePro(tex, src, dest, {}, 0, tint)
		}
	}
}
