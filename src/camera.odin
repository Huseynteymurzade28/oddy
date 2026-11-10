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

// Where the camera wants to be: ahead of the player by how fast they are
// going, so a run or a dash shows more of what is coming.
@(private = "file")
camera_goal :: proc(g: ^Game) -> rl.Vector2 {
	p := g.player
	g.camera_lead += (clamp(p.vel.x * 0.28, -LOOK_AHEAD * 2, LOOK_AHEAD * 2) - g.camera_lead) * min(1, rl.GetFrameTime() * 3)
	return p.pos - {0, CAMERA_LOOKUP} + {g.camera_lead, 0}
}

@(private = "file")
camera_clamp :: proc(g: ^Game) {
	view := view_size()
	half := view / 2
	// Inside the room you are in; a room smaller than the screen is centred.
	bounds := room_bounds(g)
	axis :: proc(v, half, from, size: f32) -> f32 {
		if size <= half * 2 {
			return from + size / 2
		}
		return clamp(v, from + half, from + size - half)
	}
	g.camera.target.x = axis(g.camera.target.x, half.x, bounds.x, bounds.width)
	g.camera.target.y = axis(g.camera.target.y, half.y, bounds.y, bounds.height)
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
	if g.room_slide > 0 {
		// Crossing to the next room: a smooth run from where it was looking
		// to where the new room wants it.
		g.camera.target = wanted
		camera_clamp(g)
		k := 1 - g.room_slide
		k = k * k * (3 - 2 * k)
		g.camera.target = g.room_from + (g.camera.target - g.room_from) * k
		return
	}
	// A respawn far from where you died cuts rather than pans: the trip back
	// is not worth watching for the hundredth time.
	if rl.Vector2Distance(wanted, g.camera.target) > view_size().x {
		g.camera.target = wanted
	}
	g.camera.target += (wanted - g.camera.target) * min(1, CAMERA_SMOOTH * dt)
	camera_clamp(g)
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
	midground_draw(g, g.level.zone, g.camera.target)
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
		if i == 1 && zone == .Mossy {
			draw_birds(g, view, s)
		}
		haze_draw(zone, i)
	}
}

// Now and then a little flock crosses the sky, behind the mountains.
@(private = "file")
draw_birds :: proc(g: ^Game, view: rl.Vector2, s: f32) {
	period: f32 = 26
	t := math.mod(g.time, period)
	span := view.x + 120
	for k in 0 ..< 5 {
		x := -60 + t / period * span * 1.6 - f32(k) * 11 - f32(k % 2) * 4
		y := 46 + f32(k) * 5 + math.sin(g.time * 1.3 + f32(k)) * 2 - f32(k % 2) * 6
		if x < -10 || x > view.x + 10 {
			continue
		}
		frame := int(g.time * 6 + f32(k)) % 2
		src := rl.Rectangle{f32(frame) * 8, 8, 8, 8}
		rl.DrawTexturePro(g.assets.critters, src, {math.round(x) * s, math.round(y) * s, 8 * s, 8 * s}, {}, 0, rl.WHITE)
	}
}
