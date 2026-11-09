package game

import "core:math"
import rl "../libs/raylib"

/*
Everything that decides what the screen shows: the fixed virtual resolution, the
camera that follows the player around the level, and the layers drawn behind
and over the world.

The game is rendered at a fixed virtual height and scaled up to the window, so it
always shows the same amount of world regardless of resolution. 240 tall is
fifteen tiles: enough to read the next jump without shrinking the player into
a dot.
*/
PIXEL_HEIGHT :: 240.0
CAMERA_LOOKUP :: 14.0 // how far above the feet the camera aims
CAMERA_SMOOTH :: 8.0
LOOK_AHEAD :: 24.0 // how far the camera leans the way you are facing

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

// Where the camera wants to be: a little ahead of the player, never showing
// anything past the edges of the level.
@(private = "file")
camera_goal :: proc(g: ^Game) -> rl.Vector2 {
	p := g.player
	ahead: f32 = p.flip ? -LOOK_AHEAD : LOOK_AHEAD
	return p.pos - {0, CAMERA_LOOKUP} + {ahead, 0}
}

@(private = "file")
camera_clamp :: proc(g: ^Game) {
	view := view_size()
	half := view / 2
	bounds := tilemap_bounds(&g.map_tiles)
	axis :: proc(v, half, size: f32) -> f32 {
		if size <= half * 2 {
			return size / 2
		}
		return clamp(v, half, size - half)
	}
	g.camera.target.x = axis(g.camera.target.x, half.x, bounds.x)
	g.camera.target.y = axis(g.camera.target.y, half.y, bounds.y)
}

@(private = "file")
camera_fit :: proc(g: ^Game) {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	g.camera.zoom = sh / PIXEL_HEIGHT
	g.camera.offset = {sw / 2, sh / 2}
}

// Jumps straight to the player: at the start of a level.
camera_snap :: proc(g: ^Game) {
	camera_fit(g)
	g.camera.target = camera_goal(g)
	camera_clamp(g)
}

camera_update :: proc(g: ^Game, dt: f32) {
	camera_fit(g)
	wanted := camera_goal(g)
	// A respawn far from where you died cuts rather than pans: the trip back
	// is not worth watching for the hundredth time.
	if rl.Vector2Distance(wanted, g.camera.target) > view_size().x {
		g.camera.target = wanted
	}
	g.camera.target += (wanted - g.camera.target) * min(1, CAMERA_SMOOTH * dt)
	camera_clamp(g)
}

// A faint darkening at the top and bottom edges, to hold the eye in the
// middle of the screen.
draw_vignette :: proc(g: ^Game, view: rl.Rectangle) {
	edge := rl.Color{10, 8, 16, 22}
	clear := rl.Color{10, 8, 16, 0}
	band := view.height * 0.16
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

// Each world's own five layers (see tools/art/backgrounds.py): the sky, the
// clouds, the far horizon, the hills and the nearest silhouettes, each moving
// a little more with the camera than the one behind it. Drawn in screen space
// at one image pixel per virtual pixel, so they stay as crisp as the level.
BG_PARALLAX := [BG_LAYERS]f32{0, 0.06, 0.12, 0.28, 0.5}
BG_W :: 480.0
BG_H :: 270.0

draw_background :: proc(g: ^Game) {
	draw_backdrop(g, g.level.zone, g.camera.target, tilemap_bounds(&g.map_tiles).y)
}

// Also used by the world map, with a slowly panning point of view.
draw_backdrop :: proc(g: ^Game, zone: Zone, look: rl.Vector2, level_h: f32) {
	view := view_size()
	s := f32(rl.GetScreenHeight()) / PIXEL_HEIGHT
	for i in 0 ..< BG_LAYERS {
		tex := g.assets.layers[zone][i]
		if tex.id == 0 {
			continue
		}
		f := BG_PARALLAX[i]
		ox := -look.x * f
		if i == 1 {
			ox -= g.time * 4 // the clouds drift on their own
		}
		ox -= math.floor(ox / BG_W) * BG_W
		// Bottom-aligned with a little slack: higher in a tall level, the
		// hills sink and more sky shows.
		drift := clamp(-(look.y - level_h / 2) * f * 0.12, -14, 14)
		oy := PIXEL_HEIGHT - BG_H + 15 + drift
		src := rl.Rectangle{0, 0, BG_W, BG_H}
		for c in 0 ..< int(view.x / BG_W) + 2 {
			dest := rl.Rectangle{math.round((ox - BG_W + f32(c) * BG_W) * s), math.round(oy * s), BG_W * s, BG_H * s}
			rl.DrawTexturePro(tex, src, dest, {}, 0, rl.WHITE)
		}
	}
}
