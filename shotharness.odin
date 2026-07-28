package game

import "core:fmt"
import "core:os"
import rl "vendor:raylib"

// TEMPORARY: drives the game without input so screenshots can be captured.
// Deleted once the visuals are verified.

shot_buf: [64]u8

shot_harness :: proc(g: ^Game, frame: int) -> bool {
	SHOT_MODE := os.get_env_buf(shot_buf[:], "ODDY_SHOT")
	if SHOT_MODE == "" {
		return false
	}

	switch frame {
	case 2:
		if SHOT_MODE == "title" {
			break
		}
		g.state = .Playing
		if SHOT_MODE == "boss" {
			r := room_rect(g.world.boss)
			g.player.pos = {r.x + r.width / 2 - 60, r.y + r.height - 3 * TILE}
			g.camera.target = g.player.pos
		}
		if SHOT_MODE == "chest" {
			for c in g.chests {
				g.player.pos = c.pos
				g.camera.target = g.player.pos
				break
			}
		}
		if SHOT_MODE == "fight" {
			for e in g.enemies {
				if e.kind != .Golem {
					g.player.pos = {e.pos.x + 50, e.pos.y}
					g.camera.target = g.player.pos
					break
				}
			}
		}
	case 40:
		if SHOT_MODE == "chest" {
			chests_interact(g)
		}
	case 70:
		rl.TakeScreenshot(fmt.ctprintf("shot_%s.png", SHOT_MODE))
	case 75:
		if SHOT_MODE == "title" {
			g.state = .Title
		}
	case 90:
		return true
	}
	return false
}
