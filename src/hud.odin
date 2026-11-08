package game

import "core:fmt"
import "core:math"
import rl "../libs/raylib"

/*
The overlay drawn on top of the world. Everything here is laid out in the same
virtual 240px-tall space as the world and scaled up to the window, so text stays
pixel-crisp at any size.

It is kept to the top edge on purpose: on a phone both bottom corners belong to
thumbs. Top left is you (hearts, coins, the gun); top right is the map. Anything
else — what to do next, the warden's health — only shows while it matters.

The map lives in `hud_minimap.odin`, the full-screen cards in
`hud_screens.odin`, and the on-screen buttons in `hud_touch.odin`.
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

format_time :: proc(seconds: f32) -> string {
	total := int(seconds)
	return fmt.tprintf("%02d:%02d", total / 60, total % 60)
}

// A prompt for something you do with the interact key. On a phone the button
// itself says what it is, so the line drops the key name.
action_label :: proc(text: string) -> cstring {
	when TOUCH_CONTROLS {
		return fmt.ctprintf("%s", text)
	} else {
		return fmt.ctprintf("E   %s", text)
	}
}

// A 7px heart, drawn rather than loaded: the sprite pack has no health icon.
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
		draw_boss_bar(g)
		draw_prompts(g)
		when TOUCH_CONTROLS {
			draw_touch_controls(g)
			draw_pause_button(g)
		} else {
			draw_crosshair(g)
		}
	case .Paused:
		draw_stats(g)
		draw_minimap(g)
		draw_pause_screen(g)
	case .Dead, .Won:
		draw_end_screen(g)
	}
}

// Hearts, then coins and the key, then the gun: one compact block in the corner.
@(private = "file")
draw_stats :: proc(g: ^Game) {
	a := &g.assets
	s := hud_scale()
	p := &g.player

	// A heart that was just lost pops, so a hit is felt even mid-fight.
	for i in 0 ..< p.max_health {
		colour := rl.Color{228, 78, 92, 255}
		if i >= p.health {
			colour = {44, 38, 54, 200}
		}
		if i >= MAX_HEALTH && i < p.health {
			colour = {255, 120, 150, 255}
		}
		x := 6 + f32(i) * 10
		draw_heart(x, 7, {8, 6, 14, 150})
		draw_heart(x, 6, colour)
	}

	y: f32 = 17
	coin_frame := int(g.time / max(a.coin.frame_time, 0.01)) % max(a.coin.count, 1)
	anim_draw_frame(&a.coin, coin_frame, {10 * s, (y + 9) * s}, false, rl.WHITE, s)
	draw_text_shadow(a, fmt.ctprintf("%v", p.coins), {17, y}, 8, rl.RAYWHITE)

	if p.has_key {
		key_frame := int(g.time / max(a.key.frame_time, 0.01)) % max(a.key.count, 1)
		kx := 24 + text_width(a, fmt.ctprintf("%v", p.coins), 8)
		anim_draw_frame(&a.key, key_frame, {kx * s, (y + 8) * s}, false, rl.WHITE, s)
	}

	// The gun: its sprite, and a thin bar for what is left in it. The name is
	// announced once when you pick it up; after that the colour says enough.
	w := p.weapon
	y += 12
	colour := RARITY_COLORS[w.rarity]
	weapon_draw_flat(w, a, {19 * s, (y + 7) * s}, 0.85 * s)
	fill_rect(6, y + 14, 26, 1, colour)
	if !w.infinite {
		frac := f32(w.ammo) / f32(max(w.ammo_max, 1))
		bar := frac < 0.25 ? rl.Color{228, 92, 92, 255} : rl.Color{236, 214, 130, 255}
		fill_rect(6, y + 14, 26 * frac, 1, bar)
		draw_text_shadow(a, fmt.ctprintf("%v", w.ammo), {36, y + 3}, 8, {200, 206, 220, 255})
	}
}

// The warden's name and health across the top, once the vault has shut behind
// you. During the introduction the name is shown big instead.
@(private = "file")
draw_boss_bar :: proc(g: ^Game) {
	a := &g.assets
	b, ok := boss_status(g)
	if !ok {
		return
	}
	view := view_size()

	if g.boss_intro > 0 {
		t := g.boss_intro
		alpha := u8(clamp(min(t, BOSS_INTRO_TIME - t) * 3, 0, 1) * 255)
		gold := rl.Color{255, 214, 110, alpha}
		draw_text_centered(a, b.title, 70, 16, gold)
		draw_text_centered(a, b.epithet, 92, 8, {206, 190, 230, alpha})
		return
	}

	width := min(view.x * 0.5, 200)
	x := (view.x - width) / 2
	y: f32 = 16
	draw_text_centered(a, b.title, 5, 8, {230, 220, 240, 255})
	fill_rect(x - 1, y - 1, width + 2, 5, {8, 6, 14, 200})
	fill_rect(x, y, width * clamp(b.frac_lag, 0, 1), 3, {255, 236, 200, 255})
	fill_rect(x, y, width * clamp(b.frac, 0, 1), 3, b.colour)
	// Where the second phase starts, so the fight has a visible halfway mark.
	if b.phase_mark > 0 {
		fill_rect(x + width * b.phase_mark, y - 1, 1, 5, {8, 6, 14, 255})
	}
}

// The floating message line, plus the panel that appears next to a chest.
@(private = "file")
draw_prompts :: proc(g: ^Game) {
	a := &g.assets
	view := view_size()

	if g.notice_timer > 0 && len(g.notice) > 0 {
		alpha := u8(clamp(g.notice_timer, 0, 1) * 255)
		draw_text_centered(a, fmt.ctprintf("%s", g.notice), 44, 8, {255, 214, 110, alpha})
	}

	// The stall owns the prompt line whenever you are standing at one of its
	// crates, so a chest in the same room can never talk over a purchase.
	if slot := shop_slot_in_reach(g.shop, g.player); slot >= 0 {
		draw_shop_prompt(g, g.shop.items[slot])
		return
	}

	for c in g.chests {
		if c.taken || !chest_in_reach(c, g.player) {
			continue
		}
		if !c.opened {
			draw_text_centered(a, action_label("OPEN"), view.y - 58, 8, {255, 214, 110, 255})
			return
		}
		top := offer_top(g, chest_loot_pos(c) - {0, 10})
		draw_weapon_offer(g, c.loot, top)
		draw_text_centered(a, action_label("TAKE IT"), top + 36, 8, {255, 214, 110, 255})
		return
	}
}

@(private = "file")
OFFER_UP :: 96.0
@(private = "file")
OFFER_H :: 44.0

// Where an offer panel starts: just above the thing on offer, so the words never
// sit on top of the gun or the stall they are describing.
@(private = "file")
offer_top :: proc(g: ^Game, anchor: rl.Vector2) -> f32 {
	view := view_size()
	screen_y := anchor.y - g.camera.target.y + view.y / 2
	return clamp(screen_y - OFFER_H - 6, 46, view.y - OFFER_UP)
}

// Comparing a gun against what you are already holding is the whole decision, so
// the numbers sit side by side rather than being left to memory.
@(private = "file")
draw_weapon_offer :: proc(g: ^Game, w: Weapon, y: f32) {
	a := &g.assets
	here := weapon_dps(w)
	mine := weapon_dps(g.player.weapon)
	arrow: cstring = here > mine ? "BETTER" : (here < mine ? "WORSE" : "SAME")
	colour := here > mine ? rl.Color{124, 224, 140, 255} : rl.Color{228, 130, 130, 255}

	draw_text_centered(
		a,
		fmt.ctprintf("%s %s", w.prefix, weapon_class_name(w.class)),
		y,
		8,
		RARITY_COLORS[w.rarity],
	)
	draw_text_centered(a, fmt.ctprintf("%s   %.0f DPS  VS  %.0f", arrow, here, mine), y + 11, 8, colour)
	draw_text_centered(
		a,
		fmt.ctprintf("%s   %v ROUNDS", RARITY_NAMES[w.rarity], w.infinite ? 0 : w.ammo),
		y + 22,
		8,
		{176, 190, 214, 255},
	)
}

@(private = "file")
draw_shop_prompt :: proc(g: ^Game, item: Shop_Item) {
	a := &g.assets
	y := offer_top(g, shop_sign_top(g.shop))

	if item.kind == .Weapon {
		draw_weapon_offer(g, item.loot, y)
	} else {
		draw_text_centered(a, fmt.ctprintf("%s", shop_item_name(item)), y, 8, SHOP_COLORS[item.kind])
		draw_text_centered(a, fmt.ctprintf("%s", shop_item_detail(item)), y + 11, 8, {176, 190, 214, 255})
	}

	if reason, useless := shop_item_useless(item, g.player); useless {
		draw_text_centered(a, fmt.ctprintf("%s", reason), y + 36, 8, {150, 160, 186, 255})
		return
	}

	if g.player.coins >= item.price {
		draw_text_centered(
			a,
			action_label(fmt.tprintf("BUY   %v COINS", item.price)),
			y + 36,
			8,
			{255, 214, 110, 255},
		)
	} else {
		draw_text_centered(
			a,
			fmt.ctprintf("%v COINS - YOU HAVE %v", item.price, g.player.coins),
			y + 36,
			8,
			{228, 130, 130, 255},
		)
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
