package game

import "core:math"
import rl "vendor:raylib"

/*
A chest is the only way to change weapons. Opening one rolls a gun on the spot,
which then hovers above the lid until you take it — that pause is deliberate, so
you get to read what it is before deciding whether it beats what you carry.
*/

CHEST_REACH :: 26.0

Chest :: struct {
	pos:    rl.Vector2, // at the feet
	opened: bool,
	taken:  bool,
	loot:   Weapon,
	bob:    f32,
	anim:   Animator,
}

chest_make :: proc(pos: rl.Vector2) -> Chest {
	return {pos = pos}
}

chest_rect :: proc(c: Chest) -> rl.Rectangle {
	return {c.pos.x - 12, c.pos.y - 18, 24, 18}
}

// The point the floating gun hovers at once the chest is open.
chest_loot_pos :: proc(c: Chest) -> rl.Vector2 {
	return {c.pos.x, c.pos.y - 30 + math.sin(c.bob * 2) * 2}
}

chest_in_reach :: proc(c: Chest, p: Player) -> bool {
	return rl.Vector2Distance(player_centre(p), {c.pos.x, c.pos.y - 8}) < CHEST_REACH
}

chest_update :: proc(g: ^Game, index: int, dt: f32) {
	c := &g.chests[index]
	c.bob += dt
	animator_play(&c.anim, &g.assets.chest)
	if c.opened {
		animator_update(&c.anim, dt)
	}
}

// Handles the E key for whichever chest the player is standing next to.
chests_interact :: proc(g: ^Game) {
	if g.player.dead {
		return
	}
	for &c, i in g.chests {
		if c.taken || !chest_in_reach(c, g.player) {
			continue
		}
		if !c.opened {
			c.opened = true
			c.loot = weapon_roll(g.world.rooms[room_coords(c.pos).y][room_coords(c.pos).x].depth)
			animator_restart(&c.anim, &g.assets.chest)
			spawn_burst(g, chest_loot_pos(c), RARITY_COLORS[c.loot.rarity], 18, 130, 1.5)
			play(&g.assets, .Power_Up)
		} else {
			c.taken = true
			player_take_weapon(g, c.loot)
			spawn_burst(g, chest_loot_pos(c), RARITY_COLORS[c.loot.rarity], 12, 150, 1.4)
		}
		return
	}
	_ = g
}

chest_draw :: proc(c: Chest, a: ^Assets, time: f32) {
	frame := c.opened ? c.anim.frame : 0
	anim_draw_frame(&a.chest, frame, c.pos, false)

	if !c.opened || c.taken {
		return
	}

	pos := chest_loot_pos(c)
	colour := RARITY_COLORS[c.loot.rarity]

	// A soft pool of the rarity colour under the gun, so a legendary is visible
	// from across the room.
	rl.BeginBlendMode(.ADDITIVE)
	glow := colour
	glow.a = 40
	rl.DrawCircleV(pos, 13 + math.sin(time * 3) * 1.5, glow)
	glow.a = 26
	rl.DrawCircleV(pos, 20, glow)
	rl.EndBlendMode()

	weapon_draw_flat(c.loot, a, pos, 0.8)
}
