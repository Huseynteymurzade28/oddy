package game

import "core:fmt"
import "core:math"
import rl "../libs/raylib"

/*
The world map: one page per world, and each page a little stretch of that
world. The ground is built from the world's own tiles and steps up toward
its boss; two pools cut it, each with a bridge. Every level is a stop along
the way:

  a lantern   dark while the level is shut, waiting once it is open, lit and
              warm once it is cleared
  a gate      the last stop of a world, where its keeper is
  a crystal   a secret level, on an islet of its own above the level whose
              secret exit leads to it; not there at all until it is found

Under each stop is a plaque with its number and three stars for its medals.
Your hero walks the ground from stop to stop. A stop you have just opened
lights up while you watch, the trail to it filling in stone by stone.

The scene (`world_map_draw_scene`) is drawn into the same picture as a level
is, so it gets the same glow; the buttons and the card (`world_map_draw`) go
over it.

Phone: tap a stop to pick it, tap it again (or PLAY) to go. The tabs under
the title turn the page; HERO picks who you play as. Keyboard: left and
right move along the path, Q and E turn the page, Enter plays, H picks a
hero, Esc goes back to the title.
*/

World_Map :: struct {
	world:       int, // 1-based, the page shown
	selected:    int, // index into `g.levels`, -1 for none
	avatar:      rl.Vector2, // the hero's feet, walking toward the stop
	hero:        Animator,
	facing_left: bool,
	picking:     bool, // the hero picker is open
	press:       int, // what the pointer went down on; see `map_hit`
	page_time:   f32, // how long this page has been showing
	card_time:   f32, // since the stop picked last changed
	slide:       f32, // 1 down to 0 while one page slides out and the next in
	slide_dir:   int,
	prev_world:  int, // the page sliding out
	known:       [64]bool, // levels the map has already shown as open
	reveal:      int, // the stop lighting up for the first time, or -1
	reveal_time: f32,
}

@(private = "file")
STOP_ROW := [LEVELS_PER_WORLD]int{9, 8, 9, 8, 7} // the ground's top, in tiles from the top of the screen
@(private = "file")
SLIDE_TIME :: 0.4
@(private = "file")
REVEAL_TIME :: 1.4
@(private = "file")
BLURB_TIME :: 6.0

@(private = "file")
Map_Button :: enum {
	None,
	Back,
	World_1,
	World_2,
	World_3,
	Play,
	Hero,
	Node, // offset by the level index; see `map_hit`
}

world_map_init :: proc(g: ^Game) {
	m := &g.world_map
	m.world = 1
	m.selected = -1
	m.press = -1
	m.reveal = -1
	// Whatever is open in the save is old news.
	for _, i in g.levels {
		if i < len(m.known) {
			m.known[i] = level_open(g, i)
		}
	}
	world_map_show_world(g, 1)
}

// Turns to a world's page and picks the furthest open level on it.
@(private = "file")
world_map_show_world :: proc(g: ^Game, world: int) {
	m := &g.world_map
	m.world = clamp(world, 1, WORLDS)
	m.selected = -1
	m.page_time = 0
	m.card_time = 0
	for n := LEVELS_PER_WORLD; n >= 1; n -= 1 {
		if i, ok := find_level(g, m.world, n); ok && level_open(g, i) {
			m.selected = i
			break
		}
	}
	if m.selected >= 0 {
		m.avatar = node_pos(g, m.selected)
	}
	notice_new(g)
}

// Shows the map with the given level picked, after playing it.
world_map_open :: proc(g: ^Game, select: int) {
	m := &g.world_map
	if select >= 0 && select < len(g.levels) {
		m.world = g.levels[select].world
		m.selected = select
		m.avatar = node_pos(g, select)
	}
	m.picking = false
	m.slide = 0
	m.page_time = 0
	m.card_time = 0
	notice_new(g)
	game_set_state(g, .Map)
}

// A stop on this page that has opened since the map last looked gets its
// moment: see `REVEAL_TIME`.
@(private = "file")
notice_new :: proc(g: ^Game) {
	m := &g.world_map
	m.reveal = -1
	for d, i in g.levels {
		if i >= len(m.known) || d.world != m.world || m.known[i] || !level_open(g, i) {
			continue
		}
		m.known[i] = true
		m.reveal = i
		m.reveal_time = 0
	}
}

// --------------------------------------------------------------- the land ---

@(private = "file")
stop_col :: proc(slot: int) -> int {
	return int(view_size().x * (0.14 + 0.18 * f32(slot)) / TILE)
}

// The top of the ground in a column, pools aside.
@(private = "file")
ground_row :: proc(col: int) -> int {
	if col <= stop_col(0) {
		return STOP_ROW[0]
	}
	for k in 0 ..< LEVELS_PER_WORLD - 1 {
		a, b := stop_col(k), stop_col(k + 1)
		if col <= b {
			return col < (a + b + 1) / 2 ? STOP_ROW[k] : STOP_ROW[k + 1]
		}
	}
	return STOP_ROW[LEVELS_PER_WORLD - 1]
}

// Two of the stretches between stops have a pool in the middle. Returns the
// row its bridge is on: level with the lower bank.
@(private = "file")
pool_at :: proc(col: int) -> (bridge: int, ok: bool) {
	for k in ([2]int{1, 3}) {
		a, b := stop_col(k), stop_col(k + 1)
		mid := (a + b + 1) / 2
		if b - a >= 4 && (col == mid - 1 || col == mid) {
			return max(STOP_ROW[k], STOP_ROW[k + 1]), true
		}
	}
	return 0, false
}

@(private = "file")
Land :: enum {
	Air,
	Ground,
	Liquid,
	Bridge,
}

@(private = "file")
land_at :: proc(col, row: int) -> Land {
	if bridge, ok := pool_at(col); ok {
		switch {
		case row == bridge:
			return .Bridge
		case row == bridge + 1:
			return .Liquid
		case row > bridge + 1:
			return .Ground
		}
		return .Air
	}
	return row >= ground_row(col) ? .Ground : .Air
}

// How high the hero's feet are at `x`.
@(private = "file")
walk_y :: proc(x: f32) -> f32 {
	col := int(math.floor(x / TILE))
	if bridge, ok := pool_at(col); ok {
		return f32(bridge) * TILE
	}
	return f32(ground_row(col)) * TILE
}

