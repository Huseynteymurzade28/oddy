package game

import "core:math"
import rl "../libs/raylib"

/*
What makes the picture deep rather than flat. The painted backdrop is far
away and the level is where you are; this file fills in the distance between
them, and the little that is closer to the eye than Lumi is.

  haze        air between the backdrop's layers: each one fades into mist at
              its foot, so the hills behind look further off than the ones
              in front
  mid-ground  two layers of tall shapes standing behind the level, already
              washed out by distance: giant trees in the moss, pillars and
              arches of the drowned city, basalt spires in the deep
  shadows     a soft patch on the ground under everything that walks or flies
  foreground  dark, out-of-focus shapes along the top and bottom of the
              screen, sliding past faster than the level does

None of it is stored: every shape comes from a hash of where it stands, so
a stretch of level always has the same trees behind it.
*/

@(private = "file")
hash :: proc(a, b, salt: int) -> f32 {
	h := u32(a * 73856093) ~ u32(b * 19349663) ~ u32(salt * 83492791)
	h = (h ~ (h >> 13)) * 0x5bd1e995
	h ~= h >> 15
	return f32(h % 10000) / 10000
}

// A rectangle in virtual pixels, snapped to them: shapes built from these
// are pixel art, whatever the window's size.
@(private = "file")
vrect :: proc(x, y, w, h: f32, c: rl.Color) {
	s := hud_scale()
	rl.DrawRectangleRec({math.round(x) * s, math.round(y) * s, math.round(w) * s, math.round(h) * s}, c)
}

@(private = "file")
vdisc :: proc(cx, cy, r: f32, c: rl.Color) {
	ri := int(r)
	for dy in -ri ..= ri {
		half := math.floor(math.sqrt(r * r - f32(dy * dy)) + 0.5)
		vrect(math.round(cx) - half, math.round(cy) + f32(dy), half * 2, 1, c)
	}
}

// --------------------------------------------------------------------- haze ---

// Mist at the foot of a backdrop layer, drawn straight after it. `layer` is
// the backdrop's index; the sky and the clouds get none.
haze_draw :: proc(zone: Zone, layer: int, strength: f32 = 1) {
	alpha: f32
	top: f32 // where the mist starts, as a fraction of the screen's height
	switch layer {
	case 2:
		alpha, top = 150, 0.34
	case 3:
		alpha, top = 96, 0.5
	case:
		return
	}
	c := ZONE_LOOKS[zone].haze
	clear := c
	clear.a = 0
	c.a = u8(alpha * strength)
	sw := rl.GetScreenWidth()
	sh := f32(rl.GetScreenHeight())
	y := i32(sh * top)
	rl.DrawRectangleGradientV(0, y, sw, i32(sh) - y, clear, c)
}

// --------------------------------------------------------------- mid-ground ---

Mid_Colours :: struct {
	body:   rl.Color,
	light:  rl.Color, // the side the sun is on
	dark:   rl.Color,
	extra:  rl.Color, // leaves, moss, or the glow in the cracks
	extra2: rl.Color,
}

Mid_Layer :: struct {
	parallax: f32,
	spacing:  f32, // between one column and the next, in virtual pixels
	width:    [2]f32,
	chance:   f32, // that a slot has a column in it
}

MID_LAYERS := [2]Mid_Layer {
	{parallax = 0.58, spacing = 104, width = {9, 15}, chance = 0.5},
	{parallax = 0.78, spacing = 168, width = {15, 25}, chance = 0.5},
}

MID_COLOURS := [Zone][2]Mid_Colours {
	.Mossy = {
		{body = {160, 204, 228, 255}, light = {180, 220, 238, 255}, dark = {146, 192, 220, 255}, extra = {156, 216, 204, 255}, extra2 = {178, 230, 214, 255}},
		{body = {120, 168, 182, 255}, light = {146, 190, 196, 255}, dark = {102, 150, 170, 255}, extra = {112, 186, 148, 255}, extra2 = {140, 208, 160, 255}},
	},
	.Drowned = {
		{body = {140, 194, 230, 255}, light = {162, 210, 238, 255}, dark = {124, 180, 220, 255}, extra = {140, 210, 204, 255}, extra2 = {160, 222, 214, 255}},
		{body = {104, 160, 208, 255}, light = {130, 184, 222, 255}, dark = {86, 142, 194, 255}, extra = {100, 182, 176, 255}, extra2 = {124, 200, 190, 255}},
	},
	.Ember = {
		{body = {176, 104, 134, 255}, light = {204, 126, 140, 255}, dark = {158, 90, 124, 255}, extra = {255, 176, 120, 255}, extra2 = {255, 210, 150, 255}},
		{body = {152, 86, 118, 255}, light = {182, 106, 126, 255}, dark = {134, 72, 108, 255}, extra = {255, 150, 84, 255}, extra2 = {255, 206, 130, 255}},
	},
}

