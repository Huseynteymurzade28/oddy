package game

import "core:math"
import rl "../libs/raylib"

/*
Small marks drawn into the world, over the lighting, that tell you what the
game is about to do: where the gun is pointed, what it picked to shoot at, and
which bits of floor you can drop through.

On a phone the thumb is never on the target, so without these you would only
find out where a shot was going by watching it go there.
*/

// A dotted line from the muzzle to the first rock in the way, while a thumb is
// aiming; a pair of brackets round whatever the gun picked by itself.
draw_aim_guide :: proc(g: ^Game) {
	when !TOUCH_CONTROLS {
		return
	}
	p := &g.player
	if p.dead || g.state != .Playing {
		return
	}

	if g.input.has_dir {
		hand := player_hand(p^)
		dir := rl.Vector2{math.cos(p.aim), math.sin(p.aim)}
		start := weapon_muzzle(p.weapon, hand, p.aim)
		reach := min(p.weapon.range, 190)
		step: f32 = 7
		march := math.mod(g.time * 40, step) // the dots creep outward
		for d := step - march; d < reach; d += step {
			at := start + dir * d
			tx := int(math.floor(at.x / TILE))
			ty := int(math.floor(at.y / TILE))
			if is_blocking(tile_at(&g.map_tiles, tx, ty)) {
				// Where it would hit: a small burst so the end is unmistakable.
				rl.DrawCircleV(at, 3, {255, 236, 160, 220})
				rl.DrawCircleV(at, 1.5, {255, 255, 255, 255})
				break
			}
			fade := 1 - d / reach
			rl.DrawCircleV(at, 1.6, {255, 240, 190, u8(80 + 170 * fade)})
		}
	}

	if p.has_target {
		t := p.aim_target
		r: f32 = 9 + math.sin(g.time * 10) * 1.2
		c := rl.Color{255, 120, 90, 230}
		// Four corner brackets, turning slowly.
		for i in 0 ..< 4 {
			a := g.time * 1.5 + f32(i) * math.PI / 2
			corner := t + rl.Vector2{math.cos(a), math.sin(a)} * r
			along := rl.Vector2{math.cos(a + math.PI * 0.75), math.sin(a + math.PI * 0.75)} * 4
			across := rl.Vector2{math.cos(a - math.PI * 0.75), math.sin(a - math.PI * 0.75)} * 4
			rl.DrawLineEx(corner, corner + along, 1.2, c)
			rl.DrawLineEx(corner, corner + across, 1.2, c)
		}
	}
}

// Chevrons bobbing over every trapdoor in the room you are in, so it is clear
// the floor there gives way when you hold down.
draw_trapdoor_hints :: proc(g: ^Game) {
	room := room_at(&g.world, g.room.x, g.room.y)
	if room == nil || .South not_in room.doors || room.role == .Boss {
		return
	}
	ox := f32(g.room.x * ROOM_W) * TILE
	oy := f32(g.room.y * ROOM_H) * TILE
	centre := rl.Vector2{ox + (DOOR_X + DOOR_W / 2) * TILE, oy + (ROOM_H - 2) * TILE - 10}
	bob := math.sin(g.time * 4) * 2
	for i in 0 ..< 2 {
		y := centre.y + bob + f32(i) * 5
		alpha := u8(110 + 70 * math.sin(g.time * 4 - f32(i)))
		c := rl.Color{255, 230, 150, alpha}
		rl.DrawLineEx({centre.x - 5, y - 3}, {centre.x, y + 1}, 1.5, c)
		rl.DrawLineEx({centre.x, y + 1}, {centre.x + 5, y - 3}, 1.5, c)
	}
}