// Where a level's stop is: the spot on the ground the hero stands on, in
// virtual pixels.
@(private = "file")
node_pos :: proc(g: ^Game, index: int) -> rl.Vector2 {
	d := &g.levels[index]
	slot := clamp(d.number, 1, LEVELS_PER_WORLD) - 1
	if d.secret {
		// On an islet above the level whose secret exit leads here.
		for other in g.levels {
			if other.unlocks == d.ident {
				slot = clamp(other.number, 1, LEVELS_PER_WORLD) - 1
			}
		}
		return {f32(stop_col(slot)) * TILE + 8 + 44, f32(STOP_ROW[slot]) * TILE - 58}
	}
	return {f32(stop_col(slot)) * TILE + 8, f32(STOP_ROW[slot]) * TILE}
}

// The stops on a world's page, in the order left and right walk them.
@(private = "file")
page_levels :: proc(g: ^Game, world: int) -> [dynamic]int {
	list := make([dynamic]int, context.temp_allocator)
	for d, i in g.levels {
		if d.world != world || d.number < 1 {
			continue
		}
		if d.secret && !level_open(g, i) {
			continue // a secret stays secret until it is found
		}
		append(&list, i)
	}
	// By position along the path, left to right.
	for i in 1 ..< len(list) {
		for j := i; j > 0 && node_pos(g, list[j]).x < node_pos(g, list[j - 1]).x; j -= 1 {
			list[j], list[j - 1] = list[j - 1], list[j]
		}
	}
	return list
}

// --------------------------------------------------------------- layout ---

@(private = "file")
panel_rect :: proc() -> rl.Rectangle {
	view := view_size()
	w := min(f32(440), view.x - 12)
	return {(view.x - w) / 2, view.y - 67, w, 62}
}

@(private = "file")
TAB_W :: 58.0
@(private = "file")
TAB_GAP :: 4.0

@(private = "file")
button_rect :: proc(b: Map_Button) -> rl.Rectangle {
	view := view_size()
	panel := panel_rect()
	#partial switch b {
	case .Back:
		return {6, 6, 26, 22}
	case .World_1, .World_2, .World_3:
		k := f32(int(b) - int(Map_Button.World_1))
		total: f32 = TAB_W * WORLDS + TAB_GAP * (WORLDS - 1)
		return {(view.x - total) / 2 + k * (TAB_W + TAB_GAP), 28, TAB_W, 14}
	case .Play:
		return {panel.x + panel.width - 96, panel.y + 14, 86, 32}
	case .Hero:
		return {view.x - 70, 6, 64, 22}
	}
	return {}
}

// What is under a point: a button, a stop (Node + level index), or nothing.
@(private = "file")
map_hit :: proc(g: ^Game, p: rl.Vector2) -> int {
	for b in ([?]Map_Button{.Back, .World_1, .World_2, .World_3, .Play, .Hero}) {
		if rl.CheckCollisionPointRec(p, grow_rect(button_rect(b), 4)) {
			return int(b)
		}
	}
	for i in page_levels(g, g.world_map.world) {
		// The whole of a stop: its lantern above the ground, its plaque below.
		pos := node_pos(g, i)
		if rl.CheckCollisionPointRec(p, {pos.x - 20, pos.y - 36, 40, 60}) {
			return int(Map_Button.Node) + i
		}
	}
	return int(Map_Button.None)
}

@(private = "file")
grow_rect :: proc(r: rl.Rectangle, by: f32) -> rl.Rectangle {
	return {r.x - by, r.y - by, r.width + by * 2, r.height + by * 2}
}

// --------------------------------------------------------------- update ---

world_map_update :: proc(g: ^Game, dt: f32) {
	m := &g.world_map
	m.page_time += dt
	m.card_time += dt
	m.slide = max(0, m.slide - dt / SLIDE_TIME)
	if m.reveal >= 0 {
		if m.reveal_time == 0 {
			play(&g.assets, .Checkpoint)
		}
		m.reveal_time += dt
		if m.reveal_time > REVEAL_TIME {
			m.reveal = -1
		}
	}
	walk_hero(g, dt)

	if g.state_time < MENU_DELAY {
		m.press = -1
		return
	}
	if m.picking {
		hero_picker_update(g)
		return
	}

	in_ := g.input
	if in_.pause {
		game_set_state(g, .Title)
		return
	}
	if in_.nav_x != 0 {
		step_selection(g, in_.nav_x)
	}
	if in_.page != 0 {
		turn_page(g, m.world + in_.page)
	}
	if in_.hero {
		m.picking = true
		play(&g.assets, .Menu_Select)
		return
	}
	if in_.confirm {
		enter_selected(g)
		return
	}

	// Pointer: a press counts when it is let go over the same thing.
	p := rl.GetMousePosition() / hud_scale()
	if rl.IsMouseButtonPressed(.LEFT) {
		m.press = map_hit(g, p)
	}
	if rl.IsMouseButtonReleased(.LEFT) && m.press >= 0 {
		hit := map_hit(g, p)
		pressed := m.press
		m.press = -1
		if hit != pressed {
			return
		}
		switch {
		case hit >= int(Map_Button.Node):
			index := hit - int(Map_Button.Node)
			if index == m.selected {
				enter_selected(g)
			} else if level_open(g, index) {
				select(g, index)
			}
		case hit == int(Map_Button.Back):
			play(&g.assets, .Menu_Select)
			game_set_state(g, .Title)
		case hit >= int(Map_Button.World_1) && hit <= int(Map_Button.World_3):
			turn_page(g, hit - int(Map_Button.World_1) + 1)
		case hit == int(Map_Button.Play):
			enter_selected(g)
		case hit == int(Map_Button.Hero):
			m.picking = true
			play(&g.assets, .Menu_Select)
		}
	}
}

// The hero goes to the picked stop on foot: along the ground, up and down
// its steps, over the bridges. To and from a secret's islet it is a leap.
@(private = "file")
walk_hero :: proc(g: ^Game, dt: f32) {
	m := &g.world_map
	a := &g.assets
	anim := &a.player.idle
	if m.selected >= 0 {
		goal := node_pos(g, m.selected)
		on_ground := abs(m.avatar.y - walk_y(m.avatar.x)) < 20
		if g.levels[m.selected].secret || !on_ground {
			m.avatar += (goal - m.avatar) * min(1, dt * 9)
			if rl.Vector2Distance(goal, m.avatar) > 3 {
				anim = m.avatar.y > goal.y ? &a.player.jump : &a.player.fall
				m.facing_left = goal.x < m.avatar.x
			}
		} else {
			dx := goal.x - m.avatar.x
			if abs(dx) > 0.5 {
				speed := max(f32(110), abs(dx) * 3.5)
				m.avatar.x += math.sign(dx) * min(abs(dx), speed * dt)
				m.facing_left = dx < 0
				anim = &a.player.run
			}
			// Steps are taken at a hop rather than a snap.
			m.avatar.y += (walk_y(m.avatar.x) - m.avatar.y) * min(1, dt * 22)
		}
	}
	animator_play(&m.hero, anim)
	animator_update(&m.hero, dt)
}

