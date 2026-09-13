package game

import "core:math/rand"
import rl "vendor:raylib"

/*
Scenery: grass, bushes, stones, crates, fence posts, ladder scraps, and the trees
in the cave mouth. None of it collides and none of it moves. Props exist so a room
reads as somewhere that was dug and then abandoned rather than a grid of tiles, so
they are rolled once per floor tile when a run is generated and never touched
again.

They draw in three layers, which is what stops decoration from turning into
clutter:

  Behind  before the tilemap, so the rock overlaps them and they read as part of
          the wall — trees, ridges, ladder scraps.
  Level   after the tilemap, before anything alive — stones, crates, fences, the
          things that sit on the floor at the same depth the player does.
  Front   after the player — grass and low bushes, drawn over boots, which is
          what makes a floor look like it has a surface at all.
*/

Prop_Layer :: enum u8 {
	Behind,
	Level,
	Front,
}

Prop :: struct {
	tex:   rl.Texture2D,
	pos:   rl.Vector2, // the feet, horizontally centred
	layer: Prop_Layer,
	flip:  bool,
	tint:  rl.Color,
}

@(private = "file")
Prop_Rule :: struct {
	kind:   Prop_Kind,
	chance: f32, // per eligible floor tile
	layer:  Prop_Layer,
	tint:   rl.Color,
}

// Checked in order, first hit wins, so the rare big things get their chance
// before grass carpets everything. The tints pull forest-green art down into a
// lit-from-nowhere cave; without them the props glow against the tileset.
@(private = "file")
PROP_RULES := [?]Prop_Rule {
	{.Ridge, 0.028, .Behind, {96, 102, 112, 255}},
	{.Ladder, 0.030, .Behind, {112, 96, 78, 255}},
	{.Stone, 0.045, .Level, {138, 140, 150, 255}},
	{.Box, 0.030, .Level, {158, 138, 112, 255}},
	{.Fence, 0.040, .Level, {150, 134, 112, 255}},
	{.Bush, 0.120, .Front, {104, 136, 108, 255}},
	{.Grass, 0.400, .Front, {116, 148, 118, 255}},
}

// The cave mouth the background layers show through. Only the starting room gets
// these, and only as silhouettes behind the rock.
@(private = "file")
LANDMARK_TINT :: rl.Color{58, 70, 66, 255}

// Does the sprite fit in open air, standing on this tile? Sprites carry
// transparent padding, so this is deliberately strict about the whole bounding
// box: a bush half-buried in rock looks worse than a bare floor.
@(private = "file")
prop_fits :: proc(m: ^Tilemap, tex: rl.Texture2D, feet: rl.Vector2) -> bool {
	left := int((feet.x - f32(tex.width) / 2) / TILE)
	right := int((feet.x + f32(tex.width) / 2 - 1) / TILE)
	top := int((feet.y - f32(tex.height)) / TILE)
	bottom := int((feet.y - 1) / TILE)

	for ty in top ..= bottom {
		for tx in left ..= right {
			t := tile_at(m, tx, ty)
			if is_blocking(t) || t == .Platform || is_hazard(t) {
				return false
			}
		}
	}
	return true
}

// Everything the player has to walk up to and read needs its own clearance, or
// the prompt ends up talking from behind a bush.
@(private = "file")
prop_crowds_gameplay :: proc(g: ^Game, feet: rl.Vector2, half_w: f32) -> bool {
	near :: proc(a, b: rl.Vector2, r: f32) -> bool {
		return abs(a.x - b.x) < r && abs(a.y - b.y) < 44
	}

	if near(feet, g.player.pos, half_w + 26) || near(feet, g.flag_pos, half_w + 22) {
		return true
	}
	if g.shop.open && near(feet, g.shop.pos, half_w + SHOP_SLOT_GAP + 28) {
		return true
	}
	for c in g.chests {
		if near(feet, c.pos, half_w + 24) {
			return true
		}
	}
	for p in g.pickups {
		if near(feet, p.pos, half_w + 14) {
			return true
		}
	}
	return false
}

