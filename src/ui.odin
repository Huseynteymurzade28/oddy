package game

import "core:math"
import rl "../libs/raylib"

/*
Buttons and boards for the menus. The art is Kenney's Pixel UI pack: 48px
squares, nine-sliced, drawn at one source pixel per virtual pixel so they sit
at the same pixel size as the rest of the game.

The menus are laid out by one function, `menu_items`, which both the update
and the draw call, so what you press is always exactly what is drawn. A
button fires when it is released over, the way phone buttons do, so a thumb
that lands on the wrong one can slide off it. On a keyboard, up and down move
a marker and Enter or Space press the marked one.
*/

Menu_Action :: enum {
	None,
	Play,
	How_To,
	Back,
	Resume,
	Restart,
	Next,
	Menu,
	Quit,
}

Menu_Item :: struct {
	label:  cstring,
	colour: Ui_Colour,
	action: Menu_Action,
	rect:   rl.Rectangle,
}

Ui_State :: struct {
	focus:  int, // the keyboard's marker
	press:  int, // the button the pointer went down on, or -1
	how_to: bool, // the title is showing the how-to-play board
}

BUTTON_W :: 140.0
BUTTON_H :: 26.0
BUTTON_GAP :: 6.0
@(private = "file")
SLICE :: 6 // source pixels of border on each side of the 48px art

// Where the board behind the buttons goes, for the current screen.
menu_panel :: proc(g: ^Game) -> rl.Rectangle {
	view := view_size()
	switch g.state {
	case .Title:
		if g.ui.how_to {
			w := min(f32(380), view.x - 16)
			return {(view.x - w) / 2, 26, w, 196}
		}
		return {(view.x - BUTTON_W - 24) / 2, 98, BUTTON_W + 24, 3 * BUTTON_H + 2 * BUTTON_GAP + 22}
	case .Paused:
		return {(view.x - BUTTON_W - 40) / 2, 46, BUTTON_W + 40, 156}
	case .Cleared:
		w := min(f32(360), view.x - 16)
		return {(view.x - w) / 2, 36, w, 168}
	case .Playing:
	}
	return {}
}

menu_items :: proc(g: ^Game) -> []Menu_Item {
	items := make([dynamic]Menu_Item, context.temp_allocator)
	panel := menu_panel(g)
	column :: proc(items: ^[dynamic]Menu_Item, panel: rl.Rectangle, top: f32, list: []Menu_Item) {
		for item, i in list {
			it := item
			it.rect = {panel.x + (panel.width - BUTTON_W) / 2, top + f32(i) * (BUTTON_H + BUTTON_GAP), BUTTON_W, BUTTON_H}
			append(items, it)
		}
	}
	switch g.state {
	case .Title:
		if g.ui.how_to {
			column(&items, panel, panel.y + panel.height - BUTTON_H - 10, {{label = "BACK", colour = .Yellow, action = .Back}})
		} else {
			column(
				&items,
				panel,
				panel.y + 11,
				{
					{label = "PLAY", colour = .Green, action = .Play},
					{label = "HELP", colour = .Blue, action = .How_To},
					{label = "QUIT", colour = .Red, action = .Quit},
				},
			)
		}
	case .Paused:
		column(
			&items,
			panel,
			panel.y + 52,
			{
				{label = "RESUME", colour = .Green, action = .Resume},
				{label = "RESTART", colour = .Yellow, action = .Restart},
				{label = "MENU", colour = .Blue, action = .Menu},
			},
		)
	case .Cleared:
		// Side by side along the bottom of the board, the next level first.
		row := make([dynamic]Menu_Item, context.temp_allocator)
		if level_has_next(g) {
			append(&row, Menu_Item{label = "NEXT", colour = .Green, action = .Next})
		}
		append(&row, Menu_Item{label = "AGAIN", colour = level_has_next(g) ? .Yellow : .Green, action = .Restart})
		append(&row, Menu_Item{label = "MENU", colour = .Blue, action = .Menu})
		gap: f32 = 8
		n := f32(len(row))
		w: f32 = min(BUTTON_W, (panel.width - 24 - gap * (n - 1)) / n)
		y := panel.y + panel.height - BUTTON_H - 12
		x := panel.x + (panel.width - (w * n + gap * (n - 1))) / 2
		for item, i in row {
			it := item
			it.rect = {x + f32(i) * (w + gap), y, w, BUTTON_H}
			append(&items, it)
		}
	case .Playing:
	}
	return items[:]
}