// The tall shapes behind the level, as seen from `look`. Drawn in screen
// space like the backdrop, between it and the tiles.
midground_draw :: proc(g: ^Game, zone: Zone, look: rl.Vector2) {
	view := view_size()
	for layer, li in MID_LAYERS {
		cols := MID_COLOURS[zone][li]
		// The layer's own coordinates: where the screen's left and top edges
		// fall on it.
		left := look.x * layer.parallax - view.x / 2
		top := look.y * layer.parallax - view.y / 2
		i0 := int(math.floor((left - 60) / layer.spacing))
		i1 := int(math.floor((left + view.x + 60) / layer.spacing))
		for i in i0 ..= i1 {
			salt := li * 100 + int(zone) * 1000
			if hash(i, 0, salt) > layer.chance {
				continue
			}
			x := f32(i) * layer.spacing + hash(i, 1, salt) * layer.spacing * 0.5 - left
			w := math.round(layer.width[0] + hash(i, 2, salt) * (layer.width[1] - layer.width[0]))
			switch zone {
			case .Mossy:
				mid_tree(g, i, salt, x, w, top, view, cols, li)
			case .Drowned:
				mid_pillar(g, i, salt, x, w, top, view, cols, layer, left)
			case .Ember:
				mid_spire(g, i, salt, x, w, top, view, cols, li)
			}
		}
	}
}

// Which repeats of something that comes round every `step` pixels up a
// column are on screen.
@(private = "file")
rows :: proc(top, height, step, margin: f32) -> (j0, j1: int) {
	return int(math.floor((top - margin) / step)), int(math.floor((top + height + margin) / step))
}

// A trunk too tall to see the top of, with boughs of leaves here and there.
@(private = "file")
mid_tree :: proc(g: ^Game, i, salt: int, x, w, top: f32, view: rl.Vector2, c: Mid_Colours, li: int) {
	vrect(x, 0, w, view.y, c.body)
	vrect(x + w - 2, 0, 2, view.y, c.light)
	vrect(x, 0, li == 0 ? 1 : 2, view.y, c.dark)

	// Bark: short dark strokes.
	j0, j1 := rows(top, view.y, 13, 10)
	for j in j0 ..= j1 {
		y := f32(j) * 13 - top
		bx := x + 3 + math.floor(hash(i, j, salt + 5) * (w - 7))
		vrect(bx, y + hash(i, j, salt + 6) * 6, 1, 4 + hash(i, j, salt + 7) * 4, c.dark)
	}

	// Boughs, alternating sides more often than not.
	step: f32 = li == 0 ? 74 : 104
	j0, j1 = rows(top, view.y, step, 60)
	for j in j0 ..= j1 {
		if hash(i, j, salt + 10) < 0.25 {
			continue
		}
		y := f32(j) * step + hash(i, j, salt + 11) * step * 0.5 - top
		side: f32 = hash(i, j, salt + 12) < 0.5 ? -1 : 1
		reach := (li == 0 ? 10 : 16) + hash(i, j, salt + 13) * (li == 0 ? 10 : 18)
		r := (li == 0 ? 7 : 11) + hash(i, j, salt + 14) * (li == 0 ? 4 : 6)
		from := side > 0 ? x + w : x - reach
		vrect(from, y, reach, li == 0 ? 2 : 3, c.dark)
		cx := side > 0 ? x + w + reach : x - reach
		sway := math.sin(g.time * 0.9 + f32(i) + f32(j) * 1.7) * 1.2
		vdisc(cx + sway, y - 2, r, c.extra)
		vdisc(cx + sway - side * r * 0.9, y + 1, r * 0.7, c.extra)
		vdisc(cx + sway + side * r * 0.8, y + 2, r * 0.75, c.extra)
		vdisc(cx + sway + r * 0.25, y - 2 - r * 0.3, r * 0.55, c.extra2)
		// A vine or two let down from the leaves.
		if hash(i, j, salt + 15) < 0.6 {
			vx := cx + sway * 1.6 - side * r * 0.5
			length := 10 + hash(i, j, salt + 16) * 26
			vrect(vx, y + r * 0.5, 1, length, c.extra)
			vrect(vx - 1, y + r * 0.5 + length * 0.5, 1, 2, c.extra)
			vrect(vx + 1, y + r * 0.5 + length - 2, 1, 2, c.extra)
		}
	}
}

