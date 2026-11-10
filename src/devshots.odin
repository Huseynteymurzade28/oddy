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
				dev_input.nav_x = 0
				dev_input.page = 0
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
		g.level.room = room_at(g, player_centre(g.player))
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
		// The same map with some progress, mid-reveal, and the other worlds.
		for id in ([?]string{"W1_1", "W1_2", "W1_3"}) {
			g.save.levels[strings.clone(id)] = {cleared = true, best_time = 31.2, fruit = 3, best_gems = 20}
		}
		world_map_init(g)
		g.world_map.known[3] = false
		world_map_open(g, 2)
		frames(g, 62)
		shot(g, "02b_map_reveal")
		frames(g, 60, {nav_x = 1})
		shot(g, "02c_map_progress")
		frames(g, 12, {page = 1})
		shot(g, "02d_map_slide")
		frames(g, 60)
		shot(g, "02e_map_locked")
		visit(g, 1, 1, 2, 11, "03_w1")
		visit(g, 1, 1, 61, 11, "04_w1_walls")
		visit(g, 1, 2, 2, 11, "20_light")
		frames(g, 8, {dash = true, move = 1})
		shot(g, "21_light_spent")
		visit(g, 1, 2, 91, 11, "22_refill")
		visit(g, 1, 3, 2, 41, "23_climb")
		visit(g, 1, 4, 121, 11, "24_gauntlet")
		visit(g, 2, 1, 20, 20, "05_w2_swim")
		visit(g, 3, 1, 19, 17, "06_w3")
		visit(g, 1, 1, 26, 11, "07_door")
		frames(g, 34, {move = 1})
		shot(g, "08_crossing")
		game_set_state(g, .Paused)
		frames(g, 20)
		shot(g, "09_pause")
		g.ui.settings = true
		frames(g, 5)
		shot(g, "10_settings")
		visit(g, 2, 3, 60, 14, "14_w2")
		visit(g, 3, 3, 20, 30, "15_w3_climb")
		visit(g, 3, 4, 70, 12, "16_w3")
		visit(g, 1, 4, 2, 11, "11_x")
		frames(g, 320)
		shot(g, "12_sleepy")
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
