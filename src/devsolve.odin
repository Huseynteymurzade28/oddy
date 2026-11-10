package game

import pq "core:container/priority_queue"
import "core:fmt"
import "core:os"
import rl "../libs/raylib"

/*
A room solver for development: build with `-define:SOLVE=true` and the game,
instead of opening to play, tries to get through every room of every level
that has rooms, by brute force, and says how it went. `tools/dev/solve.sh`
builds and runs it; name levels after it to check only those.

It plays the real game: the same `player_update` and `things_update`, a
sixtieth of a second at a time. From a room's spawn point it tries every
button it could hold for the next few frames, then every button after each
of those, breadth first, and throws away any state it has in effect been in
before (same place, same speed, same light). It stops when something reaches
the next room, or the exit.

Each room is tried twice: plainly, with nothing but running, jumping, wall
jumps and the dash, and then with every trick allowed (supers, hypers, wall
bounces). The first is what anybody needs; the second is what a speedrunner
will do to it. For each it says how long its way through took and how many
jumps and dashes. A room it cannot solve is either impossible or
wants something the search is too coarse to find, and either way is worth a
look before anybody is asked to play it.

Not searched: creatures and breaking crates. A room that needs either will
come back unsolved.
*/

DEV_SOLVE :: #config(SOLVE, false)

// Set while the solver is playing: no sound, no breaking of crates.
sim_quiet := false
// And for its plain run: no supers, hypers or wall bounces, so that what it
// finds is a way through for somebody who has never heard of them.
sim_plain := false

_ :: fmt
_ :: pq
_ :: os
_ :: rl