@(private = "file")
select :: proc(g: ^Game, index: int) {
	g.world_map.selected = index
	g.world_map.card_time = 0
	play(&g.assets, .Menu_Move)
}

@(private = "file")
step_selection :: proc(g: ^Game, dir: int) {
	m := &g.world_map
	list := page_levels(g, m.world)
	at := -1
	for i, k in list {
		if i == m.selected {
			at = k
		}
	}
	for k := at + dir; k >= 0 && k < len(list); k += dir {
		if level_open(g, list[k]) {
			select(g, list[k])
			return
		}
	}
}

@(private = "file")
turn_page :: proc(g: ^Game, world: int) {
	m := &g.world_map
	if world < 1 || world > WORLDS || world == m.world {
		return
	}
	m.prev_world = m.world
	m.slide_dir = world > m.world ? 1 : -1
	m.slide = 1
	world_map_show_world(g, world)
	play(&g.assets, .Menu_Move)
}

@(private = "file")
enter_selected :: proc(g: ^Game) {
	m := &g.world_map
	if m.selected < 0 || !level_open(g, m.selected) {
		return
	}
	play(&g.assets, .Menu_Select)
	level_enter(g, m.selected)
	game_set_state(g, .Playing)
}

// ----------------------------------------------------------- hero picker ---

@(private = "file")
hero_card :: proc(skin: Skin) -> rl.Rectangle {
	view := view_size()
	gap: f32 = 6
	w := min(f32(112), (view.x - 24 - gap * 3) / 4)
	total := w * 4 + gap * 3
	return {(view.x - total) / 2 + f32(int(skin)) * (w + gap), 66, w, 96}
}

@(private = "file")
hero_picker_update :: proc(g: ^Game) {
	m := &g.world_map
	in_ := g.input
	if in_.pause || in_.hero {
		m.picking = false
		return
	}
	pick := -1
	if in_.nav_x != 0 {
		next := (int(g.save.skin) + in_.nav_x + len(Skin)) % len(Skin)
		pick = next
	}
	if rl.IsMouseButtonReleased(.LEFT) {
		p := rl.GetMousePosition() / hud_scale()
		pick = -2 // a tap outside the cards closes the picker
		for s in Skin {
			if rl.CheckCollisionPointRec(p, hero_card(s)) {
				pick = int(s)
			}
		}
	}
	if in_.confirm {
		m.picking = false
		return
	}
	if pick == -2 {
		m.picking = false
	} else if pick >= 0 {
		skin := Skin(pick)
		if skin_unlocked(g, skin) && skin != g.save.skin {
			g.save.skin = skin
			assets_use_skin(&g.assets, skin)
			save_write(&g.save)
			play(&g.assets, .Menu_Select)
		}
	}
}

// ------------------------------------------------------------ the scene ---

@(private = "file")
GOLD :: rl.Color{255, 206, 92, 255}
@(private = "file")
GOLD_LIGHT :: rl.Color{255, 240, 170, 255}
@(private = "file")
OUTLINE :: rl.Color{40, 26, 34, 255}

@(private = "file")
ease_out :: proc(t: f32) -> f32 {
	u := 1 - clamp(t, 0, 1)
	return 1 - u * u * u
}

// The page's zone while two pages are mid-slide: the old one for the first
// half, the new one after.
world_map_zone :: proc(g: ^Game) -> Zone {
	m := &g.world_map
	if m.slide > 0.5 && m.prev_world >= 1 {
		return WORLD_ZONES[m.prev_world - 1]
	}
	return WORLD_ZONES[m.world - 1]
}

world_map_draw_scene :: proc(g: ^Game) {
	m := &g.world_map
	view := view_size()
	zone := world_map_zone(g)
	draw_backdrop(g, zone, {g.time * 8, 120}, 240)
	midground_draw(g, zone, {g.time * 10 + f32(m.world) * 400, 120})

	if m.slide > 0 {
		e := ease_out(1 - m.slide)
		dir := f32(m.slide_dir)
		draw_land(g, m.prev_world, -dir * e * view.x)
		draw_land(g, m.world, dir * (1 - e) * view.x)
		// A breath of mist over the change of sky.
		c := ZONE_LOOKS[zone].haze
		c.a = u8(150 * (1 - abs(m.slide * 2 - 1)))
		rl.DrawRectangle(0, 0, rl.GetScreenWidth(), rl.GetScreenHeight(), c)
	} else {
		draw_land(g, m.world, 0)
	}
	// A little shade at the top for the title to sit on.
	rl.DrawRectangleGradientV(0, 0, rl.GetScreenWidth(), i32(50 * hud_scale()), {20, 14, 30, 130}, {20, 14, 30, 0})
}

@(private = "file")
map_hash :: proc(x, y, salt: int) -> int {
	h := (x * 73856093) ~ (y * 19349663) ~ (salt * 83492791)
	h = h ~ (h >> 13)
	return abs(h)
}

// One tile of the land, its edges on whole screen pixels so no seams show.
@(private = "file")
land_tile :: proc(tex: rl.Texture2D, col, row: int, x, y: f32, tint := rl.WHITE) {
	s := hud_scale()
	x0, y0 := math.round(x * s), math.round(y * s)
	x1, y1 := math.round((x + TILE) * s), math.round((y + TILE) * s)
	rl.DrawTexturePro(tex, terrain_source(col, row), {x0, y0, x1 - x0, y1 - y0}, {}, 0, tint)
}