// A column of the drowned city, banded, mossed, and sometimes still joined
// to the next by an arch.
@(private = "file")
mid_pillar :: proc(g: ^Game, i, salt: int, x, w, top: f32, view: rl.Vector2, c: Mid_Colours, layer: Mid_Layer, left: f32) {
	vrect(x, 0, w, view.y, c.body)
	vrect(x + w - 2, 0, 2, view.y, c.light)
	vrect(x, 0, 2, view.y, c.dark)
	// Fluting down the middle.
	vrect(x + math.floor(w * 0.4), 0, 1, view.y, c.dark)
	vrect(x + math.floor(w * 0.62), 0, 1, view.y, c.light)

	// Courses of stone.
	j0, j1 := rows(top, view.y, 16, 4)
	for j in j0 ..= j1 {
		y := f32(j) * 16 - top
		vrect(x + 2, y, w - 4, 1, c.dark)
	}

	// A band every so often, with moss hanging off it, and maybe an arch
	// across to the next column.
	step: f32 = 112
	j0, j1 = rows(top, view.y, step, 60)
	for j in j0 ..= j1 {
		y := f32(j) * step + hash(i, 0, salt + 20) * step - top
		vrect(x - 3, y, w + 6, 4, c.light)
		vrect(x - 2, y + 4, w + 4, 2, c.body)
		vrect(x - 2, y + 6, w + 4, 1, c.dark)
		if hash(i, j, salt + 21) < 0.7 {
			mx := x + 1 + math.floor(hash(i, j, salt + 22) * (w - 6))
			length := 8 + hash(i, j, salt + 23) * 22
			vrect(mx, y + 7, 3, length, c.extra)
			vrect(mx + 3, y + 7, 2, length * 0.6, c.extra2)
			vrect(mx - 2, y + 7, 2, length * 0.4, c.extra)
		}

		// The arch: only if there is a column in the next slot to carry it.
		if hash(i + 1, 0, salt) > layer.chance || hash(i, j, salt + 24) > 0.55 {
			continue
		}
		nx := f32(i + 1) * layer.spacing + hash(i + 1, 1, salt) * layer.spacing * 0.5 - left
		span := nx - (x + w)
		if span < 20 {
			continue
		}
		ax := x + w
		vrect(ax, y - 6, span, 5, c.body)
		vrect(ax, y - 7, span, 1, c.light)
		// The curve under the beam, in steps.
		STEPS :: 9
		for k in 0 ..< STEPS {
			t0 := f32(k) / STEPS
			t1 := f32(k + 1) / STEPS
			mid := (t0 + t1) / 2 * 2 - 1 // -1 at one foot, +1 at the other
			drop := (1 - math.sqrt(max(0, 1 - mid * mid))) * min(span * 0.35, 26)
			vrect(ax + span * t0, y - 1, span * (t1 - t0) + 1, drop, c.body)
			vrect(ax + span * t0, y - 1 + drop, span * (t1 - t0) + 1, 1, c.dark)
		}
	}
}