// Rolls scenery across every room that exists. Runs last in `world_generate`,
// once the terrain, the doors and everything living in the rooms are settled —
// props are the only thing that has to dodge all of it.
scatter_props :: proc(g: ^Game) {
	clear(&g.props)
	a := &g.assets
	m := &g.map_tiles

	for ry in 0 ..< GRID_H {
		for rx in 0 ..< GRID_W {
			room := g.world.rooms[ry][rx]
			if room.role == .Unused {
				continue
			}
			if room.role == .Start {
				scatter_landmarks(g, {rx, ry})
			}

			ox, oy := rx * ROOM_W, ry * ROOM_H
			// The two columns either side of a room boundary are left bare: a prop
			// there would straddle two rooms and hang across a side doorway.
			for x in 2 ..< ROOM_W - 2 {
				for y in 0 ..< ROOM_H {
					tx, ty := ox + x, oy + y
					below := tile_at(m, tx, ty + 1)
					if !is_blocking(below) && below != .Platform {
						continue // nothing to stand on
					}

					for rule in PROP_RULES {
						if rand.float32() >= rule.chance {
							continue
						}
						// A one-way platform gets tufts of grass, but nothing with
						// weight: a crate balanced on a thin ledge reads as a bug.
						if below == .Platform && rule.layer != .Front {
							continue
						}
						// The arena stays bare of anything at eye level: a boulder
						// the size of the golem in front of the fight hides the
						// swing you are meant to be reading.
						if room.role == .Boss && rule.layer == .Level {
							continue
						}
						tex := prop_texture(a, rule.kind, rand.int_max(PROP_VARIANTS))
						if tex.id == 0 {
							break
						}
						feet := rl.Vector2{f32(tx) * TILE + TILE / 2, f32(ty) * TILE + TILE}

						// Behind-layer props are meant to be overlapped by rock, so
						// they only need somewhere to stand.
						if rule.layer != .Behind && !prop_fits(m, tex, feet) {
							break
						}
						if prop_crowds_gameplay(g, feet, f32(tex.width) / 2) {
							break
						}

						append(
							&g.props,
							Prop {
								tex = tex,
								pos = feet,
								layer = rule.layer,
								flip = rand.float32() < 0.5,
								tint = jitter_tint(rule.tint),
							},
						)
						break // one prop per tile
					}
				}
			}
		}
	}
}

// The trees and willows in the starting room. They are far too big to fit the
// ordinary clearance test, and they are not supposed to: drawn behind the
// tilemap, a tree reads as the forest still visible through the mouth of the
// mine, which is the same thing the parallax background is doing.
@(private = "file")
scatter_landmarks :: proc(g: ^Game, cell: [2]int) {
	a := &g.assets
	bounds := room_rect(cell)

	for i in 0 ..< 3 {
		kind := rand.float32() < 0.5 ? Prop_Kind.Tree : Prop_Kind.Willow
		tex := prop_texture(a, kind, rand.int_max(PROP_VARIANTS))
		if tex.id == 0 {
			continue
		}
		// Spread across the room but kept off the walls, so no trunk is sliced in
		// half by the room border.
		feet := rl.Vector2 {
			bounds.x + bounds.width * (0.2 + f32(i) * 0.3) + rand.float32_range(-24, 24),
			bounds.y + bounds.height - TILE * 2,
		}
		if prop_crowds_gameplay(g, feet, 20) {
			continue
		}
		append(
			&g.props,
			Prop {
				tex = tex,
				pos = feet,
				layer = .Behind,
				flip = rand.float32() < 0.5,
				tint = jitter_tint(LANDMARK_TINT),
			},
		)
	}
}

// A little variation per prop, so a row of the same sprite does not read as a
// repeated stamp.
@(private = "file")
jitter_tint :: proc(base: rl.Color) -> rl.Color {
	shift := rand.float32_range(0.88, 1.12)
	scale :: proc(v: u8, f: f32) -> u8 {
		return u8(clamp(f32(v) * f, 0, 255))
	}
	return {scale(base.r, shift), scale(base.g, shift), scale(base.b, shift), base.a}
}

// One layer's worth, culled to what the camera can see: a run holds well over a
// thousand props and only a room of them is ever on screen.
props_draw :: proc(g: ^Game, layer: Prop_Layer) {
	view := camera_view(g)
	for p in g.props {
		if p.layer != layer {
			continue
		}
		w, h := f32(p.tex.width), f32(p.tex.height)
		dest := rl.Rectangle{p.pos.x - w / 2, p.pos.y - h, w, h}
		if !rl.CheckCollisionRecs(dest, view) {
			continue
		}
		src := rl.Rectangle{0, 0, p.flip ? -w : w, h}
		rl.DrawTexturePro(p.tex, src, dest, {}, 0, p.tint)
	}
}
