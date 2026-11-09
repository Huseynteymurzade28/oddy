package game

import "core:fmt"
import "core:strings"
import rl "../libs/raylib"

/*
A screenshot mode for development: build with `-define:SHOTS=true` and the
game plays a fixed script instead of reading the keyboard, saving a picture
at each step. `tools/dev/shots.sh` builds it, runs it and collects the
pictures in build/shots/. The window is a phone's shape (20:9).

To look at something new, add steps to `dev_script` below.
*/

DEV_SHOTS :: #config(SHOTS, false)

// Used only in the screenshot build.
_ :: fmt
_ :: strings
_ :: rl

when DEV_SHOTS {
	dev_input: Input
	dev_shot: cstring

	@(private = "file")
	frames :: proc(g: ^Game, n: int, in_: Input = {}) {
		for i in 0 ..< n {
			dev_input = in_
			if i > 0 {
				dev_input.jump = false
				dev_input.dash = false
			}
			game_update(g, 1.0 / 60)
			game_draw(g)
		}
	}

	@(private = "file")
	shot :: proc(g: ^Game, name: string) {
		dev_shot = strings.clone_to_cstring(fmt.tprintf("%s.png", name))
		game_draw(g)
	}

	// Puts the hero at a tile of a level (world, number) and lets the world
	// settle for a moment.
	@(private = "file")
	visit :: proc(g: ^Game, world, number, tx, ty: int, name: string, secret := false) {
		index, ok := find_level(g, world, number, secret)
		if !ok {
			return
		}
		if g.level.index != index || g.state != .Playing {
			level_enter(g, index)
		}
		game_set_state(g, .Playing)
		g.fade = 0
		player_init(&g.player, {f32(tx) * TILE + TILE / 2, f32(ty + 1) * TILE})
		g.player.respawn_time = 0
		camera_snap(g)
		frames(g, 40)
		shot(g, name)
	}

	@(private = "file")
	dev_script :: proc(g: ^Game) {
		frames(g, 50)
		shot(g, "01_title")
		world_map_open(g, 0)
		frames(g, 40)
		shot(g, "02_map")
		visit(g, 1, 1, 8, 17, "03_w1")
		visit(g, 1, 3, 62, 17, "04_w1_traps")
		visit(g, 2, 1, 20, 20, "05_w2_swim")
		visit(g, 3, 1, 19, 17, "06_w3")
		visit(g, 1, 1, 42, 17, "07_lantern")
		frames(g, 20, {move = 1})
		shot(g, "08_lantern_lit")
		game_set_state(g, .Paused)
		frames(g, 20)
		shot(g, "09_pause")
	}

	dev_shots_main :: proc() {
		rl.SetConfigFlags({}) // no vsync: a hidden window must not block
		rl.InitWindow(1200, 540, "Lumi shots")
		rl.SetWindowMinSize(1200, 540)
		rl.SetWindowMaxSize(1200, 540)
		rl.InitAudioDevice()
		g := new(Game)
		game_init(g)
		dev_script(g)
		game_destroy(g)
		rl.CloseAudioDevice()
		rl.CloseWindow()
	}

	// Called at the end of a frame's drawing: saves the picture if one was
	// asked for. The blend-mode flip flushes the batch first, or the HUD
	// would be missing from the picture.
	dev_capture :: proc() {
		if dev_shot == "" {
			return
		}
		rl.BeginBlendMode(.ADDITIVE)
		rl.EndBlendMode()
		rl.TakeScreenshot(dev_shot)
		delete(dev_shot)
		dev_shot = ""
	}
} else {
	dev_capture :: proc() {}
}
