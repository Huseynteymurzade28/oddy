package game

import rl "../libs/raylib"

/*
How the Hollow changes as it goes down. Every room belongs to one of three
zones, picked from how far it is from the start, and a zone is mostly a mood:
how dark it is and what colour the dark is, how the rock is tinted, what
drifts through the air, and what grows on the walls.

  Mossy    the upper galleries, still close enough to the surface for roots
           and fireflies. The brightest of the three.
  Drowned  the flooded middle: cold blue rock, dripping ceilings, crystals.
  Ember    the deep. Red rock, rising embers, and the water there is not water
           any more. The vault is always down here.
*/

Zone :: enum u8 {
	Mossy,
	Drowned,
	Ember,
}

Zone_Look :: struct {
	ambient:    rl.Color, // what an unlit tile is multiplied by
	rock:       rl.Color, // tint over the tileset
	background: rl.Color, // tint over the parallax forest
	liquid:     rl.Color, // tint over the water tiles
	mote:       rl.Color, // the drifting particles
	accent:     rl.Color, // torches, crystals: the colour of local light
}

ZONE_LOOKS := [Zone]Zone_Look {
	.Mossy = {
		ambient    = {214, 224, 196, 255},
		rock       = {255, 255, 255, 255},
		background = {255, 255, 236, 255},
		liquid     = {220, 250, 255, 210},
		mote       = {236, 255, 140, 255},
		accent     = {255, 206, 120, 255},
	},
	.Drowned = {
		ambient    = {168, 196, 230, 255},
		rock       = {255, 255, 255, 255},
		background = {176, 214, 250, 255},
		liquid     = {170, 220, 255, 220},
		mote       = {150, 210, 255, 255},
		accent     = {120, 220, 255, 255},
	},
	.Ember = {
		ambient    = {212, 170, 160, 255},
		rock       = {255, 255, 255, 255},
		background = {245, 168, 140, 255},
		liquid     = {255, 120, 50, 245}, // lava
		mote       = {255, 150, 70, 255},
		accent     = {255, 120, 70, 255},
	},
}

// Splits the run into thirds by depth. The vault and the key are always in the
// deep, so the last stretch of a run always feels like the last stretch.
zone_for :: proc(role: Room_Role, depth, deepest: int) -> Zone {
	#partial switch role {
	case .Boss, .Key:
		return .Ember
	case .Start:
		return .Mossy
	}
	switch {
	case depth * 3 <= deepest:
		return .Mossy
	case depth * 3 <= deepest * 2:
		return .Drowned
	}
	return .Ember
}

// The zone of whatever room a world position falls in.
zone_at :: proc(w: ^World, pos: rl.Vector2) -> Zone {
	cell := room_coords(pos)
	if room := room_at(w, cell.x, cell.y); room != nil {
		return room.zone
	}
	return .Mossy
}

zone_of_tile :: proc(w: ^World, tx, ty: int) -> Zone {
	if room := room_at(w, tx / ROOM_W, ty / ROOM_H); room != nil {
		return room.zone
	}
	return .Mossy
}

lerp_color :: proc(a, b: rl.Color, t: f32) -> rl.Color {
	l :: proc(x, y: u8, t: f32) -> u8 {
		return u8(clamp(f32(x) + (f32(y) - f32(x)) * t, 0, 255))
	}
	return {l(a.r, b.r, t), l(a.g, b.g, t), l(a.b, b.b, t), l(a.a, b.a, t)}
}

mul_color :: proc(a, b: rl.Color) -> rl.Color {
	return {
		u8(u32(a.r) * u32(b.r) / 255),
		u8(u32(a.g) * u32(b.g) / 255),
		u8(u32(a.b) * u32(b.b) / 255),
		u8(u32(a.a) * u32(b.a) / 255),
	}
}
