package game

import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:os"
import rl "../libs/raylib"

/*
A soak test for development: build with `-define:SOAK=true` and the game,
instead of opening to play, plays itself for hours of game time in a few
seconds and says what went wrong. `tools/dev/soak.sh` builds and runs it;
name levels after it to check only those.

It plays the real game through `game_update`, a sixtieth of a second at a
time, with a hero that mashes buttons at random. It is looking for the ways a
level can get stuck, which nobody finds by playing well:

  a boss that leaves its arena, stops moving through its states, or never
  again leaves itself open, so the exit can never open;

  a boss fight that cannot be finished, or whose exit does not work after;

  a hero who ends up outside the level, or who dies and never comes back;

  anything that grows without end, or a number that stops being a number.

Every boss level is played three ways: at random; at random with a helping
hand that drops the hero onto the boss whenever it is open, which has to end
in a clear; and the same, dying in the moment of the last hit. Every other
level is played at random with the hero thrown somewhere new every few
seconds, so that every trap in it gets its turn.
*/

DEV_SOAK :: #config(SOAK, false)

// Set while the soak test wants its hero to live through anything, so that a
// boss fight can be played to the end by somebody who cannot play.
sim_immortal := false

_ :: fmt
_ :: math
_ :: rand
_ :: os
_ :: rl

