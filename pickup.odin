package game

import "core:math"
import rl "vendor:raylib"

Pickup_Kind :: enum {
	Coin,
	Fruit,
}

Pickup :: struct {
	pos:     rl.Vector2, // bottom centre of the sprite cell
	kind:    Pickup_Kind,
	variant: int, // which fruit; unused for coins
	taken:   bool,
	phase:   f32, // so a row of pickups does not bob in lockstep
	anim:    Animator,
}

// The fruit sheet is a 4x4 grid but only the first three columns hold artwork.
FRUIT_VARIANTS := [?]int{0, 1, 2, 4, 5, 6, 8, 9, 10, 12, 13, 14}
HEART_FRUIT :: 12 // the red apple, reused as the health icon in the HUD

pickup_make :: proc(kind: Pickup_Kind, tx, ty: int) -> Pickup {
	pos := rl.Vector2{f32(tx) * TILE + TILE / 2, f32(ty) * TILE + TILE}
	p := Pickup {
		pos     = pos,
		kind    = kind,
		phase   = f32((tx * 7 + ty * 13) % 16) * 0.4,
		variant = FRUIT_VARIANTS[(tx * 5 + ty * 3) % len(FRUIT_VARIANTS)],
	}
	return p
}

pickup_rect :: proc(p: Pickup) -> rl.Rectangle {
	return {p.pos.x - 6, p.pos.y - 14, 12, 12}
}

pickup_update :: proc(p: ^Pickup, a: ^Assets, dt: f32) {
	if p.taken {
		return
	}
	p.phase += dt
	if p.kind == .Coin {
		animator_play(&p.anim, &a.coin, CLIP_COIN_SPIN)
		animator_update(&p.anim, dt)
	}
}

pickup_draw :: proc(p: Pickup, a: ^Assets) {
	if p.taken {
		return
	}
	bob := rl.Vector2{0, math.sin(p.phase * 3) * 1.5}
	switch p.kind {
	case .Coin:
		animator_draw(p.anim, p.pos + bob, false)
	case .Fruit:
		sheet_draw(a.fruit, p.variant, p.pos + bob, false)
	}
}