@(private = "file")
pointer :: proc() -> rl.Vector2 {
	return rl.GetMousePosition() / hud_scale()
}

@(private = "file")
item_under :: proc(items: []Menu_Item, p: rl.Vector2) -> int {
	for item, i in items {
		if rl.CheckCollisionPointRec(p, item.rect) {
			return i
		}
	}
	return -1
}

// Menus wait a moment before taking a press, so the jump that finished a
// level cannot also skip past the card that says so.
MENU_DELAY :: 0.5

menu_update :: proc(g: ^Game) {
	items := menu_items(g)
	ui := &g.ui
	if len(items) == 0 {
		return
	}
	ui.focus = clamp(ui.focus, 0, len(items) - 1)
	if g.state_time < MENU_DELAY {
		ui.press = -1
		return
	}

	// Back, or Escape: close the board, go on playing, or leave.
	if g.input.pause {
		switch {
		case g.state == .Title && ui.how_to:
			activate(g, .Back)
		case g.state == .Paused:
			activate(g, .Resume)
		case g.state == .Title && TOUCH_CONTROLS:
			activate(g, .Quit)
		}
		return
	}

	if g.input.nav != 0 {
		ui.focus = (ui.focus + g.input.nav + len(items)) % len(items)
		play(&g.assets, .Menu_Move)
	}

	p := pointer()
	if rl.IsMouseButtonPressed(.LEFT) {
		ui.press = item_under(items, p)
	}
	when !TOUCH_CONTROLS {
		// A mouse that moves over a button marks it, so the marker and the
		// pointer never disagree about which one Enter would press.
		if rl.Vector2LengthSqr(rl.GetMouseDelta()) > 0 {
			if i := item_under(items, p); i >= 0 {
				ui.focus = i
			}
		}
	}
	if rl.IsMouseButtonReleased(.LEFT) && ui.press >= 0 {
		pressed := ui.press
		ui.press = -1
		if item_under(items, p) == pressed {
			activate(g, items[pressed].action)
			return
		}
	}
	if g.input.confirm {
		activate(g, items[ui.focus].action)
	}
}

@(private = "file")
activate :: proc(g: ^Game, action: Menu_Action) {
	play(&g.assets, .Menu_Select)
	switch action {
	case .None:
	case .Play:
		level_enter(g, 0)
		game_set_state(g, .Playing)
	case .Resume:
		game_set_state(g, .Playing)
	case .How_To:
		g.ui.how_to = true
		g.ui.focus = 0
	case .Back:
		g.ui.how_to = false
		g.ui.focus = 1
	case .Restart:
		level_restart(g)
		game_set_state(g, .Playing)
	case .Next:
		level_enter(g, g.level.index + 1)
		game_set_state(g, .Playing)
	case .Menu:
		level_enter(g, 0)
		game_set_state(g, .Title)
	case .Quit:
		g.quit = true
	}
}

// ------------------------------------------------------------------ drawing ---

// Draws a 48px nine-slice texture over a rectangle in virtual pixels.
draw_nine :: proc(tex: rl.Texture2D, r: rl.Rectangle, tint := rl.WHITE) {
	s := hud_scale()
	src_w, src_h := f32(tex.width), f32(tex.height)
	b: f32 = SLICE
	sx := [4]f32{0, b, src_w - b, src_w}
	sy := [4]f32{0, b, src_h - b, src_h}
	// Edges are rounded in screen pixels so neighbouring pieces never leave a
	// hairline gap between them.
	dx := [4]f32{r.x, r.x + b, r.x + r.width - b, r.x + r.width}
	dy := [4]f32{r.y, r.y + b, r.y + r.height - b, r.y + r.height}
	for i in 0 ..< 4 {
		dx[i] = math.round(dx[i] * s)
		dy[i] = math.round(dy[i] * s)
	}
	for row in 0 ..< 3 {
		for col in 0 ..< 3 {
			src := rl.Rectangle{sx[col], sy[row], sx[col + 1] - sx[col], sy[row + 1] - sy[row]}
			dst := rl.Rectangle{dx[col], dy[row], dx[col + 1] - dx[col], dy[row + 1] - dy[row]}
			rl.DrawTexturePro(tex, src, dst, {}, 0, tint)
		}
	}
}

