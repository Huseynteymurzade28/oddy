package game

import "core:fmt"
import "core:math"
import rl "vendor:raylib"

/*
The overlay drawn on top of the world. Everything here is laid out in the same
virtual 240px-tall space as the world and scaled up to the window, so text stays
pixel-crisp at any size.

This file holds the drawing helpers the rest of the HUD shares, plus the part
that is always on screen while playing. The map lives in `hud_minimap.odin` and
the full-screen cards in `hud_screens.odin`.
*/

// ------------------------------------------------------------------ helpers ---

hud_scale :: proc() -> f32 {
	return f32(rl.GetScreenHeight()) / PIXEL_HEIGHT
}

draw_text :: proc(a: ^Assets, text: cstring, pos: rl.Vector2, size: f32, color: rl.Color) {
	s := hud_scale()
	rl.DrawTextEx(a.font, text, pos * s, size * s, s, color)
}

text_width :: proc(a: ^Assets, text: cstring, size: f32) -> f32 {
	s := hud_scale()
	return rl.MeasureTextEx(a.font, text, size * s, s).x / s
}

draw_text_centered :: proc(a: ^Assets, text: cstring, y, size: f32, color: rl.Color) {
	view := view_size()
	draw_text(a, text, {(view.x - text_width(a, text, size)) / 2, y}, size, color)
}

