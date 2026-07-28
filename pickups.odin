package game

import "core:math"
import rl "vendor:raylib"

Pickup_Kind :: enum u8 {
	Coin, // score
	Rune, // heals one heart
	Key, // opens the sealed boss room
}

Pickup :: struct {
	kind:  Pickup_Kind,
	pos:   rl.Vector2, // centre of the sprite
	taken: bool,
	phase: f32, // so a row of pickups does not bob in lockstep
	anim:  Animator,
}

pickup_make :: proc(kind: Pickup_Kind, pos: rl.Vector2) -> Pickup {
	return {kind = kind, pos = pos, phase = (pos.x * 0.07 + pos.y * 0.11)}
}

pickup_rect :: proc(p: Pickup) -> rl.Rectangle {
	return {p.pos.x - 8, p.pos.y - 8, 16, 16}
}

@(private = "file")
pickup_anim :: proc(a: ^Assets, kind: Pickup_Kind) -> ^Anim {
	switch kind {
	case .Coin:
		return &a.coin
	case .Rune:
		return &a.rune
	case .Key:
		return &a.key
	}
	return &a.coin
}

pickup_update :: proc(p: ^Pickup, a: ^Assets, dt: f32) {
	if p.taken {
		return
	}
	p.phase += dt
	animator_play(&p.anim, pickup_anim(a, p.kind))
	animator_update(&p.anim, dt)
}

pickup_draw :: proc(p: Pickup, a: ^Assets) {
	if p.taken {
		return
	}
	pos := p.pos + {0, math.sin(p.phase * 3) * 1.5}

	if p.kind != .Coin {
		// Runes and the key are worth spotting from a distance.
		colour := p.kind == .Key ? rl.Color{255, 214, 110, 255} : rl.Color{150, 240, 160, 255}
		rl.BeginBlendMode(.ADDITIVE)
		colour.a = 36
		rl.DrawCircleV(pos, 11 + math.sin(p.phase * 3) * 1.5, colour)
		rl.EndBlendMode()
	}

	// The animations are anchored at the bottom of their cell, and these all
	// float, so they are drawn from their centre instead.
	anim := p.anim.anim
	if anim == nil {
		return
	}
	anim_draw_frame(anim, p.anim.frame, pos + {0, anim.frame_h / 2}, false)
}

// Runs the "did the player walk into it" check for every pickup.
pickups_collect :: proc(g: ^Game) {
	if g.player.dead {
		return
	}
	pr := player_rect(g.player)

	for &p in g.pickups {
		if p.taken || !rl.CheckCollisionRecs(pr, pickup_rect(p)) {
			continue
		}
		switch p.kind {
		case .Coin:
			p.taken = true
			g.player.coins += 1
			spawn_burst(g, p.pos, {255, 214, 110, 255}, 6, 110, 1.1)
			play(&g.assets, .Coin)
		case .Rune:
			// Only consumed if it can actually heal something.
			if player_heal(&g.player) {
				p.taken = true
				spawn_burst(g, p.pos, {150, 240, 160, 255}, 12, 130, 1.4)
				play(&g.assets, .Power_Up)
			}
		case .Key:
			p.taken = true
			g.player.has_key = true
			world_unlock_gates(&g.world, &g.map_tiles)
			g.notice = "KEY TAKEN - THE SEALED DOOR IS OPEN"
			g.notice_timer = 3.5
			g.shake = max(g.shake, 5)
			spawn_burst(g, p.pos, {255, 214, 110, 255}, 24, 180, 1.8)
			play(&g.assets, .Power_Up)
		}
	}
}
