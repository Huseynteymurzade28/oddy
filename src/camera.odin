package game

import "core:math"
import rl "vendor:raylib"

/*
Everything that decides what the screen shows: the fixed virtual resolution, the
camera that follows the player one room at a time, and the layers drawn behind
and over the world.

The game is rendered at a fixed virtual height and scaled up to the window, so it
always shows the same amount of world regardless of resolution. 240 tall is about
fifteen tiles, enough of a room to see a flyer coming without shrinking the
player into a dot.
*/
PIXEL_HEIGHT :: 240.0
CAMERA_LOOKUP :: 14.0 // how far above the feet the camera aims
CAMERA_SMOOTH :: 10.0
AIM_LEAD :: 30.0 // how far the camera leans toward where you are aiming

// The size of the virtual screen in world units.
view_size :: proc() -> rl.Vector2 {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	return {sw / (sh / PIXEL_HEIGHT), PIXEL_HEIGHT}
}

// The world-space rectangle the camera currently shows.
camera_view :: proc(g: ^Game) -> rl.Rectangle {
	view := view_size()
	return {g.camera.target.x - view.x / 2, g.camera.target.y - view.y / 2, view.x, view.y}
}

camera_update :: proc(g: ^Game, dt: f32) {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	g.camera.zoom = sh / PIXEL_HEIGHT
	g.camera.offset = {sw / 2, sh / 2}

	view := view_size()
	half := view / 2

	// Lean toward the crosshair, which buys a little more warning about what you
	// are shooting at without letting the player leave the frame.
	lead := rl.Vector2{math.cos(g.player.aim), math.sin(g.player.aim)} * AIM_LEAD
	wanted := g.player.pos - {0, CAMERA_LOOKUP} + lead
	g.camera.target += (wanted - g.camera.target) * min(1, CAMERA_SMOOTH * dt)

	// The camera stays inside the room the player is in: crossing a doorway is
	// what moves it on, which is what makes the map read as separate places.
	bounds := room_rect(g.room)
	if bounds.width > view.x {
		g.camera.target.x = clamp(
			g.camera.target.x,
			bounds.x + half.x,
			bounds.x + bounds.width - half.x,
		)
	} else {
		g.camera.target.x = bounds.x + bounds.width / 2
	}
	if bounds.height > view.y {
		g.camera.target.y = clamp(
			g.camera.target.y,
			bounds.y + half.y,
			bounds.y + bounds.height - half.y,
		)
	} else {
		g.camera.target.y = bounds.y + bounds.height / 2
	}
}

// Everything is underground, so the far edges of the view fall off into dark.
draw_vignette :: proc(g: ^Game, view: rl.Rectangle) {
	edge := rl.Color{10, 8, 16, 120}
	clear := rl.Color{10, 8, 16, 0}
	band := view.height * 0.22
	rl.DrawRectangleGradientV(i32(view.x), i32(view.y), i32(view.width), i32(band), edge, clear)
	rl.DrawRectangleGradientV(
		i32(view.x),
		i32(view.y + view.height - band),
		i32(view.width),
		i32(band),
		clear,
		edge,
	)
}

// Five parallax layers of forest seen through the cave mouth. They are drawn in
// screen space, tiled horizontally, and darkened as they come closer so the
// nearest one reads as a silhouette.
draw_background :: proc(g: ^Game) {
	view := view_size()
	s := f32(rl.GetScreenHeight()) / PIXEL_HEIGHT
	layer_w: f32 = PIXEL_HEIGHT * 16 / 9

	for i in 0 ..< BG_LAYERS {
		tex := g.assets.layers[i]
		if tex.id == 0 {
			continue
		}
		depth := f32(i) / f32(BG_LAYERS - 1)
		factor := 0.06 + depth * 0.24

		ox := -g.camera.target.x * factor
		ox -= math.floor(ox / layer_w) * layer_w // wrap into [0, layer_w)

		// Each copy is drawn taller than the screen and its vertical drift is
		// capped, so descending never slides an edge of the artwork into view.
		height: f32 = PIXEL_HEIGHT * 1.6
		drift := clamp(-g.camera.target.y * factor * 0.22, -PIXEL_HEIGHT * 0.4, 0)
		oy := -(height - PIXEL_HEIGHT) / 2 + drift

		shade := u8(118 - depth * 74)
		tint := rl.Color{shade, u8(f32(shade) * 1.06), u8(f32(shade) * 1.18), 255}
		src := rl.Rectangle{0, 0, f32(tex.width), f32(tex.height)}

		for c in 0 ..< int(view.x / layer_w) + 3 {
			dest := rl.Rectangle {
				(ox - layer_w + f32(c) * layer_w) * s,
				oy * s,
				layer_w * s,
				height * s,
			}
			rl.DrawTexturePro(tex, src, dest, {}, 0, tint)
		}
	}
}