// Right-aligned to `right`, used by everything hanging off the map panel.
draw_text_right :: proc(a: ^Assets, text: cstring, right, y, size: f32, color: rl.Color) {
	draw_text(a, text, {right - text_width(a, text, size), y}, size, color)
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

draw_dim :: proc(alpha: u8) {
	rl.DrawRectangle(0, 0, rl.GetScreenWidth(), rl.GetScreenHeight(), {12, 10, 20, alpha})
}

format_time :: proc(seconds: f32) -> string {
	total := int(seconds)
	return fmt.tprintf("%02d:%02d", total / 60, total % 60)
}

// A 7px heart, drawn rather than loaded: the sprite pack has no health icon.
@(private = "file")
draw_heart :: proc(x, y: f32, color: rl.Color) {
	s := hud_scale()
	p :: proc(x, y, s: f32) -> rl.Vector2 {return {x * s, y * s}}
	rl.DrawCircleV(p(x + 2, y + 2.2, s), 2.3 * s, color)
	rl.DrawCircleV(p(x + 5, y + 2.2, s), 2.3 * s, color)
	rl.DrawTriangle(p(x - 0.3, y + 2.6, s), p(x + 3.5, y + 7.6, s), p(x + 7.3, y + 2.6, s), color)
}

// ------------------------------------------------------------------ the HUD ---

hud_draw :: proc(g: ^Game) {
	switch g.state {
	case .Title:
		draw_title_screen(g)
	case .Playing:
		draw_stats(g)
		draw_minimap(g)
		draw_prompts(g)
		draw_crosshair(g)
	case .Dead, .Won:
		draw_stats(g)
		draw_minimap(g)
		draw_end_screen(g)
	}
}

@(private = "file")
draw_stats :: proc(g: ^Game) {
	a := &g.assets
	s := hud_scale()

	for i in 0 ..< MAX_HEALTH {
		colour := rl.Color{228, 78, 92, 255}
		if i >= g.player.health {
			colour = {44, 38, 54, 220}
		}
		draw_heart(5 + f32(i) * 10, 5, colour)
	}

	// Coin counter, using the animated coin sprite as its icon.
	coin_frame := int(g.time / max(a.coin.frame_time, 0.01)) % max(a.coin.count, 1)
	anim_draw_frame(&a.coin, coin_frame, {8 * s, 24 * s}, false, rl.WHITE, s)
	draw_text(a, fmt.ctprintf("%v", g.player.coins), {15, 17}, 8, rl.RAYWHITE)

	if g.player.has_key {
		key_frame := int(g.time / max(a.key.frame_time, 0.01)) % max(a.key.count, 1)
		anim_draw_frame(&a.key, key_frame, {40 * s, 24 * s}, false, rl.WHITE, s)
	}

	draw_weapon_panel(g)
}

@(private = "file")
draw_weapon_panel :: proc(g: ^Game) {
	a := &g.assets
	w := g.player.weapon
	view := view_size()
	s := hud_scale()

	name := fmt.ctprintf("%s %s", w.prefix, weapon_class_name(w.class))
	panel_w := max(f32(120), text_width(a, name, 8) + 44)
	x: f32 = 5
	y := view.y - 32

	fill_rect(x, y, panel_w, 27, {14, 12, 22, 180})
	fill_rect(x, y, panel_w, 1, RARITY_COLORS[w.rarity])

	weapon_draw_flat(w, a, {(x + 18) * s, (y + 10) * s}, 0.62 * s)
	draw_text(a, name, {x + 34, y + 4}, 8, RARITY_COLORS[w.rarity])

	if w.infinite {
		draw_text(a, "UNLIMITED", {x + 34, y + 16}, 8, {150, 160, 186, 255})
	} else {
		draw_text(a, fmt.ctprintf("%v / %v", w.ammo, w.ammo_max), {x + 34, y + 16}, 8, rl.RAYWHITE)
		// Ammo bar along the bottom edge of the panel.
		frac := f32(w.ammo) / f32(max(w.ammo_max, 1))
		fill_rect(x, y + 26, panel_w, 1, {40, 36, 52, 255})
		bar := rl.Color{236, 214, 130, 255}
		if frac < 0.25 {
			bar = {228, 92, 92, 255}
		}
		fill_rect(x, y + 26, panel_w * frac, 1, bar)
	}
}

// The floating message line, plus the panel that appears next to a chest.
@(private = "file")
draw_prompts :: proc(g: ^Game) {
	a := &g.assets
	view := view_size()

	if g.notice_timer > 0 && len(g.notice) > 0 {
		alpha := u8(clamp(g.notice_timer, 0, 1) * 255)
		draw_text_centered(a, fmt.ctprintf("%s", g.notice), 40, 8, {255, 214, 110, alpha})
	}

	for c in g.chests {
		if c.taken || !chest_in_reach(c, g.player) {
			continue
		}
		if !c.opened {
			draw_text_centered(a, "E   OPEN CHEST", view.y - 48, 8, {255, 214, 110, 255})
			return
		}

		// Comparing against what you are holding is the whole decision, so the
		// numbers sit side by side rather than being left to memory.
		name := fmt.ctprintf("%s %s", c.loot.prefix, weapon_class_name(c.loot.class))
		here := weapon_dps(c.loot)
		mine := weapon_dps(g.player.weapon)
		arrow: cstring = here > mine ? "BETTER DPS" : (here < mine ? "WORSE DPS" : "SAME DPS")
		colour := here > mine ? rl.Color{124, 224, 140, 255} : rl.Color{228, 130, 130, 255}

		y := view.y - 72
		draw_text_centered(a, name, y, 8, RARITY_COLORS[c.loot.rarity])
		draw_text_centered(
			a,
			fmt.ctprintf("%s   DPS %.0f  VS  %.0f", arrow, here, mine),
			y + 11,
			8,
			colour,
		)
		draw_text_centered(
			a,
			fmt.ctprintf(
				"%s   %v ROUNDS",
				RARITY_NAMES[c.loot.rarity],
				c.loot.infinite ? 0 : c.loot.ammo,
			),
			y + 22,
			8,
			{176, 190, 214, 255},
		)
		draw_text_centered(a, "E   TAKE IT", y + 36, 8, {255, 214, 110, 255})
		return
	}
}

@(private = "file")
draw_crosshair :: proc(g: ^Game) {
	m := rl.GetMousePosition()
	s := hud_scale()
	ready := g.player.fire_cd <= 0
	colour := ready ? g.player.weapon.tint : rl.Color{140, 140, 150, 200}

	pulse := 3.5 + math.sin(g.time * 8) * 0.4
	rl.DrawCircleLinesV(m, pulse * s, colour)
	rl.DrawLineV({m.x - 6 * s, m.y}, {m.x - 2.5 * s, m.y}, colour)
	rl.DrawLineV({m.x + 2.5 * s, m.y}, {m.x + 6 * s, m.y}, colour)
	rl.DrawLineV({m.x, m.y - 6 * s}, {m.x, m.y - 2.5 * s}, colour)
	rl.DrawLineV({m.x, m.y + 2.5 * s}, {m.x, m.y + 6 * s}, colour)
}