// A spire of basalt: stacked blocks, no two quite in line, split by cracks
// that glow from inside.
@(private = "file")
mid_spire :: proc(g: ^Game, i, salt: int, x, width, top: f32, view: rl.Vector2, c: Mid_Colours, li: int) {
	w := math.round(width * 1.25)
	a := math.round(w * 0.34)
	b := math.round(w * 0.4)
	BLOCK :: 34
	j0, j1 := rows(top, view.y, BLOCK, 4)
	for j in j0 ..= j1 {
		y := f32(j) * BLOCK - top
		shift := math.round((hash(i, j, salt + 30) - 0.5) * w * 0.45)
		wide := math.round(w * (0.85 + hash(i, j, salt + 31) * 0.5))
		bx := x + shift
		vrect(bx, y, wide, BLOCK, c.body)
		vrect(bx, y, math.round(wide * 0.3), BLOCK, c.dark)
		vrect(bx + math.round(wide * 0.72), y, wide - math.round(wide * 0.72), BLOCK, c.light)
		vrect(bx, y, wide, 1, c.light) // the ledge on top of the block
		vrect(bx, y + BLOCK - 2, wide, 2, c.dark)
		if hash(i, j, salt + 36) < 0.4 {
			// A shard standing on the ledge.
			sx := bx + (hash(i, j, salt + 37) < 0.5 ? -3 : wide)
			vrect(sx, y + BLOCK - 9, 3, 9, c.body)
			vrect(sx + 1, y + BLOCK - 13, 1, 4, c.body)
		}
	}

	// The glow in the cracks, slowly breathing.
	j0, j1 = rows(top, view.y, 58, 30)
	for j in j0 ..= j1 {
		if hash(i, j, salt + 32) < 0.45 {
			continue
		}
		y := f32(j) * 58 + hash(i, j, salt + 33) * 40 - top
		pulse := 0.55 + 0.45 * math.sin(g.time * 1.4 + f32(i) * 2 + f32(j))
		glow := lerp_color(c.body, c.extra, pulse * (li == 0 ? 0.6 : 0.9))
		cx := x + a + (hash(i, j, salt + 34) < 0.5 ? 0 : b)
		length := 8 + hash(i, j, salt + 35) * 14
		vrect(cx, y, 1, length, glow)
		vrect(cx + 1, y + length * 0.3, 1, length * 0.4, glow)
		if li == 1 {
			vrect(cx, y + length * 0.4, 1, 2, lerp_color(c.body, c.extra2, pulse))
		}
	}
}

// ------------------------------------------------------------------ shadows ---

// How far down a shadow is still cast, in tiles.
SHADOW_REACH :: 6

// A patch of shade on the first ground under `pos`, smaller and fainter the
// higher up whatever casts it is.
@(private = "file")
shadow :: proc(g: ^Game, pos: rl.Vector2, half: f32) {
	m := &g.map_tiles
	lands :: proc(m: ^Tilemap, x, y: int) -> bool {
		t := tile_at(m, x, y)
		return is_blocking(t) || t == .Platform
	}
	tx := int(math.floor(pos.x / TILE))
	ty0 := int(math.floor((pos.y - 1) / TILE)) + 1
	for ty in ty0 ..< ty0 + SHADOW_REACH {
		if tile_at(m, tx, ty) == .Water {
			return
		}
		if !lands(m, tx, ty) {
			continue
		}
		ground := f32(ty) * TILE
		k := 1 - clamp((ground - pos.y) / (SHADOW_REACH * TILE), 0, 1)
		w := math.round(half * (0.45 + 0.55 * k))
		// Not past the edge of what it falls on.
		x0 := pos.x - w
		x1 := pos.x + w
		if !lands(m, tx - 1, ty) || lands(m, tx - 1, ty - 1) {
			x0 = max(x0, f32(tx) * TILE)
		}
		if !lands(m, tx + 1, ty) || lands(m, tx + 1, ty - 1) {
			x1 = min(x1, f32(tx + 1) * TILE)
		}
		x0 = math.round(x0)
		x1 = math.round(x1)
		c := rl.Color{24, 18, 44, u8(74 * k)}
		rl.DrawRectangleRec({x0 + 1, ground, x1 - x0 - 2, 1}, c)
		rl.DrawRectangleRec({x0, ground + 1, x1 - x0, 1}, c)
		rl.DrawRectangleRec({x0 + 2, ground + 2, x1 - x0 - 4, 1}, c)
		return
	}
}

shadows_draw :: proc(g: ^Game) {
	p := g.player
	if !p.dead && p.respawn_time <= RESPAWN_TIME * 0.4 && p.riding < 0 && !p.in_water {
		shadow(g, p.pos, 7)
	}
	for e in g.enemies {
		if e.alive {
			shadow(g, e.pos, ENEMY_TRAITS[e.kind].size.x * 0.5 + 2)
		}
	}
}

// --------------------------------------------------------------- foreground ---

