package game

import "core:fmt"
import "core:math"
import rl "../libs/raylib"

/*
The full-screen cards: the title, the pause card, and the card at the end of
a level. Each is a wooden board over the dimmed world with its buttons on it (the
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

	draw_text_outlined_centered(a, fmt.ctprintf("%v LEVELS", len(g.levels)), view.y - 16, 8, DIM)
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
	centred_in(a, inlay, g.level.name, inlay.y + 4, 8, INK)
	draw_menu(g)
}

draw_end_screen :: proc(g: ^Game) {
	a := &g.assets
	draw_shade(100, 210)
	panel := menu_panel(g)
	// The board slides up into place.
	rise := max(0, 1 - g.state_time * 3)
	panel.y += rise * rise * 30
	draw_panel(g, panel)

	title: cstring = LORE_CLEAR_TITLE
	tw := text_width(a, title, 16)
	draw_text_outlined(a, title, {panel.x + (panel.width - tw) / 2, panel.y + 10}, 16, GOLD, GOLD_LIGHT)
	centred_in(a, panel, g.level.name, panel.y + 32, 8, CREAM)

	inlay := rl.Rectangle{panel.x + 12, panel.y + 48, panel.width - 24, 70}
	draw_inlay(g, inlay)
	draw_clear_summary(g, inlay)

	if g.state_time >= MENU_DELAY || rise == 0 {
		draw_menu(g)
	}
}

// The time and the deaths big, with their names small under them, then the
// best so far.
@(private = "file")
draw_clear_summary :: proc(g: ^Game, r: rl.Rectangle) {
	a := &g.assets
	best := g.best[g.level.index]
	col_w := r.width / 2
	columns := [2]struct {
		value: cstring,
		name:  cstring,
	}{{fmt.ctprintf("%s", format_time(g.level_time)), "TIME"}, {fmt.ctprintf("%v", g.deaths), "DEATHS"}}
	for c, i in columns {
		cx := r.x + col_w * (f32(i) + 0.5)
		draw_text(a, c.value, {cx - text_width(a, c.value, 16) / 2, r.y + 8}, 16, INK)
		draw_text(a, c.name, {cx - text_width(a, c.name, 8) / 2, r.y + 26}, 8, {140, 104, 70, 255})
	}
	fill_rect(r.x + 10, r.y + 42, r.width - 20, 1, {180, 150, 110, 255})
	centred_in(
		a,
		r,
		fmt.ctprintf("BEST  %s  -  %v DEATHS", format_time(best.time), best.deaths),
		r.y + 50,
		8,
		{140, 104, 70, 255},
	)
}
