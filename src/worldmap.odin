package game

import "core:fmt"
import "core:math"
import rl "../libs/raylib"

/*
The world map: one page per world, its levels as stops along a winding path,
your hero standing on the one picked. Under each stop, three dots for its
medals. A secret level appears as a purple stop above the level whose secret
exit leads to it, and only once that exit has been found.

Phone: tap a stop to pick it, tap it again (or PLAY) to go. The arrows by the
title turn the page; HERO picks who you play as. Keyboard: left and right
move along the path, Q and E turn the page, Enter plays, H picks a hero, Esc
goes back to the title.
*/

World_Map :: struct {
	world:    int, // 1-based, the page shown
	selected: int, // index into `g.levels`, -1 for none
	avatar:   rl.Vector2, // where the hero is drawn, easing toward the stop
	hero:     Animator,
	picking:  bool, // the hero picker is open
	press:    int, // what the pointer went down on; see `map_hit`
}

@(private = "file")
NODE_R :: 12.0
@(private = "file")
SLOT_Y := [LEVELS_PER_WORLD]f32{132, 106, 128, 100, 122}

@(private = "file")
Map_Button :: enum {
	None,
	Back,
	Prev_World,
	Next_World,
	Play,
	Hero,
	Node, // offset by the level index; see `map_hit`
}

world_map_init :: proc(g: ^Game) {
	m := &g.world_map
	m.world = 1
	m.selected = -1
	m.press = -1
	world_map_show_world(g, 1)
}

// Turns to a world's page and picks the furthest open level on it.
@(private = "file")
world_map_show_world :: proc(g: ^Game, world: int) {
	m := &g.world_map
	m.world = clamp(world, 1, WORLDS)
	m.selected = -1
	for n := LEVELS_PER_WORLD; n >= 1; n -= 1 {
		if i, ok := find_level(g, m.world, n); ok && level_open(g, i) {
			m.selected = i
			break
		}
	}
	if m.selected >= 0 {
		m.avatar = node_pos(g, m.selected)
	}
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
	game_set_state(g, .Map)
}

// Where a level's stop is on the screen, in virtual pixels.
@(private = "file")
node_pos :: proc(g: ^Game, index: int) -> rl.Vector2 {
	view := view_size()
	d := &g.levels[index]
	slot := clamp(d.number, 1, LEVELS_PER_WORLD) - 1
	x := view.x * (0.14 + 0.18 * f32(slot))
	if d.secret {
		// Above the level whose secret exit leads here.
		for other in g.levels {
			if other.unlocks == d.ident {
				src := clamp(other.number, 1, LEVELS_PER_WORLD) - 1
				return {view.x * (0.14 + 0.18 * f32(src)) + 20, 62}
			}
		}
		return {x, 62}
	}
	return {x, SLOT_Y[slot]}
}

// The stops on the current page, in the order left and right walk them.
@(private = "file")
page_levels :: proc(g: ^Game) -> [dynamic]int {
	list := make([dynamic]int, context.temp_allocator)
	for d, i in g.levels {
		if d.world != g.world_map.world || d.number < 1 {
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
	w := min(f32(420), view.x - 16)
	return {(view.x - w) / 2, view.y - 66, w, 58}
}

// Half the width of the page title, so the page arrows sit just outside it.
// Measured once per frame by the draw and read back here.
@(private = "file")
title_half: f32 = 110

@(private = "file")
button_rect :: proc(b: Map_Button) -> rl.Rectangle {
	view := view_size()
	panel := panel_rect()
	#partial switch b {
	case .Back:
		return {6, 6, 26, 22}
	case .Prev_World:
		return {view.x / 2 - title_half - 30, 9, 22, 20}
	case .Next_World:
		return {view.x / 2 + title_half + 8, 9, 22, 20}
	case .Play:
		return {panel.x + panel.width - 92, panel.y + 15, 82, 28}
	case .Hero:
		return {view.x - 70, 6, 64, 22}
	}
	return {}
}

// What is under a point: a button, a stop (Node + level index), or nothing.
@(private = "file")
map_hit :: proc(g: ^Game, p: rl.Vector2) -> int {
	for b in ([?]Map_Button{.Back, .Prev_World, .Next_World, .Play, .Hero}) {
		if rl.CheckCollisionPointRec(p, grow_rect(button_rect(b), 4)) {
			return int(b)
		}
	}
	for i in page_levels(g) {
		if rl.Vector2Distance(p, node_pos(g, i)) < NODE_R + 6 {
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
	animator_play(&m.hero, &g.assets.player.idle)
	animator_update(&m.hero, dt)
	if m.selected >= 0 {
		m.avatar += (node_pos(g, m.selected) - m.avatar) * min(1, dt * 10)
	}
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
		turn_page(g, in_.page)
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
				m.selected = index
				play(&g.assets, .Menu_Move)
			}
		case hit == int(Map_Button.Back):
			play(&g.assets, .Menu_Select)
			game_set_state(g, .Title)
		case hit == int(Map_Button.Prev_World):
			turn_page(g, -1)
		case hit == int(Map_Button.Next_World):
			turn_page(g, 1)
		case hit == int(Map_Button.Play):
			enter_selected(g)
		case hit == int(Map_Button.Hero):
			m.picking = true
			play(&g.assets, .Menu_Select)
		}
	}
}