FG_PARALLAX :: 1.45
FG_SPACING :: 132.0

@(private = "file")
SOFT_ALPHA := [3]f32{0.22, 0.4, 1}

// A filled shape with two fainter, fatter copies behind it: close things
// are out of focus.
@(private = "file")
soft_tri :: proc(a, b, c: rl.Vector2, colour: rl.Color) {
	s := hud_scale()
	centre := (a + b + c) / 3
	grows := [3]f32{1.3, 1.14, 1}
	for k in 0 ..< 3 {
		grow := grows[k]
		col := colour
		col.a = u8(f32(colour.a) * SOFT_ALPHA[k])
		tri((centre + (a - centre) * grow) * s, (centre + (b - centre) * grow) * s, (centre + (c - centre) * grow) * s, col)
	}
}

@(private = "file")
soft_disc :: proc(p: rl.Vector2, r: f32, colour: rl.Color) {
	s := hud_scale()
	for k in 0 ..< 3 {
		col := colour
		col.a = u8(f32(colour.a) * SOFT_ALPHA[k])
		rl.DrawCircleV(p * s, (r + f32(2 - k) * 1.2) * s, col)
	}
}

@(private = "file")
soft_line :: proc(a, b: rl.Vector2, thick: f32, colour: rl.Color) {
	s := hud_scale()
	for k in 0 ..< 2 {
		col := colour
		col.a = u8(f32(colour.a) * (k == 0 ? 0.3 : 1))
		rl.DrawLineEx(a * s, b * s, (thick + (k == 0 ? 2 : 0)) * s, col)
	}
}

// The nearest things of all, along the bottom and top of the screen. They
// belong to the floor and the roof of the level, so they slide out of sight
// as the camera leaves either: in the middle of a tall climb nothing is in
// the way.
foreground_draw :: proc(g: ^Game) {
	view := view_size()
	zone := g.level.zone
	look := g.camera.target
	level := tilemap_bounds(&g.map_tiles)
	// How far the camera is from the floor and from the roof.
	sink := max(0, level.y - (look.y + view.y / 2)) * (FG_PARALLAX - 1) * 1.6
	rise := max(0, look.y - view.y / 2) * (FG_PARALLAX - 1) * 1.6
	left := look.x * FG_PARALLAX - view.x / 2
	i0 := int(math.floor((left - 80) / FG_SPACING))
	i1 := int(math.floor((left + view.x + 80) / FG_SPACING))
	salt := 7000 + int(zone) * 100

	dark: rl.Color
	switch zone {
	case .Mossy:
		dark = {20, 50, 50, 236}
	case .Drowned:
		dark = {16, 38, 78, 236}
	case .Ember:
		dark = {36, 14, 34, 240}
	}

	for i in i0 ..= i1 {
		x := f32(i) * FG_SPACING + hash(i, 1, salt) * FG_SPACING * 0.6 - left
		floor := view.y + 3 + sink
		if sink < 40 && hash(i, 0, salt) < 0.62 {
			switch zone {
			case .Mossy:
				fg_bush(g, i, salt, {x, floor}, dark)
			case .Drowned:
				fg_kelp(g, i, salt, {x, floor}, dark)
			case .Ember:
				fg_rocks(g, i, salt, {x, floor}, dark)
			}
		}
		roof := -3 - rise
		if rise < 44 && hash(i, 4, salt) < 0.45 {
			x2 := x + FG_SPACING * 0.5
			switch zone {
			case .Mossy:
				fg_leaves(g, i, salt, {x2, roof}, dark)
			case .Drowned, .Ember:
				fg_stalactites(i, salt, {x2, roof}, dark)
			}
		}
	}
}

// A bush: nothing but round shapes, so nobody takes it for spikes.
@(private = "file")
fg_bush :: proc(g: ^Game, i, salt: int, foot: rl.Vector2, dark: rl.Color) {
	sway := math.sin(g.time * 1.3 + f32(i)) * 1.2
	soft_disc(foot + {-13, 2}, 8 + hash(i, 10, salt) * 3, dark)
	soft_disc(foot + {sway * 0.4, -3}, 11 + hash(i, 11, salt) * 4, dark)
	soft_disc(foot + {13, 1}, 9 + hash(i, 12, salt) * 3, dark)
	// Sprigs of leaves standing proud of it, stirring.
	sprigs := 2 + int(hash(i, 13, salt) * 3)
	for l in 0 ..< sprigs {
		f := f32(l) / f32(sprigs) * 2 - 0.8
		h := 13 + hash(i, 14 + l, salt) * 6
		soft_disc(foot + {f * 12 + sway, -h}, 3.2 + hash(i, 24 + l, salt) * 1.6, dark)
		soft_disc(foot + {f * 9 + sway * 0.6, -h + 5}, 4.4, dark)
	}
}

