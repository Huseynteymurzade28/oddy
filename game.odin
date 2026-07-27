package game

import "core:math"
import "core:math/rand"
import rl "vendor:raylib"

// The game is rendered at a fixed virtual height and scaled up to the window,
// so it always shows the same amount of world regardless of resolution.
PIXEL_HEIGHT :: 180.0
CAMERA_LOOKUP :: 14.0 // how far above the feet the camera aims
CAMERA_SMOOTH :: 9.0

Game_State :: enum {
	Title,
	Playing,
	Won,
}

Game :: struct {
	assets:      Assets,
	world:       Tilemap,
	player:      Player,
	enemies:     [dynamic]Enemy,
	pickups:     [dynamic]Pickup,
	checkpoints: [dynamic]Checkpoint,
	goal:        Goal,
	coins_total: int,
	coins_taken: int,
	state:       Game_State,
	time:        f32,
	play_time:   f32,
	shake:       f32,
	camera:      rl.Camera2D,
}

game_init :: proc(g: ^Game) {
	assets_load(&g.assets)
	level_load(g)
	g.state = .Title
	g.camera = {
		zoom   = 1,
		target = g.player.pos,
	}
	rl.PlayMusicStream(g.assets.music)
}

game_destroy :: proc(g: ^Game) {
	assets_unload(&g.assets)
	tilemap_destroy(&g.world)
	delete(g.enemies)
	delete(g.pickups)
	delete(g.checkpoints)
}

game_restart :: proc(g: ^Game) {
	tilemap_destroy(&g.world)
	level_load(g)
	g.coins_taken = 0
	g.play_time = 0
	g.shake = 0
	g.state = .Playing
	g.camera.target = g.player.pos
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
		g.play_time += dt
		game_update_play(g, dt)
	case .Won:
		if rl.IsKeyPressed(.R) {
			game_restart(g)
		}
	}

	camera_update(g, dt)
}

@(private = "file")
game_update_play :: proc(g: ^Game, dt: f32) {
	player_update(&g.player, &g.world, &g.assets, dt)

	// Dying costs no progress: the world's enemies come back, the coins stay
	// collected, and the player returns to the last sign they touched.
	if g.player.dead && g.player.respawn_timer <= 0 {
		player_respawn(&g.player)
		for &e in g.enemies {
			enemy_reset(&e)
		}
	}

	for &e in g.enemies {
		enemy_update(&e, &g.world, &g.assets, dt)
	}
	for &p in g.pickups {
		pickup_update(&p, &g.assets, dt)
	}
	for &c in g.checkpoints {
		c.pulse = max(0, c.pulse - dt * 2)
	}

	if !g.player.dead {
		pr := player_rect(g.player)

		for &p in g.pickups {
			if p.taken || !rl.CheckCollisionRecs(pr, pickup_rect(p)) {
				continue
			}
			switch p.kind {
			case .Coin:
				p.taken = true
				g.coins_taken += 1
				play(&g.assets, .Coin)
			case .Fruit:
				// Fruit is only consumed if it can actually heal.
				if player_heal(&g.player) {
					p.taken = true
					play(&g.assets, .Power_Up)
				}
			}
		}

		// Landing on a slime squashes it; touching it any other way hurts.
		for &e in g.enemies {
			if !e.alive {
				continue
			}
			er := enemy_rect(e)
			if !rl.CheckCollisionRecs(pr, er) {
				continue
			}
			if g.player.vel.y > 0 && pr.y + pr.height < er.y + ENEMY_H * 0.6 {
				enemy_squash(&e, &g.assets)
				g.player.vel.y = -STOMP_BOUNCE
				g.player.holding_jump = true
				g.shake = max(g.shake, 2.5)
			} else if player_hurt(&g.player, &g.assets, e.pos.x) {
				g.shake = max(g.shake, 5)
			}
		}

		for &c in g.checkpoints {
			if c.active || !rl.CheckCollisionRecs(pr, checkpoint_rect(c)) {
				continue
			}
			c.active = true
			c.pulse = 1
			g.player.spawn = checkpoint_spawn(c)
			play(&g.assets, .Power_Up)
		}

		if rl.CheckCollisionRecs(pr, goal_rect(g.goal)) {
			g.state = .Won
			play(&g.assets, .Power_Up)
		}
	}

	g.shake = max(0, g.shake - dt * 18)
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

	wanted := g.player.pos - {0, CAMERA_LOOKUP}
	g.camera.target += (wanted - g.camera.target) * min(1, CAMERA_SMOOTH * dt)

	bounds := tilemap_bounds(&g.world)
	if bounds.x > view.x {
		g.camera.target.x = clamp(g.camera.target.x, half.x, bounds.x - half.x)
	}
	if bounds.y > view.y {
		g.camera.target.y = clamp(g.camera.target.y, half.y, bounds.y - half.y)
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
	draw_sky(view)

	cam := g.camera
	if g.shake > 0 {
		cam.offset += {
			rand.float32_range(-g.shake, g.shake),
			rand.float32_range(-g.shake, g.shake),
		}
	}

	rl.BeginMode2D(cam)
	draw_parallax(view, 0.65, {74, 112, 105, 255}, 46, 96, -10)
	draw_parallax(view, 0.40, {58, 92, 88, 255}, 34, 74, 2)

	tilemap_draw(&g.world, &g.assets, view)

	for c in g.checkpoints {
		checkpoint_draw(c, &g.assets)
	}
	goal_draw(g.goal, &g.assets, g.time)
	for p in g.pickups {
		pickup_draw(p, &g.assets)
	}
	for e in g.enemies {
		enemy_draw(e)
	}
	player_draw(g.player, &g.assets)
	rl.EndMode2D()

	hud_draw(g)
	rl.EndDrawing()
}

// World height of the outdoor ground line. The parallax hills sit on it and the
// sky darkens into cave gloom below it.
HORIZON_Y :: 33 * TILE

@(private = "file")
color_lerp :: proc(a, b: rl.Color, t: f32) -> rl.Color {
	mix :: proc(x, y: u8, t: f32) -> u8 {
		return u8(f32(x) + (f32(y) - f32(x)) * t)
	}
	return {mix(a.r, b.r, t), mix(a.g, b.g, t), mix(a.b, b.b, t), 255}
}

@(private = "file")
draw_sky :: proc(view: rl.Rectangle) {
	depth := clamp((view.y + view.height / 2 - HORIZON_Y) / (8 * TILE), 0, 1)
	top := color_lerp({56, 78, 130, 255}, {16, 15, 26, 255}, depth)
	bottom := color_lerp({124, 145, 200, 255}, {30, 27, 44, 255}, depth)
	rl.DrawRectangleGradientV(0, 0, rl.GetScreenWidth(), rl.GetScreenHeight(), top, bottom)
}

// Rolling hills anchored to the horizon that scroll slower than the world.
// `depth` of 0 moves with the world, 1 would be pinned to the camera. Climbing
// or descending simply carries them out of view.
@(private = "file")
draw_parallax :: proc(view: rl.Rectangle, depth: f32, color: rl.Color, radius, spacing, y_offset: f32) {
	base_y := f32(HORIZON_Y) + y_offset
	if base_y - radius > view.y + view.height || base_y < view.y {
		return
	}
	lag := view.x * depth
	first := int(math.floor((view.x - lag) / spacing)) - 1
	count := int(view.width / spacing) + 3
	for i in first ..= first + count {
		rl.DrawCircleV({f32(i) * spacing + lag, base_y}, radius, color)
	}
}