@(private = "file")
step_selection :: proc(g: ^Game, dir: int) {
	m := &g.world_map
	list := page_levels(g)
	at := -1
	for i, k in list {
		if i == m.selected {
			at = k
		}
	}
	for k := at + dir; k >= 0 && k < len(list); k += dir {
		if level_open(g, list[k]) {
			m.selected = list[k]
			play(&g.assets, .Menu_Move)
			return
		}
	}
}

@(private = "file")
turn_page :: proc(g: ^Game, dir: int) {
	next := g.world_map.world + dir
	if next < 1 || next > WORLDS {
		return
	}
	world_map_show_world(g, next)
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

// ----------------------------------------------------------------- draw ---

@(private = "file")
GOLD :: rl.Color{255, 206, 92, 255}
@(private = "file")
GOLD_LIGHT :: rl.Color{255, 240, 170, 255}
@(private = "file")
INK :: rl.Color{92, 60, 36, 255}

// The road on each world's page: its edge, its earth, and the lighter ruts.
@(private = "file")
MAP_ROAD := [WORLDS][3]rl.Color {
	{{61, 36, 24, 255}, {227, 168, 106, 255}, {242, 211, 162, 255}},
	{{28, 44, 74, 255}, {154, 208, 230, 255}, {214, 242, 255, 255}},
	{{26, 14, 26, 255}, {138, 90, 110, 255}, {255, 176, 74, 255}},
}

world_map_draw :: proc(g: ^Game) {
	a := &g.assets
	m := &g.world_map
	view := view_size()
	// The world itself, panning slowly, with a little shade at the top for
	// the title to sit on.
	draw_backdrop(g, WORLD_ZONES[m.world - 1], {g.time * 8, 120}, 240)
	rl.DrawRectangleGradientV(0, 0, rl.GetScreenWidth(), i32(46 * hud_scale()), {20, 14, 30, 120}, {20, 14, 30, 0})

	// The title, with page arrows when there is somewhere to turn to.
	title := fmt.ctprintf("WORLD %v  %s", m.world, WORLD_NAMES[m.world - 1])
	size: f32 = 16
	// A long name on a narrow phone drops to the small size rather than run
	// into the buttons in the corners.
	if text_width(a, title, size) > view.x - 200 {
		size = 8
	}
	title_half = text_width(a, title, size) / 2
	draw_text_outlined_centered(a, title, size == 16 ? 10 : 14, size, GOLD, GOLD_LIGHT)
	if m.world > 1 {
		draw_arrow_button(g, button_rect(.Prev_World), -1)
	}
	if m.world < WORLDS {
		draw_arrow_button(g, button_rect(.Next_World), 1)
	}
	draw_back_button(g, button_rect(.Back))
	draw_hero_button(g)

	list := page_levels(g)
	if !world_open(g, m.world) || len(list) == 0 {
		msg: cstring = len(list) == 0 ? "COMING SOON" : "CLEAR THE WORLD BEFORE TO OPEN THIS ONE"
		draw_text_outlined_centered(a, msg, 108, 8, {210, 210, 230, 255})
		draw_totals(g)
		return
	}

	// The road through every slot of the world, built or not, and a dotted
	// trail up to any secret found.
	draw_road(g, MAP_ROAD[m.world - 1])
	for i in list {
		if !g.levels[i].secret {
			continue
		}
		for other, j in g.levels {
			if other.unlocks == g.levels[i].ident {
				draw_dotted(node_pos(g, j), node_pos(g, i), {200, 150, 255, 170})
			}
		}
	}
	// Slots that have no level in the file yet.
	for n in 1 ..= LEVELS_PER_WORLD {
		if _, ok := find_level(g, m.world, n); !ok {
			pos := rl.Vector2{view.x * (0.14 + 0.18 * f32(n - 1)), SLOT_Y[n - 1]}
			fill_circle(pos, NODE_R, {40, 36, 52, 160})
			draw_text_center_at(a, "?", pos - {0, 4}, 8, {120, 116, 140, 255})
		}
	}

	for i in list {
		draw_node(g, i)
	}

	// The hero, standing on the picked stop.
	if m.selected >= 0 && m.hero.anim != nil {
		s := hud_scale()
		bob := math.sin(g.time * 3) * 0.6
		anim_draw_frame(m.hero.anim, m.hero.frame, (m.avatar - {0, NODE_R - 2 + bob}) * s, false, rl.WHITE, s)
	}

	draw_info_panel(g)
	draw_totals(g)
	if m.picking {
		draw_hero_picker(g)
	}
}

@(private = "file")
draw_node :: proc(g: ^Game, i: int) {
	a := &g.assets
	d := &g.levels[i]
	pos := node_pos(g, i)
	open := level_open(g, i)
	l := save_level(&g.save, d.ident)
	selected := i == g.world_map.selected

	body: rl.Color
	switch {
	case !open:
		body = {70, 66, 84, 255}
	case d.secret:
		body = {150, 100, 220, 255}
	case l.cleared:
		body = {232, 182, 70, 255}
	case:
		body = {92, 190, 120, 255}
	}
	if selected {
		pulse := 0.5 + 0.5 * math.sin(g.time * 5)
		ring(pos, NODE_R + 4 + pulse * 1.5, 1.5, {255, 240, 190, 220})
	}
	// A medallion on the road: a shadow, a dark rim, the colour, and a
	// lighter top half where the light catches it.
	fill_circle(pos + {0, 3}, NODE_R + 1, {20, 14, 30, 110})
	fill_circle(pos, NODE_R + 1.5, {40, 26, 34, 255})
	fill_circle(pos, NODE_R, lerp_color(body, {0, 0, 0, 255}, 0.18))
	fill_circle(pos - {0, 1.5}, NODE_R - 1.5, body)
	fill_circle(pos - {2.5, 4}, 3, lerp_color(body, {255, 255, 255, 255}, 0.5))
	label := d.secret ? fmt.ctprintf("S") : fmt.ctprintf("%v", d.number)
	if !open {
		label = "-"
	}
	draw_text_center_at(a, label, pos - {0, 3}, 8, {40, 26, 34, 200})
	draw_text_center_at(a, label, pos - {0, 4}, 8, {255, 255, 255, 255})

	// Three dots for the medals: time, deathless, fruit.
	if open {
		medals := level_medals(g, i)
		for medal, k in Medal {
			c := rl.Vector2{pos.x - 7 + f32(k) * 7, pos.y + NODE_R + 6}
			fill_circle(c, 2.3, {10, 8, 16, 160})
			if medal in medals {
				fill_circle(c, 2, MEDAL_COLOURS[medal])
			} else {
				ring(c, 2, 0.8, {200, 196, 214, 160})
			}
		}
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
draw_info_panel :: proc(g: ^Game) {
	a := &g.assets
	m := &g.world_map
	panel := panel_rect()
	draw_panel(g, panel)
	if m.selected < 0 {
		return
	}
	d := &g.levels[m.selected]
	l := save_level(&g.save, d.ident)
	x := panel.x + 12
	draw_text(a, d.name, {x, panel.y + 10}, 8, {255, 244, 222, 255})
	line: cstring
	if l.cleared {
		line = fmt.ctprintf("BEST %s   %v DEATHS", format_time(l.best_time), l.best_deaths)
	} else {
		line = "NOT CLEARED YET"
	}
	draw_text(a, line, {x, panel.y + 22}, 8, {230, 214, 190, 255})
	gems_of := len(d.gems) + d.crates * GEMS_PER_CRATE
	extra := fmt.ctprintf("FRUIT %v/%v   GEMS %v/%v", fruit_count(l.fruit), len(d.fruit), l.best_gems, gems_of)
	if d.par > 0 {
		extra = fmt.ctprintf("FRUIT %v/%v   GEMS %v/%v   PAR %s", fruit_count(l.fruit), len(d.fruit), l.best_gems, gems_of, format_time(d.par))
	}
	draw_text(a, extra, {x, panel.y + 34}, 8, {230, 214, 190, 255})

	r := button_rect(.Play)
	pressed := g.world_map.press == int(Map_Button.Play) && rl.IsMouseButtonDown(.LEFT)
	tex := a.ui.button[.Green][pressed ? 1 : 0]
	draw_nine(tex, r)
	tw := text_width(a, "PLAY", 16)
	draw_text(a, "PLAY", {r.x + (r.width - tw) / 2, r.y + (r.height - 2 - 16) / 2 + (pressed ? 2 : 0)}, 16, rl.WHITE)
}

@(private = "file")
draw_totals :: proc(g: ^Game) {
	a := &g.assets
	view := view_size()
	t := progress_totals(g)
	s := hud_scale()
	y: f32 = 32
	anim := &a.fruit[0]
	anim_draw_frame(anim, int(g.time / anim.frame_time) % anim.count, {(view.x - 58) * s, (y + 4) * s}, false, rl.WHITE, s * 0.6)
	draw_text_shadow(a, fmt.ctprintf("%v", t.fruit), {view.x - 50, y}, 8, rl.RAYWHITE)
	fill_circle({view.x - 30, y + 4}, 3, MEDAL_COLOURS[.Time])
	draw_text_shadow(a, fmt.ctprintf("%v", t.medals), {view.x - 24, y}, 8, rl.RAYWHITE)
	gem := &a.gem
	anim_draw_frame(gem, int(g.time / gem.frame_time) % gem.count, {(view.x - 82) * s, (y + 4) * s}, false, rl.WHITE, s)
	draw_text_shadow(a, fmt.ctprintf("%v", t.gems), {view.x - 75, y}, 8, rl.RAYWHITE)
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
draw_arrow_button :: proc(g: ^Game, r: rl.Rectangle, dir: f32) {
	s := hud_scale()
	draw_nine(g.assets.ui.button[.Yellow][0], r)
	c := rl.Vector2{r.x + r.width / 2, r.y + r.height / 2 - 1}
	tri((c + {dir * 5, 0}) * s, (c + {-dir * 3, -6}) * s, (c + {-dir * 3, 6}) * s, rl.WHITE)
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

// A winding dirt road through the five stops: a dark edge, the earth, and
// paler ruts down the middle, sampled along a smooth curve.
@(private = "file")
draw_road :: proc(g: ^Game, c: [3]rl.Color) {
	view := view_size()
	pts: [LEVELS_PER_WORLD + 2]rl.Vector2
	for n in 0 ..< LEVELS_PER_WORLD {
		pts[n + 1] = {view.x * (0.14 + 0.18 * f32(n)), SLOT_Y[n]}
	}
	pts[0] = pts[1] - {60, -14} // the road comes in from off the left edge
	pts[LEVELS_PER_WORLD + 1] = pts[LEVELS_PER_WORLD] + {60, 10}
	samples := make([dynamic]rl.Vector2, context.temp_allocator)
	for i in 0 ..< len(pts) - 1 {
		p0 := pts[max(i - 1, 0)]
		p1 := pts[i]
		p2 := pts[i + 1]
		p3 := pts[min(i + 2, len(pts) - 1)]
		for k in 0 ..< 14 {
			t := f32(k) / 14
			t2, t3 := t * t, t * t * t
			p := 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
			append(&samples, p)
		}
	}
	for p in samples {
		fill_circle(p + {0, 2}, 7.5, {20, 14, 30, 60})
	}
	for p in samples {
		fill_circle(p, 7, c[0])
	}
	for p in samples {
		fill_circle(p, 5.5, c[1])
	}
	for p, i in samples {
		if i % 3 == 0 {
			fill_circle(p + {0, -1.5}, 1, c[2])
			fill_circle(p + {0, 1.5}, 1, c[2])
		}
	}
}

@(private = "file")
draw_dotted :: proc(a, b: rl.Vector2, colour: rl.Color) {
	steps := int(rl.Vector2Distance(a, b) / 7)
	for i in 1 ..< steps {
		fill_circle(a + (b - a) * (f32(i) / f32(steps)), 1.3, colour)
	}
}

@(private = "file")
draw_text_center_at :: proc(a: ^Assets, text: cstring, pos: rl.Vector2, size: f32, colour: rl.Color) {
	draw_text(a, text, {pos.x - text_width(a, text, size) / 2, pos.y}, size, colour)
}