// Ribbons of weed standing up from the bottom, swaying together.
@(private = "file")
fg_kelp :: proc(g: ^Game, i, salt: int, foot: rl.Vector2, dark: rl.Color) {
	ribbons := 2 + int(hash(i, 10, salt) * 3)
	for r in 0 ..< ribbons {
		base := foot + {f32(r) * 7 - f32(ribbons) * 3.5, 0}
		h := 16 + hash(i, 11 + r, salt) * 14
		prev := base
		SEGS :: 5
		for k in 1 ..= SEGS {
			f := f32(k) / SEGS
			p := base + {math.sin(g.time * 1.2 + f32(i) + f32(r) + f * 3) * 3.5 * f, -h * f}
			soft_line(prev, p, 3.2 - f * 1.8, dark)
			prev = p
		}
	}
	soft_disc(foot + {0, 3}, 7, dark)
}

// Broken rock, blunt on top, with a hot edge where the lava's light
// catches it.
@(private = "file")
fg_rocks :: proc(g: ^Game, i, salt: int, foot: rl.Vector2, dark: rl.Color) {
	s := hud_scale()
	count := 2 + int(hash(i, 10, salt) * 3)
	for r in 0 ..< count {
		base := foot + {f32(r) * 14 - f32(count) * 7, 0}
		h := 8 + hash(i, 11 + r, salt) * 12
		w := 8 + hash(i, 21 + r, salt) * 6
		lean := (hash(i, 31 + r, salt) - 0.5) * 6
		top_l := base + {lean - w * 0.45, -h}
		top_r := base + {lean + w * 0.4, -h + 2}
		soft_tri(base + {-w, 0}, base + {w, 0}, top_l, dark)
		soft_tri(base + {w, 0}, top_r, top_l, dark)
		glow := 0.6 + 0.4 * math.sin(g.time * 1.7 + f32(i + r))
		rl.DrawLineEx((base + {-w, 0}) * s, top_l * s, 0.8 * s, {255, 130, 60, u8(110 * glow)})
		rl.DrawLineEx(top_l * s, top_r * s, 0.8 * s, {255, 130, 60, u8(70 * glow)})
	}
}

// Leaves hanging in from above the screen, with a creeper or two.
@(private = "file")
fg_leaves :: proc(g: ^Game, i, salt: int, top: rl.Vector2, dark: rl.Color) {
	sway := math.sin(g.time * 1.1 + f32(i)) * 1.5
	soft_disc(top + {sway, 0}, 11, dark)
	soft_disc(top + {-12 + sway, -2}, 8, dark)
	soft_disc(top + {13 + sway, -3}, 9, dark)
	creepers := 1 + int(hash(i, 12, salt) * 3)
	for c in 0 ..< creepers {
		base := top + {f32(c) * 9 - 8 + sway, 6}
		length := 10 + hash(i, 13 + c, salt) * 16
		prev := base
		SEGS :: 4
		for k in 1 ..= SEGS {
			f := f32(k) / SEGS
			p := base + {math.sin(g.time * 1.4 + f32(i + c) + f * 2) * 2.5 * f, length * f}
			soft_line(prev, p, 1.6, dark)
			prev = p
		}
		soft_disc(prev, 1.8, dark)
	}
}

@(private = "file")
fg_stalactites :: proc(i, salt: int, top: rl.Vector2, dark: rl.Color) {
	count := 2 + int(hash(i, 12, salt) * 3)
	for c in 0 ..< count {
		base := top + {f32(c) * 11 - f32(count) * 5.5, 0}
		h := 10 + hash(i, 13 + c, salt) * 18
		w := 4 + hash(i, 23 + c, salt) * 3
		soft_tri(base + {-w, 0}, base + {w, 0}, base + {(hash(i, 33 + c, salt) - 0.5) * 4, h}, dark)
	}
}
