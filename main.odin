package game

import rl "vendor:raylib"

WINDOW_WIDTH :: 1280
WINDOW_HEIGHT :: 720

// A single frame never advances more than this. A hitch (window drag, load
// stall) would otherwise move the player far enough to tunnel through tiles.
MAX_STEP :: 1.0 / 30.0

main :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "Oddy")
	defer rl.CloseWindow()

	rl.SetWindowMinSize(640, 360)
	rl.SetWindowPosition(200, 120)
	rl.SetTargetFPS(60)
	// The HUD draws its own crosshair, so the system pointer is in the way.
	rl.HideCursor()

	rl.InitAudioDevice()
	defer rl.CloseAudioDevice()

	game: Game
	game_init(&game)
	defer game_destroy(&game)

	frame := 0
	for !rl.WindowShouldClose() {
		if rl.IsKeyPressed(.F11) {
			rl.ToggleFullscreen()
		}

		frame += 1
		if shot_harness(&game, frame) {
			break
		}

		game_update(&game, min(rl.GetFrameTime(), MAX_STEP))
		game_draw(&game)

		free_all(context.temp_allocator)
	}
}
