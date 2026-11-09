package game

import rl "../libs/raylib"

WINDOW_WIDTH :: 1280
WINDOW_HEIGHT :: 720

// A single frame never advances more than this. A hitch (window drag, load
// stall, the phone waking up) would otherwise move the player far enough to
// tunnel through tiles.
MAX_STEP :: 1.0 / 30.0

IS_MOBILE :: ODIN_PLATFORM_SUBTARGET == .Android

// On Android there is no `main`: raylib's `android_main` calls into the game
// through `oddy_android_main` in `main_android.odin` instead. A shared library
// with a `main` would have it run from the loader, before there is a window.
when !IS_MOBILE {
	main :: proc() {
		run()
	}
}

// The whole program: open the window, run the game until it is closed.
run :: proc() {
	when IS_MOBILE {
		rl.SetConfigFlags({.FULLSCREEN_MODE, .VSYNC_HINT})
		rl.InitWindow(0, 0, "Oddy")
	} else {
		rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
		rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "Oddy")
		rl.SetWindowMinSize(640, 360)
		rl.SetWindowPosition(200, 120)
	}
	defer rl.CloseWindow()

	rl.SetTargetFPS(60)
	// The HUD draws its own crosshair, so the system pointer is in the way.
	rl.HideCursor()
	// The back button pauses rather than killing the app outright.
	rl.SetExitKey(.KEY_NULL)

	rl.InitAudioDevice()
	defer rl.CloseAudioDevice()

	game: Game
	game_init(&game)
	defer game_destroy(&game)

	for !rl.WindowShouldClose() && !game.quit {
		when !IS_MOBILE {
			if rl.IsKeyPressed(.F11) {
				rl.ToggleFullscreen()
			}
		}

		game_update(&game, min(rl.GetFrameTime(), MAX_STEP))
		game_draw(&game)

		free_all(context.temp_allocator)
	}
	haptics_shutdown()
}
