package game

import "core:fmt"
import rl "vendor:raylib"

// The HUD and menus are laid out in the same virtual 180px-tall space as the
// world and scaled up to the window, so text stays pixel-crisp at any size.
@(private = "file")
hud_scale :: proc() -> f32 {
	return f32(rl.GetScreenHeight()) / PIXEL_HEIGHT
}

@(private = "file")
draw_text :: proc(a: ^Assets, text: cstring, pos: rl.Vector2, size: f32, color: rl.Color) {
	s := hud_scale()
	rl.DrawTextEx(a.font, text, pos * s, size * s, s, color)
}

@(private = "file")
text_width :: proc(a: ^Assets, text: cstring, size: f32) -> f32 {
	s := hud_scale()
	return rl.MeasureTextEx(a.font, text, size * s, s).x / s
}

@(private = "file")
draw_text_centered :: proc(a: ^Assets, text: cstring, y, size: f32, color: rl.Color) {
	view := view_size()
	draw_text(a, text, {(view.x - text_width(a, text, size)) / 2, y}, size, color)
}

@(private = "file")
draw_dim :: proc(alpha: u8) {
	rl.DrawRectangle(0, 0, rl.GetScreenWidth(), rl.GetScreenHeight(), {12, 14, 26, alpha})
}

hud_draw :: proc(g: ^Game) {
	a := &g.assets

	switch g.state {
	case .Title:
		draw_dim(150)
		draw_text_centered(a, "ODDY", 40, 24, {255, 214, 110, 255})
		draw_text_centered(a, "BIR PLATFORM MACERASI", 70, 8, {225, 232, 245, 255})

		hint := rl.Color{176, 190, 214, 255}
		draw_text_centered(a, "A D  /  YON TUSLARI     YURU", 94, 8, hint)
		draw_text_centered(a, "SPACE   ZIPLA - BASILI TUT, DAHA YUKSEK", 106, 8, hint)
		draw_text_centered(a, "ASAGI   PLATFORMDAN ASAGI IN", 118, 8, hint)
		draw_text_centered(a, "SLIMLERIN USTUNE ZIPLAYARAK EZ", 130, 8, hint)
		if int(g.time * 2) % 2 == 0 {
			draw_text_centered(a, "BASLAMAK ICIN SPACE", 152, 8, {255, 214, 110, 255})
		}

	case .Playing:
		draw_stats(g)

	case .Won:
		draw_stats(g)
		draw_dim(170)
		draw_text_centered(a, "TAMAMLANDI", 50, 20, {255, 214, 110, 255})
		draw_text_centered(
			a,
			fmt.ctprintf("PARA: %v / %v", g.coins_taken, g.coins_total),
			84,
			8,
			rl.RAYWHITE,
		)
		draw_text_centered(a, fmt.ctprintf("SURE: %v", format_time(g.play_time)), 98, 8, rl.RAYWHITE)
		if g.coins_taken >= g.coins_total {
			draw_text_centered(a, "TUM PARALAR TOPLANDI", 116, 8, {140, 226, 140, 255})
		}
		if int(g.time * 2) % 2 == 0 {
			draw_text_centered(a, "TEKRAR OYNAMAK ICIN R", 146, 8, {255, 214, 110, 255})
		}
	}
}

@(private = "file")
draw_stats :: proc(g: ^Game) {
	a := &g.assets
	s := hud_scale()

	for i in 0 ..< MAX_HEALTH {
		tint := i < g.player.health ? rl.WHITE : rl.Color{18, 22, 36, 190}
		dest := rl.Rectangle{(5 + f32(i) * 13) * s, 4 * s, 16 * s, 16 * s}
		rl.DrawTexturePro(
			a.fruit.texture,
			sheet_source(a.fruit, HEART_FRUIT, false),
			dest,
			{},
			0,
			tint,
		)
	}

	coin := rl.Rectangle{5 * s, 19 * s, 16 * s, 16 * s}
	rl.DrawTexturePro(a.coin.texture, sheet_source(a.coin, 0, false), coin, {}, 0, rl.WHITE)
	draw_text(a, fmt.ctprintf("%v / %v", g.coins_taken, g.coins_total), {21, 24}, 8, rl.RAYWHITE)
}

@(private = "file")
format_time :: proc(seconds: f32) -> string {
	total := int(seconds)
	return fmt.tprintf("%02d:%02d", total / 60, total % 60)
}