// A wooden board with a soft shadow under it.
draw_panel :: proc(g: ^Game, r: rl.Rectangle) {
	fill_rect(r.x + 3, r.y + 4, r.width, r.height, {8, 6, 14, 90})
	draw_nine(g.assets.ui.panel, r)
}

draw_inlay :: proc(g: ^Game, r: rl.Rectangle) {
	draw_nine(g.assets.ui.inlay, r)
}

draw_menu :: proc(g: ^Game) {
	a := &g.assets
	items := menu_items(g)
	p := pointer()
	down := rl.IsMouseButtonDown(.LEFT)
	ready := g.state_time >= MENU_DELAY
	for item, i in items {
		pressed := ready && down && g.ui.press == i && rl.CheckCollisionPointRec(p, item.rect)
		r := item.rect
		// The pressed art has no lip under it, so it is drawn two pixels
		// lower: the button sinks into the board.
		tex := a.ui.button[item.colour][pressed ? 1 : 0]
		if pressed {
			r.y += 2
			r.height -= 2
		}
		tint := ready ? rl.WHITE : rl.Color{255, 255, 255, 140}
		draw_nine(tex, r, tint)

		size: f32 = 16
		if text_width(a, item.label, size) > r.width - 12 {
			size = 8
		}
		tw := text_width(a, item.label, size)
		ty := r.y + (r.height - 2 - size) / 2
		draw_text(a, item.label, {r.x + (r.width - tw) / 2, ty + 1}, size, {20, 16, 30, 110})
		draw_text(a, item.label, {r.x + (r.width - tw) / 2, ty}, size, rl.WHITE)

		// The keyboard's marker: a pair of arrows either side, bobbing.
		when !TOUCH_CONTROLS {
			if i == g.ui.focus && ready {
				bob := math.sin(g.time * 6) * 1.5
				cy := r.y + r.height / 2
				s := hud_scale()
				l := rl.Vector2{r.x - 6 + bob, cy}
				rr := rl.Vector2{r.x + r.width + 6 - bob, cy}
				gold := rl.Color{255, 220, 120, 255}
				tri(l * s, (l + {-5, -4}) * s, (l + {-5, 4}) * s, gold)
				tri(rr * s, (rr + {5, -4}) * s, (rr + {5, 4}) * s, gold)
			}
		}
	}
}

// Big text with a dark outline and a drop shadow, for titles over the world.
draw_text_outlined :: proc(a: ^Assets, text: cstring, pos: rl.Vector2, size: f32, colour: rl.Color, top: rl.Color = {}) {
	o: f32 = size >= 24 ? 2 : 1
	ink := rl.Color{24, 16, 34, colour.a}
	draw_text(a, text, pos + {0, o * 2}, size, {10, 6, 16, colour.a / 2})
	for d in ([8]rl.Vector2{{-1, 0}, {1, 0}, {0, -1}, {0, 1}, {-1, -1}, {1, -1}, {-1, 1}, {1, 1}}) {
		draw_text(a, text, pos + d * o, size, ink)
	}
	draw_text(a, text, pos, size, colour)
	if top.a > 0 {
		// The top half in a lighter shade: a cheap bevel that makes big pixel
		// letters look carved rather than printed.
		s := hud_scale()
		rl.BeginScissorMode(0, i32(pos.y * s), rl.GetScreenWidth(), i32(size * 0.45 * s))
		draw_text(a, text, pos, size, top)
		rl.EndScissorMode()
	}
}

draw_text_outlined_centered :: proc(a: ^Assets, text: cstring, y, size: f32, colour: rl.Color, top: rl.Color = {}) {
	view := view_size()
	draw_text_outlined(a, text, {(view.x - text_width(a, text, size)) / 2, y}, size, colour, top)
}

// The touch screen's pause button: a small grey square in the top-right corner.
pause_button_rect :: proc() -> rl.Rectangle {
	view := view_size()
	return {view.x - 27, 5, 22, 22}
}

draw_pause_button :: proc(g: ^Game) {
	r := pause_button_rect()
	draw_nine(g.assets.ui.button[.Grey][0], r, {255, 255, 255, 210})
	ink := rl.Color{80, 84, 100, 255}
	fill_rect(r.x + 7, r.y + 6, 3, 9, ink)
	fill_rect(r.x + 12, r.y + 6, 3, 9, ink)
}