when DEV_SOAK {
	soak_input: Input

	@(private = "file")
	DT :: 1.0 / 60
	@(private = "file")
	STALL :: 12.0 // seconds a boss may stay in one state
	@(private = "file")
	SHUT :: 30.0 // seconds a boss may go without being open

	@(private = "file")
	Mode :: enum {
		Random,
		Helped,
		Die_On_Last_Hit,
		Wander,
	}

	@(private = "file")
	Bot :: struct {
		move:      f32,
		move_y:    f32,
		jump_held: bool,
		hold:      int, // frames until the next change of mind
	}

	@(private = "file")
	bot_input :: proc(b: ^Bot) -> Input {
		b.hold -= 1
		in_: Input
		if b.hold <= 0 {
			b.hold = 4 + int(rand.int31_max(40))
			b.move = f32(rand.int31_max(3)) - 1
			b.move_y = f32(rand.int31_max(3)) - 1
			was := b.jump_held
			b.jump_held = rand.int31_max(3) > 0
			in_.jump = b.jump_held && !was
			in_.dash = rand.int31_max(4) == 0
			in_.down = rand.int31_max(8) == 0
		}
		in_.move = b.move
		in_.move_y = b.move_y
		in_.jump_held = b.jump_held
		return in_
	}

	@(private = "file")
	finite :: proc(v: rl.Vector2) -> bool {
		return !math.is_nan(v.x) && !math.is_nan(v.y) && !math.is_inf(v.x) && !math.is_inf(v.y)
	}

	// Somewhere with room to stand: two empty tiles over anything at all.
	@(private = "file")
	random_place :: proc(g: ^Game) -> (rl.Vector2, bool) {
		m := &g.map_tiles
		for _ in 0 ..< 200 {
			tx := 1 + int(rand.int31_max(i32(max(1, m.width - 2))))
			ty := 1 + int(rand.int31_max(i32(max(1, m.height - 2))))
			if tile_at(m, tx, ty) == .Empty && tile_at(m, tx, ty - 1) == .Empty {
				return {f32(tx) * TILE + TILE / 2, f32(ty + 1) * TILE}, true
			}
		}
		return {}, false
	}

	// Plays one level one way for `seconds` of game time. Returns what went
	// wrong, or "".
	@(private = "file")
	soak :: proc(g: ^Game, index: int, mode: Mode, seed: u64, seconds: f32) -> string {
		rand.reset(seed)
		if os.get_env("TRACE", context.temp_allocator) != "" {
			fmt.printfln("== %v seed %d", mode, seed)
		}
		level_enter(g, index)
		game_set_state(g, .Playing)
		g.fade = 0
		bot: Bot
		bounds := tilemap_bounds(&g.map_tiles)
		boss_fight := g.boss.present

		state := g.boss.state
		in_state: f32
		since_open: f32
		dead_for: f32
		hits_left := g.boss.hp
		downed := false
		won_at := -1
		hands_off: f32 // the moment after a hit in which the boss may not kill
		passive := seed % 2 == 1 // and in which this hero lets go of the pad
		sim_immortal = mode == .Helped || mode == .Die_On_Last_Hit
		defer sim_immortal = false
		deaths := 0

		frames := int(seconds * 60)
		for f in 0 ..< frames {
			at := f32(f) / 60
			soak_input = bot_input(&bot)
			if hands_off > 0 && passive {
				soak_input = {}
			}
			p := &g.player
			b := &g.boss

			if mode == .Wander && f % 240 == 239 && !p.dead {
				if where_, ok := random_place(g); ok {
					p.pos = where_
					p.vel = {}
					g.level.room = room_at(g, player_centre(p^))
				}
			}
			helped := mode == .Helped || mode == .Die_On_Last_Hit
			if helped && b.present && !b.beaten && b.state == .Open && b.timer > 0.3 && !p.dead && f % 20 == 0 {
				// The helping hand: dropped onto it from just above.
				br := boss_rect(b^)
				p.pos = {br.x + PLAYER_W / 2 + 1 + rand.float32() * (br.width - PLAYER_W - 2), br.y - 6}
				p.vel = {0, 200}
				p.dash_time = 0
			}
			if won_at < 0 && b.present && b.beaten {
				won_at = f
			}
			if won_at >= 0 && f == won_at + 90 && !p.dead {
				p.pos = g.level.exit // and out through the door
				p.vel = {}
			}

			was_state, was_dead := b.state, p.dead
			game_update(g, DT)
			free_all(context.temp_allocator)
			if os.get_env("TRACE", context.temp_allocator) != "" {
				if b.state != was_state {
					fmt.printfln("  %6.2f  %v -> %v  hp %d  boss %v  hero %v", at, was_state, b.state, b.hp, b.pos, p.pos)
				}
				if p.dead && !was_dead {
					fmt.printfln("  %6.2f  died at %v (boss %v at %v)", at, p.pos, b.state, b.pos)
				}
			}

			if g.state == .Cleared {
				return ""
			}
			if g.state != .Playing {
				return fmt.tprintf("%.1fs: the game left the level by itself (%v)", at, g.state)
			}
			if !finite(p.pos) || !finite(p.vel) {
				return fmt.tprintf("%.1fs: the hero is at %v going %v", at, p.pos, p.vel)
			}
			if p.pos.x < 0 || p.pos.x > bounds.x || p.pos.y < -bounds.y - 400 {
				return fmt.tprintf("%.1fs: the hero is outside the level at %v", at, p.pos)
			}
			dead_for = p.dead ? dead_for + DT : 0
			if dead_for > 3 {
				return fmt.tprintf("%.1fs: the hero died and never came back", at)
			}
			if len(g.enemies) > 64 || len(g.waves) > 64 || len(g.rocks) > 64 || len(g.arrows) > 256 || len(g.sparks) > 4000 {
				return fmt.tprintf("%.1fs: piling up: %d creatures, %d waves, %d rocks, %d arrows, %d sparks", at, len(g.enemies), len(g.waves), len(g.rocks), len(g.arrows), len(g.sparks))
			}
			for e in g.enemies {
				if e.alive && !finite(e.pos) {
					return fmt.tprintf("%.1fs: a %v is at %v", at, e.kind, e.pos)
				}
			}

			if !b.present {
				continue
			}
			if mode == .Die_On_Last_Hit && b.hp <= 0 && !downed {
				downed = true
				sim_immortal = false
				player_kill(g)
				sim_immortal = true
			}
			// Thrown off a boss, the hero must not be killed by it for coming
			// down on it, or inside it, before having had a chance to move.
			if helped && b.state == .Hurt && was_state != .Hurt {
				hands_off = BOSS_HURT + (passive ? 0.5 : 0.1)
				sim_immortal = false
			}
			if hands_off > 0 {
				hands_off -= DT
				by_boss := p.dead && !was_dead && rl.CheckCollisionRecs(player_rect(p^), boss_rect(b^))
				for e in g.enemies {
					// One of its young got there first: fair enough.
					by_boss &&= !(e.alive && rl.CheckCollisionRecs(player_rect(p^), enemy_rect(e)))
				}
				if by_boss {
					return fmt.tprintf("%.1fs: thrown off the %v at %v, the hero came down on it at %v and died", at, b.kind, b.pos, p.pos)
				}
				if hands_off <= 0 || p.dead {
					hands_off = 0
					sim_immortal = true
				}
			}
			if b.beaten {
				continue
			}
			if downed && b.hp > 0 {
				return fmt.tprintf("%.1fs: the %v took its last hit, the hero died, and it came back", at, b.kind)
			}
			if p.dead || deaths != g.deaths {
				// A death puts the boss back as it was: start counting again
				// once the hero is back.
				if !p.dead {
					deaths = g.deaths
				}
				hits_left = b.hp
				since_open = 0
				in_state = 0
			}
			if b.hp > hits_left {
				return fmt.tprintf("%.1fs: the %v healed (%d to %d)", at, b.kind, hits_left, b.hp)
			}
			hits_left = b.hp
			r := boss_rect(b^)
			if !finite(b.pos) || r.x < -1 || r.x + r.width > bounds.x + 1 || b.pos.y > bounds.y + 1 || r.y + r.height < 0 {
				return fmt.tprintf("%.1fs: the %v is out of its arena at %v (%v)", at, b.kind, b.pos, b.state)
			}
			if b.state != state {
				state = b.state
				in_state = 0
			}
			in_state += DT
			if in_state > STALL && !p.dead {
				return fmt.tprintf("%.1fs: the %v has been %v for %.0fs at %v", at, b.kind, b.state, in_state, b.pos)
			}
			since_open = b.state == .Open || b.state == .Hurt || b.state == .Waiting ? 0 : since_open + DT
			if since_open > SHUT {
				return fmt.tprintf("%.1fs: the %v has not been open for %.0fs", at, b.kind, since_open)
			}
		}
		if boss_fight && (mode == .Helped || mode == .Die_On_Last_Hit) {
			return fmt.tprintf("the %v was not beaten in %.0fs (%d hits left, %v), or the exit stayed shut", g.boss.kind, seconds, g.boss.hp, g.boss.state)
		}
		return ""
	}

	dev_soak_main :: proc() {
		rl.SetTraceLogLevel(.WARNING)
		rl.SetConfigFlags({})
		rl.InitWindow(320, 180, "Lumi soak")
		rl.InitAudioDevice()
		g := new(Game)
		game_init(g)
		sim_quiet = true
		vibration_on = false

		failed := 0
		for d, index in g.levels {
			wanted := len(os.args) <= 1
			for arg in os.args[1:] {
				wanted ||= arg == d.ident
			}
			if !wanted {
				continue
			}
			modes := d.has_boss ? []Mode{.Random, .Helped, .Die_On_Last_Hit} : []Mode{.Wander}
			for mode in modes {
				seeds, seconds := 12, f32(240)
				if mode != .Random && mode != .Wander {
					seeds, seconds = 60, 180
				}
				problems := 0
				first := ""
				for seed in 0 ..< seeds {
					if why := soak(g, index, mode, u64(seed) * 7919 + 1, seconds); why != "" {
						if problems == 0 {
							first = fmt.aprintf("seed %d, %s", seed, why)
						}
						problems += 1
					}
				}
				if problems > 0 {
					failed += 1
					fmt.printfln("%-6s %-16v FAILED %d of %d   %s", d.ident, mode, problems, seeds, first)
				} else {
					fmt.printfln("%-6s %-16v ok", d.ident, mode)
				}
			}
		}
		rl.CloseAudioDevice()
		rl.CloseWindow()
		os.exit(failed > 0 ? 1 : 0)
	}
}