// A whole page: its ground, its pools and bridges, the trail, the stops,
// and the hero if it is the page being shown. `off` slides it sideways.
@(private = "file")
draw_land :: proc(g: ^Game, world: int, off: f32) {
	m := &g.world_map
	view := view_size()
	zone := WORLD_ZONES[world - 1]
	tex := g.assets.terrain[zone]
	open := world_open(g, world)
	cols := int(view.x / TILE) + 1
	rows := int(view.y / TILE)
	frame := int(g.time / LIQUID_FRAME_TIME) % 4
	solid :: proc(col, row: int) -> bool {
		return land_at(col, row) == .Ground
	}

	for col in -1 ..= cols {
		x := f32(col) * TILE + off
		for row in 5 ..= rows {
			y := f32(row) * TILE
			switch land_at(col, row) {
			case .Ground:
				up, right := solid(col, row - 1), solid(col + 1, row)
				down, left := solid(col, row + 1), solid(col - 1, row)
				mask := int(up) | int(right) << 1 | int(down) << 2 | int(left) << 3
				// Darker the deeper, as in the levels.
				depth := 0
				for depth < 5 && solid(col, row - depth - 1) {
					depth += 1
				}
				k := u8(255 - depth * 15)
				land_tile(tex, mask, map_hash(col, row, world) % GROUND_VARIANTS, x, y, {k, k, u8(min(255, int(k) + depth * 5)), 255})
				if up && left && !solid(col - 1, row - 1) {land_tile(tex, 0, ROW_EXTRAS, x, y)}
				if up && right && !solid(col + 1, row - 1) {land_tile(tex, 1, ROW_EXTRAS, x, y)}
				if !up && land_at(col, row - 1) == .Air {
					land_tile(tex, 4 + map_hash(col, row, 5) % 4, ROW_EXTRAS, x, y - TILE)
					if h := map_hash(col, row, 9 + world) % 100; h < 30 {
						sway := math.round(math.sin(g.time * 2.2 + f32(col) * 0.7) * 1.2)
						land_tile(tex, 8 + h % 8, ROW_EXTRAS, x + sway, y - TILE)
					}
				}
			case .Liquid:
				land_tile(tex, (frame + col) % 4, ROW_LIQUID, x, y)
			case .Bridge:
				_, more_left := pool_at(col - 1)
				_, more_right := pool_at(col + 1)
				land_tile(tex, more_left && more_right ? 1 : more_right ? 0 : 3, ROW_PLATFORM, x, y)
			case .Air:
			}
		}
	}

	// The pools give off a little light: more of it where they are lava.
	rl.BeginBlendMode(.ADDITIVE)
	for col in -1 ..= cols {
		if bridge, ok := pool_at(col); ok {
			s := hud_scale()
			glow := zone == .Ember ? rl.Color{120, 50, 10, 255} : rl.Color{20, 44, 56, 255}
			x := (f32(col) * TILE + off) * s
			y := f32(bridge + 1) * TILE * s
			rl.DrawRectangleGradientV(i32(x), i32(y - 14 * s), i32(TILE * s) + 1, i32(14 * s), {0, 0, 0, 255}, glow)
		}
	}
	rl.EndBlendMode()

	draw_trail(g, world, off, open)

	list := page_levels(g, world)
	// A dotted way up to any secret found.
	for i in list {
		if !g.levels[i].secret {
			continue
		}
		for other, j in g.levels {
			if other.unlocks == g.levels[i].ident {
				from := node_pos(g, j) + {off + 4, -26}
				to := node_pos(g, i) + {off - 22, 6}
				steps := int(rl.Vector2Distance(from, to) / 6)
				for k in 1 ..< steps {
					f := f32(k) / f32(steps)
					twinkle := 0.6 + 0.4 * math.sin(g.time * 4 - f32(k))
					fill_circle(from + (to - from) * f, 1.2, {214, 170, 255, u8(210 * twinkle)})
				}
			}
		}
	}
	// Slots that have no level in the file yet: a bare signpost.
	for n in 1 ..= LEVELS_PER_WORLD {
		if _, ok := find_level(g, world, n); !ok {
			pos := rl.Vector2{f32(stop_col(n - 1)) * TILE + 8 + off, f32(STOP_ROW[n - 1]) * TILE}
			fill_rect(pos.x - 1, pos.y - 12, 2, 12, OUTLINE)
			draw_plaque(g, pos, "?", {96, 92, 112, 255})
		}
	}
	for i in list {
		draw_stop(g, i, off, open)
	}

	// The hero, wherever the walk has got to, and a marker over their head.
	if world == m.world && m.selected >= 0 && m.hero.anim != nil {
		s := hud_scale()
		feet := m.avatar + {off, 0}
		fill_rect(feet.x - 6, feet.y, 12, 1, {24, 18, 44, 70})
		fill_rect(feet.x - 7, feet.y + 1, 14, 1, {24, 18, 44, 70})
		rl.BeginBlendMode(.ADDITIVE)
		rl.DrawCircleGradient({feet.x * s, (feet.y - 12) * s}, 26 * s, {90, 80, 56, 255}, {0, 0, 0, 255})
		rl.EndBlendMode()
		anim_draw_frame(m.hero.anim, m.hero.frame, {math.round(feet.x * s), math.round(feet.y * s)}, m.facing_left, rl.WHITE, s)
		bob := math.abs(math.sin(g.time * 4)) * 3
		tip := feet + {0, -34 - bob}
		tri((tip + {-4.5, -6}) * s, (tip + {4.5, -6}) * s, (tip + {0, 1}) * s, OUTLINE)
		tri((tip + {-3, -5}) * s, (tip + {3, -5}) * s, (tip + {0, -0.5}) * s, GOLD)
	}

	// A shut world lies under a pall.
	if !open {
		c := ZONE_LOOKS[zone].shade
		c.a = 150
		s := hud_scale()
		rl.DrawRectangleGradientV(i32(off * s), i32(40 * s), i32(view.x * s) + 2, i32(60 * s), {c.r, c.g, c.b, 0}, c)
		rl.DrawRectangle(i32(off * s), i32(100 * s), i32(view.x * s) + 2, i32(view.y * s), c)
	}
}

// Stepping stones from each stop to the next, lit as far as you have got.
@(private = "file")
draw_trail :: proc(g: ^Game, world: int, off: f32, open: bool) {
	m := &g.world_map
	for k in 0 ..< LEVELS_PER_WORLD - 1 {
		next, ok := find_level(g, world, k + 2)
		reached := ok && open && level_open(g, next)
		x0 := f32(stop_col(k)) * TILE + 8
		x1 := f32(stop_col(k + 1)) * TILE + 8
		count := int((x1 - x0) / 9)
		for i in 1 ..< count {
			f := f32(i) / f32(count)
			x := math.round(x0 + (x1 - x0) * f)
			if abs(x - x0) < 11 || abs(x1 - x) < 11 {
				continue
			}
			y := walk_y(x) + 3
			lit := reached
			if reached && m.reveal == next {
				lit = f < m.reveal_time / (REVEAL_TIME * 0.5) // filling in toward the new stop
			}
			fill_rect(x - 2 + off, y, 4, 3, {30, 20, 30, 150})
			stone := lit ? GOLD_LIGHT : rl.Color{150, 146, 160, 255}
			fill_rect(x - 2 + off, y, 4, 2, lit ? GOLD : rl.Color{112, 108, 126, 255})
			fill_rect(x - 1 + off, y, 2, 1, stone)
		}
	}
}

