package game

import "core:fmt"
import rl "vendor:raylib"

/*
The full-screen cards: the title, and the two ways a run can end. All three read
their words from `lore.odin` so the story is written in one place.
*/

@(private = "file")
GOLD :: rl.Color{255, 214, 110, 255}
@(private = "file")
DIM :: rl.Color{150, 160, 186, 255}
@(private = "file")
PALE :: rl.Color{206, 216, 234, 255}

// A short rule between sections of a card.
@(private = "file")
draw_rule :: proc(y: f32, colour: rl.Color) {
	view := view_size()
	width := view.x * 0.26
	fill_rect((view.x - width) / 2, y, width, 1, colour)
}

@(private = "file")
draw_lines :: proc(a: ^Assets, lines: []cstring, top, step, size: f32, colour: rl.Color) {
	for line, i in lines {
		draw_text_centered(a, line, top + f32(i) * step, size, colour)
	}
}

draw_title_screen :: proc(g: ^Game) {
	a := &g.assets
	draw_dim(180)

	draw_text_centered(a, GAME_TITLE, 18, 28, GOLD)
	draw_text_centered(a, GAME_TAGLINE, 52, 8, {180, 150, 210, 255})

	draw_lines(a, LORE_INTRO[:], 72, 10, 8, PALE)

	draw_rule(114, {70, 76, 100, 255})
	draw_lines(a, LORE_OBJECTIVES[:], 122, 10, 8, GOLD)

	draw_rule(156, {70, 76, 100, 255})
	draw_lines(a, LORE_CONTROLS[:], 164, 10, 8, DIM)

	if int(g.time * 2) % 2 == 0 {
		draw_text_centered(a, "PRESS SPACE TO GO DOWN", 222, 8, GOLD)
	}
}

draw_end_screen :: proc(g: ^Game) {
	a := &g.assets
	won := g.state == .Won
	draw_dim(won ? 185 : 190)

	title: cstring = won ? LORE_WIN_TITLE : LORE_DEAD_TITLE
	line: cstring = won ? LORE_WIN_LINE : LORE_DEAD_LINE
	draw_text_centered(a, title, 42, 16, won ? GOLD : rl.Color{228, 92, 92, 255})
	draw_text_centered(a, line, 66, 8, won ? rl.Color{150, 240, 160, 255} : DIM)

	draw_rule(82, {70, 76, 100, 255})
	draw_run_summary(g, 92)

	if int(g.time * 2) % 2 == 0 {
		draw_text_centered(a, "PRESS R TO GO BACK DOWN", 158, 8, GOLD)
	}
}

@(private = "file")
draw_run_summary :: proc(g: ^Game, y: f32) {
	a := &g.assets
	white := rl.RAYWHITE
	draw_text_centered(
		a,
		fmt.ctprintf("ROOMS EXPLORED   %v / %v", rooms_seen(&g.world), ROOMS_PER_RUN),
		y,
		8,
		white,
	)
	draw_text_centered(a, fmt.ctprintf("ENEMIES KILLED   %v", g.player.kills), y + 11, 8, white)
	draw_text_centered(
		a,
		fmt.ctprintf("COINS            %v / %v", g.player.coins, g.coins_total),
		y + 22,
		8,
		white,
	)
	draw_text_centered(
		a,
		fmt.ctprintf("TIME             %v", format_time(g.run_time)),
		y + 33,
		8,
		white,
	)
	draw_text_centered(
		a,
		fmt.ctprintf("BEST   %v ROOMS   %v KILLS   RUN %v", g.best_rooms, g.best_kills, g.runs),
		y + 48,
		8,
		DIM,
	)
}
