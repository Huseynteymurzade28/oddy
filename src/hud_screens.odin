package game

import "core:fmt"
import "core:math"
import rl "../libs/raylib"

/*
The full-screen cards: the title, the pause card, and the two ways a run can
end. Each is a wooden board over the dimmed world with its buttons on it (the
buttons themselves live in `ui.odin`). They read their words from `lore.odin`
so the story is written in one place.
*/

@(private = "file")
GOLD :: rl.Color{255, 206, 92, 255}
@(private = "file")
GOLD_LIGHT :: rl.Color{255, 240, 170, 255}
@(private = "file")
CREAM :: rl.Color{255, 244, 222, 255}
@(private = "file")
INK :: rl.Color{92, 60, 36, 255} // text on parchment
@(private = "file")
DIM :: rl.Color{200, 206, 226, 255}

// A soft fade from clear at the top to dark at the bottom, so the boards and
// buttons stand off the world without blacking it out.
@(private = "file")
draw_shade :: proc(top, bottom: u8) {
	rl.DrawRectangleGradientV(
		0,
		0,
		rl.GetScreenWidth(),
		rl.GetScreenHeight(),
		{14, 10, 26, top},
		{14, 10, 26, bottom},
	)
}

@(private = "file")
centred_in :: proc(a: ^Assets, r: rl.Rectangle, text: cstring, y, size: f32, colour: rl.Color) {
	draw_text(a, text, {r.x + (r.width - text_width(a, text, size)) / 2, y}, size, colour)
}

draw_title_screen :: proc(g: ^Game) {
	a := &g.assets
	view := view_size()
	draw_shade(70, 170)

	if g.ui.how_to {
		draw_how_to(g)
		draw_menu(g)
		return
	}

	// The name drops in, overshoots a little, settles, and then bobs gently.
	t := min(g.state_time * 2.2, 1)
	drop := (1 - t) * (1 - t) * -40 + math.sin(t * math.PI) * 3
	bob := math.sin(g.time * 1.8) * 1.5
	draw_text_outlined_centered(a, GAME_TITLE, 20 + drop + bob, 48, GOLD, GOLD_LIGHT)
	draw_text_outlined_centered(a, GAME_TAGLINE, 74, 8, {222, 200, 255, 255})

	draw_panel(g, menu_panel(g))
	draw_menu(g)

	if g.runs > 1 && (g.best_rooms > 0 || g.best_kills > 0) {
		draw_text_outlined_centered(
			a,
			fmt.ctprintf("BEST  %v ROOMS  -  %v KILLS", g.best_rooms, g.best_kills),
			view.y - 16,
			8,
			DIM,
		)
	}
}

@(private = "file")
draw_how_to :: proc(g: ^Game) {
	a := &g.assets
	panel := menu_panel(g)
	draw_panel(g, panel)
	draw_text_outlined(a, "HOW TO PLAY", {panel.x + (panel.width - text_width(a, "HOW TO PLAY", 16)) / 2, panel.y + 8}, 16, GOLD, GOLD_LIGHT)

	inlay := rl.Rectangle{panel.x + 10, panel.y + 30, panel.width - 20, panel.height - 30 - BUTTON_H - 20}
	draw_inlay(g, inlay)
	y := inlay.y + 8
	for line in LORE_INTRO {
		centred_in(a, inlay, line, y, 8, INK)
		y += 11
	}
	y += 6
	when TOUCH_CONTROLS {
		lines := LORE_HOW_TO_TOUCH[:]
	} else {
		lines := LORE_HOW_TO[:]
	}
	for line in lines {
		centred_in(a, inlay, line, y, 8, {120, 84, 54, 255})
		y += 11
	}
}

draw_pause_screen :: proc(g: ^Game) {
	a := &g.assets
	draw_shade(110, 190)
	panel := menu_panel(g)
	draw_panel(g, panel)
	draw_text_outlined(a, "PAUSED", {panel.x + (panel.width - text_width(a, "PAUSED", 16)) / 2, panel.y + 9}, 16, GOLD, GOLD_LIGHT)
	inlay := rl.Rectangle{panel.x + 10, panel.y + 30, panel.width - 20, 16}
	draw_inlay(g, inlay)
	centred_in(a, inlay, objective_text(g), inlay.y + 4, 8, INK)
	draw_menu(g)
}

draw_end_screen :: proc(g: ^Game) {
	a := &g.assets
	won := g.state == .Won
	draw_shade(won ? 100 : 130, 210)
	panel := menu_panel(g)
	// The board slides up into place.
	rise := max(0, 1 - g.state_time * 3)
	panel.y += rise * rise * 30
	draw_panel(g, panel)

	title: cstring = won ? fmt.ctprintf("%s FALLS", boss_title(g.boss_kind)) : LORE_DEAD_TITLE
	line: cstring = won ? LORE_WIN_LINE : LORE_DEAD_LINE
	colour := won ? GOLD : rl.Color{255, 112, 102, 255}
	light := won ? GOLD_LIGHT : rl.Color{255, 178, 168, 255}
	tw := text_width(a, title, 16)
	draw_text_outlined(a, title, {panel.x + (panel.width - tw) / 2, panel.y + 10}, 16, colour, light)
	centred_in(a, panel, line, panel.y + 32, 8, CREAM)

	inlay := rl.Rectangle{panel.x + 12, panel.y + 48, panel.width - 24, 82}
	draw_inlay(g, inlay)
	draw_run_summary(g, inlay)

	if g.state_time >= MENU_DELAY || rise == 0 {
		draw_menu(g)
	}
}

// Three numbers big, with their names small under them, then the best so far.
@(private = "file")
draw_run_summary :: proc(g: ^Game, r: rl.Rectangle) {
	a := &g.assets
	stats := [3]struct {
		value: int,
		name:  cstring,
	}{{rooms_seen(&g.world), "ROOMS"}, {g.player.kills, "KILLS"}, {g.player.coins, "COINS"}}
	col_w := r.width / 4
	for s, i in stats {
		cx := r.x + col_w * (f32(i) + 0.5)
		v := fmt.ctprintf("%v", s.value)
		draw_text(a, v, {cx - text_width(a, v, 16) / 2, r.y + 8}, 16, INK)
		draw_text(a, s.name, {cx - text_width(a, s.name, 8) / 2, r.y + 26}, 8, {140, 104, 70, 255})
	}
	{
		cx := r.x + col_w * 3.5
		v := fmt.ctprintf("%s", format_time(g.run_time))
		draw_text(a, v, {cx - text_width(a, v, 16) / 2, r.y + 8}, 16, INK)
		draw_text(a, "TIME", {cx - text_width(a, "TIME", 8) / 2, r.y + 26}, 8, {140, 104, 70, 255})
	}
	fill_rect(r.x + 10, r.y + 44, r.width - 20, 1, {180, 150, 110, 255})
	centred_in(
		a,
		r,
		fmt.ctprintf("BEST  %v ROOMS  -  %v KILLS  -  RUN %v", g.best_rooms, g.best_kills, g.runs),
		r.y + 54,
		8,
		{140, 104, 70, 255},
	)
}