// The board under a stop: its number, or whatever else is to be said.
@(private = "file")
draw_plaque :: proc(g: ^Game, pos: rl.Vector2, label: cstring, colour: rl.Color) {
	a := &g.assets
	w := max(f32(15), text_width(a, label, 8) + 7)
	x := math.round(pos.x - w / 2)
	y := pos.y + 5
	fill_rect(x - 1, y + 1, w + 2, 12, {20, 14, 30, 90})
	fill_rect(x - 1, y - 1, w + 2, 13, OUTLINE)
	fill_rect(x, y, w, 11, lerp_color(colour, {0, 0, 0, 255}, 0.22))
	fill_rect(x, y, w, 9, colour)
	fill_rect(x + 1, y, w - 2, 1, lerp_color(colour, {255, 255, 255, 255}, 0.45))
	if label == "#" {
		// A padlock, where a number has not been earned.
		ink := rl.Color{226, 224, 236, 255}
		fill_rect(pos.x - 3, y + 4, 6, 4, ink)
		fill_rect(pos.x - 2, y + 1, 1, 3, ink)
		fill_rect(pos.x + 1, y + 1, 1, 3, ink)
		fill_rect(pos.x - 2, y + 1, 4, 1, ink)
		fill_rect(pos.x - 0.5, y + 5, 1, 2, OUTLINE)
		return
	}
	tw := text_width(a, label, 8)
	draw_text(a, label, {pos.x - tw / 2 + 0.5, y + 2}, 8, {40, 26, 34, 170})
	draw_text(a, label, {pos.x - tw / 2 + 0.5, y + 1}, 8, rl.WHITE)
}

// A small five-pointed star, filled or hollow.
@(private = "file")
draw_star :: proc(c: rl.Vector2, r: f32, colour: rl.Color) {
	s := hud_scale()
	for k in 0 ..< 5 {
		a0 := f32(k) * math.TAU / 5 - math.PI / 2
		a1 := a0 + math.TAU / 10
		a2 := a0 - math.TAU / 10
		tip := c + {math.cos(a0), math.sin(a0)} * r
		l := c + {math.cos(a2), math.sin(a2)} * r * 0.45
		rr := c + {math.cos(a1), math.sin(a1)} * r * 0.45
		tri(tip * s, l * s, rr * s, colour)
		tri(c * s, l * s, rr * s, colour)
	}
}

MEDAL_COLOURS := [Medal]rl.Color {
	.Time      = {120, 210, 255, 255},
	.Deathless = {255, 120, 120, 255},
	.Fruit     = {140, 230, 110, 255},
}

MEDAL_NAMES := [Medal]cstring {
	.Time      = "TIME",
	.Deathless = "NO DEATHS",
	.Fruit     = "ALL FRUIT",
}

@(private = "file")
draw_medal_stars :: proc(c: rl.Vector2, medals: Medals, gap: f32, r: f32) {
	for medal, k in Medal {
		p := c + {(f32(k) - 1) * gap, 0}
		draw_star(p + {0, 0.8}, r + 1.2, {24, 16, 30, 200})
		draw_star(p, r, medal in medals ? MEDAL_COLOURS[medal] : rl.Color{104, 98, 118, 255})
	}
}

// A soft additive glow, for anything lit.
@(private = "file")
glow :: proc(pos: rl.Vector2, radius: f32, colour: rl.Color) {
	s := hud_scale()
	rl.BeginBlendMode(.ADDITIVE)
	rl.DrawCircleGradient(pos * s, radius * s, colour, {0, 0, 0, 255})
	rl.EndBlendMode()
}

// One stop: what stands on the ground there, its plaque and its stars.
@(private = "file")
draw_stop :: proc(g: ^Game, i: int, off: f32, world_is_open: bool) {
	m := &g.world_map
	d := &g.levels[i]
	pos := node_pos(g, i) + {off, 0}
	open := world_is_open && level_open(g, i)
	l := save_level(&g.save, d.ident)
	cleared := open && l.cleared
	boss := !d.secret && d.number == LEVELS_PER_WORLD
	zone := WORLD_ZONES[d.world - 1]
	t := g.time + f32(i) * 1.7

	// Coming alight for the first time: dark until the trail has reached
	// it, then a flash that settles.
	lit: f32 = open ? 1 : 0
	flash: f32
	if m.reveal == i {
		since := m.reveal_time - REVEAL_TIME * 0.5
		lit = since > 0 ? 1 : 0
		flash = since > 0 ? max(0, 1 - since / (REVEAL_TIME * 0.5)) : 0
	}

	if d.secret {
		// Its own islet, bobbing a little.
		tex := g.assets.terrain[zone]
		pos.y += math.round(math.sin(t * 1.2) * 1.5)
		land_tile(tex, 2, map_hash(i, 0, 3) % GROUND_VARIANTS, pos.x - 24, pos.y)
		land_tile(tex, 2 | 8, map_hash(i, 1, 3) % GROUND_VARIANTS, pos.x - 8, pos.y)
		land_tile(tex, 8, map_hash(i, 2, 3) % GROUND_VARIANTS, pos.x + 8, pos.y)
		for k in 0 ..< 3 {
			land_tile(tex, 4 + map_hash(i, k, 5) % 4, ROW_EXTRAS, pos.x - 24 + f32(k) * TILE, pos.y - TILE)
		}
	}

	switch {
	case boss:
		draw_gate(g, pos, zone, lit, cleared, t)
	case d.secret:
		draw_map_crystal(pos + {-13, 0}, t, cleared)
	case:
		draw_lantern(pos + {-17, 0}, lit, cleared, t)
	}

	if flash > 0 {
		// A ring of light going out from it, and sparks.
		centre := pos + {0, -14}
		s := hud_scale()
		rl.BeginBlendMode(.ADDITIVE)
		k := u8(255 * flash)
		rl.DrawRing(centre * s, (1 - flash) * 34 * s, ((1 - flash) * 34 + 6 * flash) * s, 0, 360, 40, {k, k, u8(f32(k) * 0.7), 255})
		for spark in 0 ..< 10 {
			a := f32(spark) * math.TAU / 10 + f32(i)
			p := centre + {math.cos(a), math.sin(a)} * (8 + (1 - flash) * 30)
			rl.DrawCircleV(p * s, 1.4 * flash * s, {k, k, u8(f32(k) * 0.6), 255})
		}
		rl.EndBlendMode()
		glow(centre, 44, {u8(170 * flash), u8(150 * flash), u8(90 * flash), 255})
	}

	// The plaque: gold once cleared, the world's green while it waits, grey
	// and locked until then.
	colour: rl.Color
	label: cstring
	switch {
	case !open || lit == 0:
		colour, label = {92, 88, 108, 255}, "#"
	case d.secret:
		colour, label = {150, 100, 220, 255}, "S"
	case cleared:
		colour, label = {226, 168, 56, 255}, fmt.ctprintf("%v", d.number)
	case:
		colour, label = {74, 176, 108, 255}, fmt.ctprintf("%v", d.number)
	}
	draw_plaque(g, pos, label, colour)
	if open {
		draw_medal_stars(pos + {0, 22}, level_medals(g, i), 7, 2.6)
	}

	// Mist hangs about a stop that is still shut.
	if !open {
		s := hud_scale()
		haze := ZONE_LOOKS[zone].haze
		for k in 0 ..< 3 {
			drift := math.sin(t * 0.7 + f32(k) * 2.1) * 6
			haze.a = u8(46 + 14 * math.sin(t + f32(k)))
			rl.DrawCircleV((pos + {drift + f32(k - 1) * 9, -10 - f32(k % 2) * 7}) * s, (9 + f32(k) * 2) * s, haze)
		}
	}
}

