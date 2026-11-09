package game

import "core:fmt"
import "core:math"
import rl "../libs/raylib"

/*
The overlay drawn on top of the world. Everything here is laid out in the same
virtual 240px-tall space as the world and scaled up to the window, so text stays
pixel-crisp at any size.

It is kept to the top edge on purpose: on a phone both bottom corners belong to
thumbs. Top left is the clock and the death count; the level's name shows in
the middle for a moment when it starts.

The full-screen cards live in `hud_screens.odin`, and the on-screen buttons in
`hud_touch.odin`.
*/

// ------------------------------------------------------------------ helpers ---

hud_scale :: proc() -> f32 {
	return f32(rl.GetScreenHeight()) / PIXEL_HEIGHT
}

draw_text :: proc(a: ^Assets, text: cstring, pos: rl.Vector2, size: f32, color: rl.Color) {
	s := hud_scale()
	rl.DrawTextEx(a.font, text, pos * s, size * s, s, color)
}

// The same text with a one-pixel drop shadow, for anything that floats over the
// world without a panel behind it.
draw_text_shadow :: proc(a: ^Assets, text: cstring, pos: rl.Vector2, size: f32, color: rl.Color) {
	shadow := rl.Color{8, 6, 14, color.a / 4 * 3}
	draw_text(a, text, pos + {0, 1}, size, shadow)
	draw_text(a, text, pos, size, color)
}

text_width :: proc(a: ^Assets, text: cstring, size: f32) -> f32 {
	s := hud_scale()
	return rl.MeasureTextEx(a.font, text, size * s, s).x / s
}

draw_text_centered :: proc(a: ^Assets, text: cstring, y, size: f32, color: rl.Color) {
	view := view_size()
	draw_text_shadow(a, text, {(view.x - text_width(a, text, size)) / 2, y}, size, color)
}

draw_text_right :: proc(a: ^Assets, text: cstring, right, y, size: f32, color: rl.Color) {
	draw_text_shadow(a, text, {right - text_width(a, text, size), y}, size, color)
}

fill_rect :: proc(x, y, w, h: f32, color: rl.Color) {
	s := hud_scale()
	rl.DrawRectangleV({x * s, y * s}, {w * s, h * s}, color)
}

// A one-pixel frame drawn just outside the given rectangle.
outline_rect :: proc(x, y, w, h: f32, color: rl.Color) {
	fill_rect(x - 1, y - 1, w + 2, 1, color)
	fill_rect(x - 1, y + h, w + 2, 1, color)
	fill_rect(x - 1, y, 1, h, color)
	fill_rect(x + w, y, 1, h, color)
}

fill_circle :: proc(c: rl.Vector2, r: f32, color: rl.Color) {
	s := hud_scale()
	rl.DrawCircleV(c * s, r * s, color)
}

ring :: proc(c: rl.Vector2, r, thickness: f32, color: rl.Color) {
	s := hud_scale()
	rl.DrawRing(c * s, (r - thickness) * s, r * s, 0, 360, 40, color)
}

draw_dim :: proc(alpha: u8) {
	rl.DrawRectangle(0, 0, rl.GetScreenWidth(), rl.GetScreenHeight(), {12, 10, 20, alpha})
}

// Minutes, seconds and hundredths: a precision platformer is timed to the
// hundredth.
format_time :: proc(seconds: f32) -> string {
	total := int(seconds * 100)
	return fmt.tprintf("%d:%02d.%02d", total / 6000, (total / 100) % 60, total % 100)
}

// A small skull, drawn rather than loaded, beside the death count.
draw_skull :: proc(x, y: f32, color: rl.Color) {
	s := hud_scale()
	rl.DrawCircleV({(x + 3.5) * s, (y + 3) * s}, 3.4 * s, color)
	fill_rect(x + 1.5, y + 4, 4, 3, color)
	eye := rl.Color{20, 16, 30, color.a}
	fill_rect(x + 1.5, y + 2.5, 1.5, 1.5, eye)
	fill_rect(x + 4, y + 2.5, 1.5, 1.5, eye)
	fill_rect(x + 3, y + 6, 1, 1, eye)
}

// ------------------------------------------------------------------ the HUD ---

hud_draw :: proc(g: ^Game) {
	switch g.state {
	case .Title:
		draw_title_screen(g)
	case .Map:
		world_map_draw(g)
	case .Playing:
		draw_iris(g)
		draw_stats(g)
		draw_level_name(g)
		when TOUCH_CONTROLS {
			draw_touch_controls(g)
			draw_pause_button(g)
		}
	case .Paused:
		draw_iris(g)
		draw_stats(g)
		draw_pause_screen(g)
	case .Cleared:
		draw_end_screen(g)
	}
}

// A closing circle when you die and an opening one when you come back (and
// when a level starts), centred on you: the cut back to the checkpoint is
// never a jump in the dark.
@(private = "file")
draw_iris :: proc(g: ^Game) {
	p := g.player
	open: f32 = 1
	switch {
	case p.dead:
		open = clamp((p.death_timer - 0.04) / (DEATH_TIME * 0.5), 0, 1)
	case p.respawn_time > 0:
		open = 1 - p.respawn_time / RESPAWN_TIME
	}
	if open >= 1 {
		return
	}
	open = open * open * (3 - 2 * open)
	sw, sh := f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())
	centre := rl.GetWorldToScreen2D(player_centre(p), g.camera)
	far := math.sqrt(sw * sw + sh * sh) * 1.2
	ink := rl.Color{14, 10, 22, 255}
	if open <= 0 {
		rl.DrawRectangle(0, 0, i32(sw), i32(sh), ink)
		return
	}
	rl.DrawRing(centre, far * open, far * 2, 0, 360, 72, ink)
}

// The clock, and how many times this level has killed you.
@(private = "file")
draw_stats :: proc(g: ^Game) {
	a := &g.assets
	draw_text_shadow(a, fmt.ctprintf("%s", format_time(g.level_time)), {6, 5}, 8, rl.RAYWHITE)
	draw_skull(6, 17, {8, 6, 14, 150})
	draw_skull(6, 16, {236, 228, 240, 255})
	draw_text_shadow(a, fmt.ctprintf("%v", g.deaths), {16, 15}, 8, rl.RAYWHITE)
}

@(private = "file")
draw_level_name :: proc(g: ^Game) {
	if g.level_intro <= 0 {
		return
	}
	t := g.level_intro
	alpha := u8(clamp(min(t, LEVEL_INTRO_TIME - t) * 3, 0, 1) * 255)
	draw_text_outlined_centered(&g.assets, g.level.name, 18, 16, {255, 214, 110, alpha})
}
