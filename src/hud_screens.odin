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

// The title stands in the meadow: the sky and hills behind, a strip of
// grassy ground along the bottom, and your hero trotting on the spot.
@(private = "file")
draw_title_scene :: proc(g: ^Game) {
	a := &g.assets
	view := view_size()
	s := hud_scale()
	draw_backdrop(g, .Mossy, {g.time * 14, 120}, 240)
	tex := a.terrain[.Mossy]
	ground_y: f32 = view.y - 26
	scroll := math.mod(g.time * 30, TILE)
	for i in -1 ..< int(view.x / TILE) + 2 {
		x := f32(i) * TILE - scroll
		hash := (i + int(g.time * 30 / TILE)) * 7919
		cells := [3]rl.Rectangle {
			terrain_source(2 | 8, abs(hash) % 6), // the grassy top
			terrain_source(1 | 2 | 8 | 4, abs(hash / 3) % 6),
			terrain_source(4 + abs(hash) % 4, 6), // its fringe, above
		}
		rl.DrawTexturePro(tex, cells[0], {x * s, ground_y * s, TILE * s, TILE * s}, {}, 0, rl.WHITE)
		rl.DrawTexturePro(tex, cells[1], {x * s, (ground_y + TILE) * s, TILE * s, TILE * s}, {}, 0, {235, 235, 235, 255})
		rl.DrawTexturePro(tex, cells[2], {x * s, (ground_y - TILE) * s, TILE * s, TILE * s}, {}, 0, rl.WHITE)
		if abs(hash) % 100 < 30 {
			rl.DrawTexturePro(tex, terrain_source(8 + abs(hash / 7) % 8, 6), {x * s, (ground_y - TILE) * s, TILE * s, TILE * s}, {}, 0, rl.WHITE)
		}
	}
	// The hero runs along with the scrolling ground.
	anim := &a.player.run
	frame := int(g.time / anim.frame_time) % anim.count
	bob := math.abs(math.sin(g.time * 9)) * 1.2
	anim_draw_frame(anim, frame, {view.x * 0.18 * s, (ground_y - bob) * s}, false, rl.WHITE, s)
	rl.DrawRectangleGradientV(0, 0, rl.GetScreenWidth(), i32(110 * s), {20, 14, 40, 90}, {20, 14, 40, 0})
}

draw_title_screen :: proc(g: ^Game) {
	a := &g.assets
	view := view_size()
	draw_title_scene(g)

	if g.ui.how_to {
		draw_how_to(g)
		draw_menu(g)
		return
	}

	// The name drops in, overshoots a little, settles, and then bobs gently.
	t := min(g.state_time * 2.2, 1)
	drop := (1 - t) * (1 - t) * -40 + math.sin(t * math.PI) * 3
	bob := math.sin(g.time * 1.8) * 1.5
	draw_text_outlined_centered(a, GAME_TITLE, 12 + drop + bob, 48, GOLD, GOLD_LIGHT)
	draw_text_outlined_centered(a, GAME_TITLE_TAIL, 62 + drop * 0.5, 16, {255, 236, 200, 255}, {255, 250, 230, 255})
	draw_text_outlined_centered(a, GAME_TAGLINE, 82, 8, {240, 226, 255, 255})

	draw_panel(g, menu_panel(g))
	draw_menu(g)

	_ = view
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
	draw_shade(40, 150)
	panel := menu_panel(g)
	// The board slides up into place.
	rise := max(0, 1 - g.state_time * 3)
	panel.y += rise * rise * 30
	draw_panel(g, panel)

	d := &g.levels[g.level.index]
	finale := d.world == WORLDS && d.number == LEVELS_PER_WORLD && !d.secret
	title: cstring = g.clear.secret ? LORE_SECRET_TITLE : (finale ? LORE_END_TITLE : LORE_CLEAR_TITLE)
	colour := g.clear.secret ? rl.Color{214, 160, 255, 255} : GOLD
	light := g.clear.secret ? rl.Color{240, 214, 255, 255} : GOLD_LIGHT
	tw := text_width(a, title, 16)
	draw_text_outlined(a, title, {panel.x + (panel.width - tw) / 2, panel.y + 10}, 16, colour, light)
	centred_in(a, panel, finale ? LORE_END_LINE : g.level.name, panel.y + 32, 8, CREAM)

	inlay := rl.Rectangle{panel.x + 12, panel.y + 46, panel.width - 24, 88}
	draw_inlay(g, inlay)
	draw_clear_summary(g, inlay)

	if g.state_time >= MENU_DELAY || rise == 0 {
		draw_menu(g)
	}
	// The confetti falls in front of the card, not behind it.
	rl.BeginMode2D(g.camera)
	confetti_draw(g)
	rl.EndMode2D()
}

// The time and the deaths big, the fruit beside them, and then the three
// medals: lit if earned, with the ones earned just now marked NEW.
@(private = "file")
draw_clear_summary :: proc(g: ^Game, r: rl.Rectangle) {
	a := &g.assets
	c := g.clear
	col_w := r.width / 4
	columns := [4]struct {
		value: cstring,
		name:  cstring,
	} {
		{fmt.ctprintf("%s", format_time(g.level_time)), "TIME"},
		{fmt.ctprintf("%v", g.deaths), "DEATHS"},
		{fmt.ctprintf("%v/%v", c.fruit, c.fruit_of), "FRUIT"},
		{fmt.ctprintf("%v/%v", c.gems, c.gems_of), "GEMS"},
	}
	for col, i in columns {
		cx := r.x + col_w * (f32(i) + 0.5)
		size: f32 = text_width(a, col.value, 16) > col_w - 4 ? 8 : 16
		draw_text(a, col.value, {cx - text_width(a, col.value, size) / 2, r.y + 6 + (16 - size) / 2}, size, INK)
		draw_text(a, col.name, {cx - text_width(a, col.name, 8) / 2, r.y + 24}, 8, {140, 104, 70, 255})
	}
	fill_rect(r.x + 10, r.y + 37, r.width - 20, 1, {180, 150, 110, 255})

	for medal, i in Medal {
		cx := r.x + r.width / 3 * (f32(i) + 0.5)
		pos := rl.Vector2{cx, r.y + 52}
		earned := medal in c.medals
		fresh := medal in c.new_medals
		k: f32 = fresh ? 1 + 0.15 * math.sin(g.state_time * 10) : 1
		fill_circle(pos + {0, 1}, 7 * k, {90, 60, 36, 120})
		if earned {
			fill_circle(pos, 7 * k, MEDAL_COLOURS[medal])
			ring(pos, 7 * k, 1.2, {255, 255, 255, 200})
		} else {
			ring(pos, 7, 1.2, {170, 140, 110, 255})
		}
		name := MEDAL_NAMES[medal]
		draw_text(a, name, {cx - text_width(a, name, 8) / 2, r.y + 62}, 8, earned ? INK : rl.Color{170, 140, 110, 255})
		if fresh {
			draw_text(a, "NEW", {cx + 9, r.y + 44}, 8, {200, 80, 60, 255})
		}
	}
	if c.new_skin {
		centred_in(a, r, "A NEW HERO WAITS ON THE MAP", r.y + 75, 8, {120, 70, 160, 255})
	} else if c.secret {
		centred_in(a, r, "A HIDDEN LEVEL OPENS ON THE MAP", r.y + 75, 8, {120, 70, 160, 255})
	} else if level := g.levels[g.level.index]; level.par > 0 && .Time not_in c.medals {
		centred_in(a, r, fmt.ctprintf("PAR TIME %s", format_time(level.par)), r.y + 75, 8, {140, 104, 70, 255})
	}
}