// A lantern on a post. `lit` is whether there is any flame in it at all;
// a cleared level's burns warm and steady, an open one's cool and small.
@(private = "file")
draw_lantern :: proc(foot: rl.Vector2, lit: f32, cleared: bool, t: f32) {
	wood := rl.Color{86, 58, 44, 255}
	fill_rect(foot.x - 1, foot.y - 23, 2, 23, OUTLINE)
	fill_rect(foot.x - 0.5, foot.y - 22, 1, 22, wood)
	fill_rect(foot.x - 1, foot.y - 23, 9, 2, OUTLINE)
	fill_rect(foot.x + 5, foot.y - 21, 1, 3, OUTLINE)
	// The lamp itself.
	lamp := rl.Vector2{foot.x + 5.5, foot.y - 14}
	fill_rect(lamp.x - 4, lamp.y - 5, 8, 10, OUTLINE)
	fill_rect(lamp.x - 3, lamp.y - 5, 6, 1, {120, 112, 130, 255})
	glass := rl.Color{58, 56, 76, 255}
	if lit > 0 {
		flicker := 0.85 + 0.15 * math.sin(t * 9)
		if cleared {
			glass = {255, 214, 120, 255}
			glow(lamp, 24 * flicker, {84, 58, 22, 255})
			glow(lamp, 9, {60, 46, 22, 255})
		} else {
			pulse := 0.6 + 0.4 * math.sin(t * 3)
			glass = lerp_color({96, 150, 190, 255}, {190, 236, 255, 255}, pulse)
			glow(lamp, 16 + 4 * pulse, {30, 60, 80, 255})
		}
	}
	fill_rect(lamp.x - 3, lamp.y - 4, 6, 8, glass)
	if lit > 0 {
		fill_rect(lamp.x - 1, lamp.y - 2, 2, 4, {255, 255, 240, 255})
	}
	fill_rect(lamp.x - 0.5, lamp.y - 4, 1, 8, {40, 26, 34, 120})
}

// The gate at the end of a world: two posts and a lintel with the keeper's
// mark on it. Its braziers burn once the level is open; beaten, it wears a
// crown instead of a skull.
@(private = "file")
draw_gate :: proc(g: ^Game, foot: rl.Vector2, zone: Zone, lit: f32, cleared: bool, t: f32) {
	stone := lerp_color(ZONE_LOOKS[zone].shade, {70, 64, 86, 255}, 0.55)
	light := lerp_color(stone, {255, 255, 255, 255}, 0.3)
	for side in ([2]f32{-1, 1}) {
		x := foot.x + side * 13
		fill_rect(x - 4, foot.y - 30, 8, 30, OUTLINE)
		fill_rect(x - 3, foot.y - 29, 6, 29, stone)
		fill_rect(x - 3, foot.y - 29, 2, 29, light)
		fill_rect(x - 5, foot.y - 4, 10, 4, OUTLINE)
		fill_rect(x - 4, foot.y - 3, 8, 3, stone)
		// A brazier on top of each post.
		fill_rect(x - 4, foot.y - 34, 8, 4, OUTLINE)
		if lit > 0 {
			f := math.sin(t * 11 + side) * 0.8
			flame := cleared ? rl.Color{255, 200, 90, 255} : ZONE_LOOKS[zone].accent
			s := hud_scale()
			tri(rl.Vector2{x - 3, foot.y - 34} * s, rl.Vector2{x + 3, foot.y - 34} * s, rl.Vector2{x + f, foot.y - 42 + f} * s, flame)
			fill_rect(x - 1, foot.y - 37, 2, 3, {255, 250, 220, 255})
			glow({x, foot.y - 37}, 20 + f * 2, mul_color(flame, {130, 110, 100, 255}))
		}
	}
	fill_rect(foot.x - 19, foot.y - 30, 38, 8, OUTLINE)
	fill_rect(foot.x - 18, foot.y - 29, 36, 6, stone)
	fill_rect(foot.x - 18, foot.y - 29, 36, 2, light)
	// The mark over the door.
	c := rl.Vector2{foot.x, foot.y - 26}
	fill_circle(c, 6.5, OUTLINE)
	if cleared {
		fill_circle(c, 5.5, {226, 168, 56, 255})
		gold := GOLD_LIGHT
		fill_rect(c.x - 3.5, c.y, 7, 2.5, gold)
		fill_rect(c.x - 3.5, c.y - 3, 1.5, 3, gold)
		fill_rect(c.x - 0.75, c.y - 3.5, 1.5, 3.5, gold)
		fill_rect(c.x + 2, c.y - 3, 1.5, 3, gold)
	} else {
		fill_circle(c, 5.5, lit > 0 ? rl.Color{196, 70, 78, 255} : rl.Color{92, 88, 108, 255})
		draw_skull(c.x - 3.5, c.y - 3.5, {250, 244, 236, 255})
	}
}

@(private = "file")
draw_map_crystal :: proc(foot: rl.Vector2, t: f32, cleared: bool) {
	s := hud_scale()
	pulse := 0.75 + 0.25 * math.sin(t * 2.4)
	base := cleared ? rl.Color{255, 200, 110, 255} : rl.Color{176, 120, 250, 255}
	bright := lerp_color(base, {255, 255, 255, 255}, 0.5 * pulse)
	dark := mul_color(base, {150, 130, 190, 255})
	shard :: proc(foot: rl.Vector2, h, w, lean: f32, fill, edge: rl.Color, s: f32) {
		tip := foot + {lean, -h}
		tri((foot + {-w - 1, 0}) * s, (foot + {w + 1, 0}) * s, (tip + {0, -1.5}) * s, OUTLINE)
		tri((foot + {-w, 0}) * s, (foot + {w, 0}) * s, tip * s, fill)
		rl.DrawLineEx((foot + {-w * 0.3, -1}) * s, tip * s, 0.8 * s, edge)
	}
	shard(foot + {-5, 0}, 11, 3, -3, dark, bright, s)
	shard(foot + {5, 0}, 9, 3, 3, dark, bright, s)
	shard(foot, 19, 4, 0.5, base, bright, s)
	glow(foot + {0, -9}, 26 * pulse, mul_color(base, {120, 110, 130, 255}))
}

