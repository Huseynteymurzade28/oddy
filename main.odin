package game

import rl "vendor:raylib"


Animation_Name :: enum {
	Idle,
	Run,
}


Animation :: struct {
	texture : rl.Texture2D,
	num_frames : int,
	frame_timer : f32,
	current_frame : int,
	frame_length : f32,
	name : Animation_Name,
}

update_animation :: proc(a: ^Animation) {
a.frame_timer += rl.GetFrameTime()

	if a.frame_timer > a.frame_length {
		a.current_frame += 1
		a.frame_timer = 0

		if a.current_frame == a.num_frames {
			a.current_frame = 0
		}
	}
}

draw_animation :: proc(a: Animation, pos: rl.Vector2, flip: bool) {

	width := f32(a.texture.width)
	height := f32(a.texture.height)

	source := rl.Rectangle {
		x = f32(a.current_frame) * width / f32(a.num_frames),
		y = 0,
		width = width / f32(	a.num_frames),
		height = height,
	}

	if flip {
		source.width = -source.width
	}


	dest := rl.Rectangle {
		x = pos.x,
		y = pos.y,
		width = width * 4 / f32(a.num_frames),
		height = height * 4
	}

	rl.DrawTexturePro(a.texture, source, dest, 0, 0, rl.WHITE)
}

main :: proc() {
	rl.InitWindow(1280, 720, "oddy")

	player_pos := rl.Vector2{640, 360}
	player_vel : rl.Vector2
	player_grounded : bool
	player_flip : bool

	player_run := Animation {
		texture = rl.LoadTexture("bruh_run.png"),
		num_frames = 4,
		frame_length = 0.1,
		name = .Run,
	}

	player_idle := Animation {
		texture = rl.LoadTexture("idle_bruh_man.png"),
		num_frames = 2,
		frame_length = 0.5,
		name = .Idle,
	}

	current_anim := player_idle

	for !rl.WindowShouldClose() {
		rl.BeginDrawing()
		rl.ClearBackground({124,145,200,128})

		if rl.IsKeyDown(.LEFT) {
			player_vel.x = -400
			player_flip = true
			if current_anim.name != .Run {
				current_anim = player_run
			}
		} else if rl.IsKeyDown(.RIGHT) {
			player_vel.x = 400
			player_flip = false
			if current_anim.name != .Run {
				current_anim = player_run
			}
		} else {
			player_vel.x = 0
			if current_anim.name != .Idle {
				current_anim = player_idle
			}
		}
		player_vel.y += 1800 * rl.GetFrameTime()
		if player_grounded && rl.IsKeyPressed(.SPACE) {
			player_vel.y = -600
			player_grounded = false
		}
		player_pos += player_vel * rl.GetFrameTime()

		if player_pos.y > f32(rl.GetScreenHeight() - 64) {
			player_pos.y = f32(rl.GetScreenHeight() - 64)
			player_grounded = true
		}

		update_animation(&current_anim)
		draw_animation(current_anim, player_pos, player_flip)

		rl.EndDrawing()
	}
}
