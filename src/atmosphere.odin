package game

import "core:math"
import rl "../libs/raylib"

/*
Light that is not a lamp: drawn additively over the lit world, so it brightens
whatever it falls across. Each zone gets one thing:

  Mossy    shafts of daylight slanting down from cracks in the ceiling
  Drowned  a soft blue shimmer that rises off the floor and wavers
  Ember    a hot glow welling up from below

The level is cut into screen-sized chunks and each one places its light from
its own grid position, so a stretch of level looks the same every time you
come back to it.
*/

CHUNK_W :: 32 // tiles
CHUNK_H :: 18

atmosphere_draw :: proc(g: ^Game, view: rl.Rectangle) {
	rl.BeginBlendMode(.ADDITIVE)
	defer rl.EndBlendMode()

	cw: f32 = CHUNK_W * TILE
	ch: f32 = CHUNK_H * TILE
	x0 := int(view.x / cw)
	y0 := int(view.y / ch)
	for cy in y0 ..= int((view.y + view.height) / ch) {
		for cx in x0 ..= int((view.x + view.width) / cw) {
			cell := [2]int{cx, cy}
			bounds := rl.Rectangle{f32(cx) * cw, f32(cy) * ch, cw, ch}
			switch g.level.zone {
			case .Mossy:
				sun_shafts(g, cell, bounds)
			case .Drowned:
				shimmer(g, bounds, {60, 120, 170, 0})
			case .Ember:
				shimmer(g, bounds, {190, 80, 30, 0})
			}
		}
	}
}

@(private = "file")
hash :: proc(cell: [2]int, i: int) -> f32 {
	h := u32(cell.x * 73856093) ~ u32(cell.y * 19349663) ~ u32(i * 83492791)
	h = (h ~ (h >> 13)) * 0x5bd1e995
	h ~= h >> 15
	return f32(h % 10000) / 10000
}

// Three or four slanted beams, each a stack of strips that fade as they go
// down, and breathe a little.
@(private = "file")
sun_shafts :: proc(g: ^Game, cell: [2]int, bounds: rl.Rectangle) {
	count := 3 + int(hash(cell, 0) * 2)
	slant: f32 = 0.35
	for i in 0 ..< count {
		x := bounds.x + bounds.width * (0.12 + 0.76 * hash(cell, i + 1))
		width := 10 + hash(cell, i + 11) * 16
		length := bounds.height * (0.55 + hash(cell, i + 21) * 0.35)
		breathe := 0.75 + 0.25 * math.sin(g.time * 0.8 + f32(i) * 2.1)
		top := bounds.y + TILE

		SEGMENTS :: 10
		for s in 0 ..< SEGMENTS {
			t0 := f32(s) / SEGMENTS
			t1 := f32(s + 1) / SEGMENTS
			y0 := top + length * t0
			y1 := top + length * t1
			w0 := width * (1 + t0 * 1.4)
			w1 := width * (1 + t1 * 1.4)
			x0 := x + (y0 - top) * slant
			x1 := x + (y1 - top) * slant
			a := u8(26 * (1 - t0) * breathe)
			c := rl.Color{a, u8(f32(a) * 0.95), u8(f32(a) * 0.7), 255}
			quad({x0 - w0 / 2, y0}, {x0 + w0 / 2, y0}, {x1 + w1 / 2, y1}, {x1 - w1 / 2, y1}, c)
		}
	}
}

// A glow from the floor up that slowly breathes, so it reads as heat or water
// light rather than a flat wash.
@(private = "file")
shimmer :: proc(g: ^Game, bounds: rl.Rectangle, colour: rl.Color) {
	breathe := 0.75 + 0.25 * math.sin(g.time * 1.3 + bounds.x * 0.01)
	height := bounds.height * (0.5 + 0.04 * math.sin(g.time * 0.9))
	k := 0.3 * breathe
	bottom := rl.Color{u8(f32(colour.r) * k), u8(f32(colour.g) * k), u8(f32(colour.b) * k), 255}
	top := rl.Color{0, 0, 0, 255}
	y := bounds.y + bounds.height - TILE - height
	rl.DrawRectangleGradientV(i32(bounds.x), i32(y), i32(bounds.width), i32(height), top, bottom)
}

@(private = "file")
quad :: proc(a, b, c, d: rl.Vector2, colour: rl.Color) {
	tri(a, b, c, colour)
	tri(a, c, d, colour)
}