// ----------------------------------------------------------- the buttons ---

world_map_draw :: proc(g: ^Game) {
	a := &g.assets
	m := &g.world_map
	view := view_size()

	// The world's name, dropping to the small size on a narrow phone rather
	// than run into the buttons in the corners.
	title := WORLD_NAMES[m.world - 1]
	size: f32 = 16
	if text_width(a, title, size) > view.x - 200 {
		size = 8
	}
	draw_text_outlined_centered(a, title, size == 16 ? 8 : 12, size, GOLD, GOLD_LIGHT)
	draw_world_tabs(g)

	// What the world is, said once when its page turns up, then out of the
	// way.
	if fade := clamp(BLURB_TIME - m.page_time, 0, 1) * clamp(m.page_time * 3 - 0.6, 0, 1); fade > 0 {
		for line, i in WORLD_BLURBS[m.world - 1] {
			draw_text_outlined_centered(a, line, 47 + f32(i) * 10, 8, {240, 236, 250, u8(235 * fade)})
		}
	}

	draw_back_button(g, button_rect(.Back))
	draw_hero_button(g)
	draw_totals(g)
	draw_info_card(g)
	if m.picking {
		draw_hero_picker(g)
	}
}

// One tab per world: its number, how many of its medals you have, and a
// padlock if it is still shut.
@(private = "file")
draw_world_tabs :: proc(g: ^Game) {
	a := &g.assets
	m := &g.world_map
	for w in 1 ..= WORLDS {
		r := button_rect(Map_Button(int(Map_Button.World_1) + w - 1))
		here := w == m.world
		open := world_open(g, w)
		got, of := 0, 0
		for d, i in g.levels {
			if d.world == w && d.number >= 1 {
				of += len(Medal)
				got += card(level_medals(g, i))
			}
		}
		accent := ZONE_LOOKS[WORLD_ZONES[w - 1]].accent
		if here {
			fill_rect(r.x - 2, r.y - 2, r.width + 4, r.height + 4, GOLD)
		}
		fill_rect(r.x - 1, r.y - 1, r.width + 2, r.height + 2, OUTLINE)
		fill_rect(r.x, r.y, r.width, r.height, here ? rl.Color{84, 62, 92, 255} : rl.Color{50, 40, 62, 235})
		fill_rect(r.x, r.y, r.width, 1, {255, 255, 255, 40})
		// The world's colour, as a gem.
		c := rl.Vector2{r.x + 8, r.y + r.height / 2}
		s := hud_scale()
		gem := open ? accent : rl.Color{110, 106, 124, 255}
		tri((c + {0, -4}) * s, (c + {4, 0}) * s, (c + {-4, 0}) * s, lerp_color(gem, {255, 255, 255, 255}, 0.35))
		tri((c + {0, 4}) * s, (c + {4, 0}) * s, (c + {-4, 0}) * s, gem)
		ink := here ? rl.WHITE : rl.Color{196, 190, 210, 255}
		if open {
			label := fmt.ctprintf("%v/%v", got, of)
			draw_text(a, label, {r.x + 15 + (r.width - 17 - text_width(a, label, 8)) / 2, r.y + 3}, 8, ink)
		} else {
			x := r.x + r.width / 2 + 5
			fill_rect(x - 3, r.y + 6, 6, 5, ink)
			fill_rect(x - 2, r.y + 3, 1, 3, ink)
			fill_rect(x + 1, r.y + 3, 1, 3, ink)
			fill_rect(x - 2, r.y + 3, 4, 1, ink)
		}
	}
}

// A little clock face.
@(private = "file")
draw_clock :: proc(c: rl.Vector2, colour: rl.Color) {
	fill_circle(c, 4.2, colour)
	fill_circle(c, 3, {84, 56, 40, 255})
	fill_rect(c.x - 0.5, c.y - 2.4, 1, 2.8, colour)
	fill_rect(c.x - 0.5, c.y - 0.4, 2.4, 1, colour)
}

// The card along the bottom: the stop picked, what you have done there, what
// is still to be won, and the way in. It slides up afresh with each pick.
@(private = "file")
draw_info_card :: proc(g: ^Game) {
	a := &g.assets
	m := &g.world_map
	s := hud_scale()
	panel := panel_rect()
	panel.y += (1 - ease_out(m.card_time / 0.22)) * 14
	draw_panel(g, panel)

	cream := rl.Color{255, 244, 222, 255}
	tan := rl.Color{236, 216, 186, 255}
	dim := rl.Color{186, 158, 128, 255}

	if !world_open(g, m.world) || m.selected < 0 {
		msg: cstring = fmt.ctprintf("BEAT WORLD %v TO OPEN THIS ONE", m.world - 1)
		if world_open(g, m.world) {
			msg = "COMING SOON"
		}
		draw_text(a, msg, {panel.x + (panel.width - text_width(a, msg, 8)) / 2, panel.y + 26}, 8, cream)
		return
	}

	d := &g.levels[m.selected]
	l := save_level(&g.save, d.ident)
	medals := level_medals(g, m.selected)

	// Its number, set into the board.
	badge := rl.Rectangle{panel.x + 9, panel.y + 9, 34, 40}
	draw_inlay(g, badge)
	number: cstring = d.secret ? "S" : fmt.ctprintf("%v", d.number)
	draw_text(a, number, {badge.x + (badge.width - text_width(a, number, 16)) / 2 + 1, badge.y + 5}, 16, {120, 84, 54, 255})
	draw_medal_stars({badge.x + badge.width / 2, badge.y + 30}, medals, 9, 3.2)

	x := badge.x + badge.width + 8
	room := button_rect(.Play).x - x - 6
	name_size: f32 = text_width(a, d.name, 16) <= room ? 16 : 8
	draw_text(a, d.name, {x, panel.y + (name_size == 16 ? 7 : 12) + 1}, name_size, {60, 38, 26, 150})
	draw_text(a, d.name, {x, panel.y + (name_size == 16 ? 7 : 12)}, name_size, cream)

	// What you have done here: fruit, gems, and your best run.
	y := panel.y + 28
	cx := x
	fruit := &a.fruit[(d.number * 3) % FRUIT_KINDS]
	anim_draw_frame(fruit, int(g.time / fruit.frame_time) % fruit.count, {(cx + 5) * s, (y + 4) * s}, false, rl.WHITE, s * 0.62)
	text := fmt.ctprintf("%v/%v", fruit_count(l.fruit), len(d.fruit))
	draw_text(a, text, {cx + 12, y}, 8, tan)
	cx += 18 + text_width(a, text, 8)
	gem := &a.gem
	anim_draw_frame(gem, int(g.time / gem.frame_time) % gem.count, {(cx + 5) * s, (y + 4) * s}, false, rl.WHITE, s)
	text = fmt.ctprintf("%v/%v", l.best_gems, len(d.gems) + d.crates * GEMS_PER_CRATE)
	draw_text(a, text, {cx + 12, y}, 8, tan)
	cx += 18 + text_width(a, text, 8)
	if l.cleared {
		draw_clock({cx + 4, y + 4}, tan)
		text = fmt.ctprintf("%s", format_time(l.best_time))
		draw_text(a, text, {cx + 11, y}, 8, .Time in medals ? GOLD_LIGHT : tan)
		cx += 17 + text_width(a, text, 8)
		if cx + 30 < x + room {
			draw_skull(cx, y, tan)
			draw_text(a, fmt.ctprintf("%v", l.best_deaths), {cx + 9, y}, 8, tan)
		}
	} else {
		draw_text(a, "NEW", {cx + 2, y}, 8, {170, 236, 150, 255})
	}

	// What is still to be won: the three medals, by name.
	y = panel.y + 43
	cx = x
	labels := [Medal]cstring {
		.Time      = d.par > 0 ? fmt.ctprintf("%d:%02d", int(d.par) / 60, int(d.par) % 60) : "TIME",
		.Deathless = "NO DEATHS",
		.Fruit     = "ALL FRUIT",
	}
	for medal in Medal {
		has := medal in medals
		draw_star({cx + 3.5, y + 4.8}, 4.6, {40, 26, 34, 190})
		draw_star({cx + 3.5, y + 4}, 3.6, has ? MEDAL_COLOURS[medal] : rl.Color{124, 100, 84, 255})
		draw_text(a, labels[medal], {cx + 10, y}, 8, has ? cream : dim)
		cx += 17 + text_width(a, labels[medal], 8)
	}

	// PLAY, breathing a little so the eye finds it.
	r := button_rect(.Play)
	r.y += panel.y - panel_rect().y
	pressed := m.press == int(Map_Button.Play) && rl.IsMouseButtonDown(.LEFT)
	if !pressed {
		swell := math.sin(g.time * 3.2) * 0.8
		r = grow_rect(r, swell)
	} else {
		r.y += 2
		r.height -= 2
	}
	draw_nine(a.ui.button[.Green][pressed ? 1 : 0], r)
	tw := text_width(a, "PLAY", 16)
	ty := r.y + (r.height - 2 - 16) / 2
	draw_text(a, "PLAY", {r.x + (r.width - tw) / 2, ty + 1}, 16, {20, 60, 30, 130})
	draw_text(a, "PLAY", {r.x + (r.width - tw) / 2, ty}, 16, rl.WHITE)
}