when DEV_SOLVE {
	@(private = "file")
	SNAP_THINGS :: 8
	// Frames each choice of buttons is held. The plain run uses the longer:
	// a way through found at that grain does not hang on frame-perfect timing.
	@(private = "file")
	STEP_FRAMES := 3
	@(private = "file")
	PLAIN_STEP :: 5
	@(private = "file")
	TRICK_STEP :: 3
	@(private = "file")
	MAX_STATES :: 900_000
	// How much the search leans toward the goal rather than fanning out
	// evenly: 0 would be plain breadth first.
	@(private = "file")
	GREED :: 1.6
	@(private = "file")
	DT :: 1.0 / 60

	@(private = "file")
	Thing_Bits :: struct {
		pos:   rl.Vector2,
		vel:   rl.Vector2,
		t:     f32,
		dir:   f32,
		timer: f32,
		state: i32,
	}

	@(private = "file")
	Snap :: struct {
		steps:  i32, // from the start
		score:  f32, // steps plus how far there still is to go: lowest is tried next
		player: Player,
		things: [SNAP_THINGS]Thing_Bits,
		solid:  [Light_Kind]bool,
		held:   bool, // jump was held through the last step
		parent: i32,
		action: u8,
	}

	// What can be held for a step: left, right or neither; jump or not; and
	// a dash in one of eight directions, or none.
	@(private = "file")
	Action :: struct {
		move: f32,
		held: bool,
		dash: rl.Vector2, // zero for none
	}

	@(private = "file")
	actions: [dynamic]Action

	@(private = "file")
	room_things: [dynamic]int // indices into g.things of what is in the room

	@(private = "file")
	save_state :: proc(g: ^Game, s: ^Snap) {
		s.player = g.player
		s.solid = light_solid
		for idx, k in room_things {
			t := g.things[idx]
			s.things[k] = {t.pos, t.vel, t.t, t.dir, t.timer, i32(t.state)}
		}
	}

	@(private = "file")
	load_state :: proc(g: ^Game, s: ^Snap) {
		g.player = s.player
		light_solid = s.solid
		for idx, k in room_things {
			t := &g.things[idx]
			b := s.things[k]
			t.pos, t.vel, t.t, t.dir, t.timer, t.state = b.pos, b.vel, b.t, b.dir, b.timer, int(b.state)
			t.delta = {}
			t.ridden = false
		}
	}

	@(private = "file")
	tidy :: proc(g: ^Game) {
		clear(&g.sparks)
		clear(&g.poofs)
		for p in g.popups {
			delete(p.text)
		}
		clear(&g.popups)
		clear(&g.chips)
		clear(&g.confetti)
		g.freeze = 0
		g.shake = 0
	}

	// What makes two states the same for the search's purposes.
	@(private = "file")
	key_of :: proc(s: ^Snap) -> u64 {
		p := &s.player
		h: u64 = 1469598103934665603
		mix :: proc(h: ^u64, v: int) {
			h^ = (h^ ~ u64(u32(v))) * 1099511628211
		}
		mix(&h, int(p.pos.x / 3))
		mix(&h, int(p.pos.y / 3))
		mix(&h, int((p.vel.x + 2000) / 60))
		mix(&h, int((p.vel.y + 2000) / 60))
		flags := 0
		flags |= p.dashes > 0 ? 1 : 0
		flags |= p.dash_time > 0 ? 2 : 0
		flags |= s.held ? 4 : 0
		flags |= p.grounded ? 8 : 0
		flags |= p.wall_stick > 0 ? 16 : 0
		flags |= p.coyote > 0 ? 32 : 0
		flags |= p.holding_jump ? 64 : 0
		flags |= s.solid[.Lit] ? 128 : 0
		flags |= s.solid[.Dark] ? 256 : 0
		flags |= p.since_dash < DASH_TIME + SUPER_GRACE ? 512 : 0
		flags |= p.since_dash < DASH_COOLDOWN ? 1024 : 0
		mix(&h, flags)
		if p.dash_time > 0 {
			mix(&h, int(p.dash_dir.x * 2) + int(p.dash_dir.y * 2) * 8)
			mix(&h, int(p.dash_time * 60))
		}
		for k in 0 ..< len(room_things) {
			b := s.things[k]
			mix(&h, int(b.state))
			mix(&h, int(b.timer * 4))
			mix(&h, int(b.pos.y / 4))
			mix(&h, int(b.pos.x / 4))
		}
		return h
	}

	@(private = "file")
	Outcome :: struct {
		solved:  bool,
		frames:  int,
		jumps:   int,
		dashes:  int,
		states:  int,
		nearest: f32, // how close to the goal anything got, when not solved
	}

	@(private = "file")
	solve_room :: proc(g: ^Game, room: int) -> Outcome {
		l := &g.level
		rect := l.rooms[room]
		last := room == len(l.rooms) - 1
		goal_point: rl.Vector2
		if last {
			goal_point = l.exit - {0, 12}
		} else {
			// The doorway: the middle of whatever is open along the edge
			// the two rooms share.
			next := l.rooms[room + 1]
			sum: rl.Vector2
			count: f32
			for i in 0 ..< 40 {
				f := (f32(i) + 0.5) / 40
				q: rl.Vector2
				switch {
				case next.x >= rect.x + rect.width:
					q = {next.x + 4, rect.y + rect.height * f}
				case next.x + next.width <= rect.x:
					q = {rect.x - 4, rect.y + rect.height * f}
				case next.y + next.height <= rect.y:
					q = {rect.x + rect.width * f, rect.y - 4}
				case:
					q = {rect.x + rect.width * f, next.y + 4}
				}
				if !is_blocking(tile_at(&g.map_tiles, int(q.x / TILE), int(q.y / TILE))) {
					sum += q
					count += 1
				}
			}
			goal_point = count > 0 ? sum / count : rl.Vector2{next.x + next.width / 2, next.y + next.height / 2}
		}

		level_restart(g)
		spawn, ok := room_spawn(g, room, {rect.x, rect.y + rect.height})
		if !ok {
			return {}
		}
		player_init(&g.player, spawn)
		l.room = room
		clear(&room_things)
		for t, i in g.things {
			c := rl.Vector2{t.data.rect.x + t.data.rect.width / 2, t.data.rect.y + t.data.rect.height / 2}
			if rl.CheckCollisionPointRec(c, rect) && len(room_things) < SNAP_THINGS {
				append(&room_things, i)
			}
		}
		// Let the puff of arriving clear.
		for _ in 0 ..< 24 {
			g.input = {}
			things_update(g, DT)
			player_update(g, DT)
			tidy(g)
		}

		states := make([dynamic]Snap, 0, 1 << 16)
		defer delete(states)
		seen := make(map[u64]struct {}, 1 << 16)
		defer delete(seen)

		// A step can cover about this many pixels at the very most.
		reach: f32 = HYPER_X * DT * f32(STEP_FRAMES)
		Open :: struct {
			index: i32,
			score: f32,
		}
		open: pq.Priority_Queue(Open)
		pq.init(&open, proc(a, b: Open) -> bool {return a.score < b.score}, pq.default_swap_proc(Open))
		defer pq.destroy(&open)

		first: Snap
		save_state(g, &first)
		first.parent = -1
		append(&states, first)
		seen[key_of(&first)] = {}
		pq.push(&open, Open{0, 0})

		out := Outcome{nearest = 1e9}
		for pq.len(open) > 0 && len(states) < MAX_STATES {
			at := int(pq.pop(&open).index)
			can_dash := states[at].player.dashes > 0 && states[at].player.dash_time <= 0 && states[at].player.since_dash >= DASH_COOLDOWN - DT
			for a, ai in actions {
				if a.dash != {} && !can_dash {
					continue
				}
				load_state(g, &states[at])
				was_held := states[at].held
				alive := true
				won := false
				for f in 0 ..< STEP_FRAMES {
					in_ := Input{move = a.move, jump_held = a.held}
					if f == 0 {
						in_.jump = a.held && !was_held
						if a.dash != {} {
							in_.dash = true
							in_.move = a.dash.x
							in_.move_y = a.dash.y
						}
					}
					g.input = in_
					things_update(g, DT)
					player_update(g, DT)
					tidy(g)
					p := &g.player
					if p.dead {
						alive = false
						break
					}
					c := player_centre(p^)
					if last {
						if rl.CheckCollisionRecs(player_rect(p^), flag_rect(l.exit, EXIT_REACH)) {
							won = true
							break
						}
					}
					where_ := room_at(g, c)
					if where_ == room + 1 && !last {
						won = true
						break
					}
					if where_ != room {
						// Back the way it came, or out of the bottom.
						alive = false
						break
					}
				}
				if !alive {
					continue
				}
				next: Snap
				save_state(g, &next)
				next.held = a.held
				next.parent = i32(at)
				next.action = u8(ai)
				next.steps = states[at].steps + 1
				if won {
					// Walk back up the chain to count what it took.
					out.solved = true
					out.states = len(states)
					steps := 1
					prev_held := false
					chain := make([dynamic]u8, context.temp_allocator)
					append(&chain, next.action)
					for k := next.parent; k > 0; k = states[k].parent {
						append(&chain, states[k].action)
						steps += 1
					}
					for k := len(chain) - 1; k >= 0; k -= 1 {
						act := actions[chain[k]]
						if act.held && !prev_held {
							out.jumps += 1
						}
						if act.dash != {} {
							out.dashes += 1
						}
						prev_held = act.held
					}
					out.frames = steps * STEP_FRAMES
					if os.get_env("TRACE", context.temp_allocator) != "" {
						// Where it went, a step at a time, in tiles within the room.
						path := make([dynamic]i32, context.temp_allocator)
						for k := next.parent; k >= 0; k = states[k].parent {
							append(&path, k)
						}
						for k := len(path) - 1; k >= 0; k -= 1 {
							st := states[path[k]]
							act := actions[st.action]
							fmt.printfln("      %5.1f,%5.1f  v %4.0f,%4.0f  %s%s%s", (st.player.pos.x - rect.x) / TILE, (st.player.pos.y - rect.y) / TILE, st.player.vel.x, st.player.vel.y, st.player.dashes > 0 ? "lit " : "dark", act.held ? " jump" : "", act.dash != {} ? fmt.tprintf(" dash %v", act.dash) : "")
						}
					}
					return out
				}
				key := key_of(&next)
				if key in seen {
					continue
				}
				seen[key] = {}
				away := rl.Vector2Distance(player_centre(next.player), goal_point)
				next.score = f32(next.steps) + GREED * away / reach
				append(&states, next)
				pq.push(&open, Open{i32(len(states) - 1), next.score})
				out.nearest = min(out.nearest, away)
			}
		}
		out.states = len(states)
		return out
	}

	dev_solve_main :: proc() {
		rl.SetTraceLogLevel(.WARNING)
		rl.SetConfigFlags({})
		rl.InitWindow(320, 180, "Lumi solver")
		rl.InitAudioDevice()
		g := new(Game)
		game_init(g)
		sim_quiet = true
		vibration_on = false
		g.save.settings.endless_dash = false

		for move in ([3]f32{0, -1, 1}) {
			for held in ([2]bool{false, true}) {
				append(&actions, Action{move = move, held = held})
			}
		}
		for dir in ([8]rl.Vector2{{1, 0}, {-1, 0}, {0, -1}, {0, 1}, {1, -1}, {-1, -1}, {1, 1}, {-1, 1}}) {
			for held in ([2]bool{false, true}) {
				append(&actions, Action{move = dir.x, held = held, dash = dir})
			}
		}

		failed := 0
		for d, index in g.levels {
			if len(d.rooms) == 0 {
				continue
			}
			wanted := len(os.args) <= 1
			for arg in os.args[1:] {
				wanted ||= arg == d.ident
			}
			if !wanted {
				continue
			}
			level_enter(g, index)
			game_set_state(g, .Playing)
			fmt.printfln("%s  %s", d.ident, d.name)
			total := 0
			for room in 0 ..< len(d.rooms) {
				sim_plain = true
				STEP_FRAMES = PLAIN_STEP
				o := solve_room(g, room)
				sim_plain = false
				STEP_FRAMES = TRICK_STEP
				t := solve_room(g, room)
				tricks := t.solved ? fmt.tprintf("with tricks %.1fs", f32(t.frames) / 60) : "with tricks: unsolved"
				if o.solved {
					total += o.frames
					fmt.printfln("  room %d  ok   %.1fs  %d jumps  %d dashes  (%dk states)   %s", room + 1, f32(o.frames) / 60, o.jumps, o.dashes, o.states / 1000, tricks)
				} else {
					if !t.solved {
						failed += 1
					}
					fmt.printfln("  room %d  NO PLAIN WAY  nearest %.0fpx from the goal  (%dk states)   %s", room + 1, o.nearest, o.states / 1000, tricks)
				}
			}
			fmt.printfln("  plainly, start to finish: %.1fs", f32(total) / 60)
		}
		if failed > 0 {
			fmt.printfln("%d rooms unsolved", failed)
		}
		rl.CloseAudioDevice()
		rl.CloseWindow()
		os.exit(failed > 0 ? 1 : 0)
	}
}