// Everything you have gathered, in a row of chips under the HERO button.
@(private = "file")
draw_totals :: proc(g: ^Game) {
	a := &g.assets
	view := view_size()
	t := progress_totals(g)
	s := hud_scale()
	y: f32 = 33
	x := view.x - 6
	chip :: proc(a: ^Assets, right, y: f32, text: cstring) -> (left: f32) {
		w := text_width(a, text, 8) + 17
		fill_rect(right - w - 1, y - 3, w + 2, 14, {40, 26, 34, 255})
		fill_rect(right - w, y - 2, w, 12, {50, 40, 62, 235})
		draw_text(a, text, {right - w + 13, y}, 8, rl.RAYWHITE)
		return right - w
	}
	left := chip(a, x, y, fmt.ctprintf("%v", t.medals))
	draw_star({left + 7, y + 4}, 4, MEDAL_COLOURS[.Time])
	left = chip(a, left - 4, y, fmt.ctprintf("%v", t.fruit))
	fruit := &a.fruit[0]
	anim_draw_frame(fruit, int(g.time / fruit.frame_time) % fruit.count, {(left + 7) * s, (y + 4) * s}, false, rl.WHITE, s * 0.6)
	left = chip(a, left - 4, y, fmt.ctprintf("%v", t.gems))
	gem := &a.gem
	anim_draw_frame(gem, int(g.time / gem.frame_time) % gem.count, {(left + 7) * s, (y + 4) * s}, false, rl.WHITE, s)
}

@(private = "file")
draw_hero_button :: proc(g: ^Game) {
	a := &g.assets
	r := button_rect(.Hero)
	draw_nine(a.ui.button[.Blue][0], r)
	tw := text_width(a, "HERO", 8)
	draw_text(a, "HERO", {r.x + (r.width - tw) / 2, r.y + 6}, 8, rl.WHITE)
}

@(private = "file")
draw_back_button :: proc(g: ^Game, r: rl.Rectangle) {
	s := hud_scale()
	draw_nine(g.assets.ui.button[.Grey][0], r, {255, 255, 255, 220})
	c := rl.Vector2{r.x + r.width / 2, r.y + r.height / 2 - 1}
	ink := rl.Color{80, 84, 100, 255}
	tri((c + {-5, 0}) * s, (c + {2, -6}) * s, (c + {2, 6}) * s, ink)
	fill_rect(c.x + 1, c.y - 2, 5, 4, ink)
}

@(private = "file")
draw_hero_picker :: proc(g: ^Game) {
	a := &g.assets
	view := view_size()
	draw_dim(150)
	draw_text_outlined_centered(a, "PICK A HERO", 40, 16, GOLD, GOLD_LIGHT)
	s := hud_scale()
	for skin in Skin {
		r := hero_card(skin)
		unlocked := skin_unlocked(g, skin)
		chosen := skin == g.save.skin
		draw_nine(a.ui.panel, {r.x, r.y, r.width, r.height + 8})
		if chosen {
			outline_rect(r.x + 3, r.y + 3, r.width - 6, r.height - 6, {255, 230, 140, 255})
		}
		anim := &a.skins[skin].idle
		frame := unlocked ? int(g.time / anim.frame_time) % anim.count : 0
		tint := unlocked ? rl.WHITE : rl.Color{20, 16, 30, 255}
		anim_draw_frame(anim, frame, {r.x + r.width / 2, r.y + 62} * s, false, tint, s * 1.5)
		name := SKIN_NAMES[skin]
		draw_text(a, name, {r.x + (r.width - text_width(a, name, 8)) / 2, r.y + 68}, 8, {255, 244, 222, 255})
		if !unlocked {
			for line, k in skin_hint(skin) {
				draw_text(a, line, {r.x + (r.width - text_width(a, line, 8)) / 2, r.y + 79 + f32(k) * 9}, 8, {230, 170, 150, 255})
			}
		}
	}
	draw_text_outlined_centered(a, "TAP A HERO TO PLAY AS THEM", view.y - 40, 8, {210, 210, 230, 255})
}
