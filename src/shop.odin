package game

import "core:math"
import "core:math/rand"
import rl "vendor:raylib"

/*
One stall per run, in a room of its own. Three crates on the floor, one thing
standing on each, and a sign hanging over them.

This is what coins are for. Everything else in a run is found; the stall is the
only place a run makes you choose, because the money never covers all three. So
the offers are deliberately different in kind rather than in size: a heart is
survival now, a heart container and a trigger job are survival later, a gun is
damage, and ammo is what keeps a gun you already like alive. Whatever you skip
is gone — the stall does not restock, and the run does not come back.
*/

SHOP_SLOTS :: 3
SHOP_REACH :: 20.0
SHOP_SLOT_GAP :: 30.0 // horizontal spacing between crates

Shop_Kind :: enum u8 {
	Weapon, // a rolled gun, priced by its rarity
	Heart, // heals one heart
	Vessel, // +1 maximum health, and fills it
	Ammo, // refills the gun in hand
	Trigger, // permanently faster fire, for the rest of the run
}

TRIGGER_BONUS :: 0.15 // fraction of fire rate a trigger job adds

@(private = "file")
PRICES := [Shop_Kind]int {
	.Weapon  = 0, // set from the rolled rarity instead
	.Heart   = 10,
	.Vessel  = 30,
	.Ammo    = 12,
	.Trigger = 24,
}

@(private = "file")
WEAPON_PRICES := [Weapon_Rarity]int {
	.Common    = 12,
	.Uncommon  = 18,
	.Rare      = 26,
	.Epic      = 34,
	.Legendary = 44,
}

Shop_Item :: struct {
	kind:  Shop_Kind,
	price: int,
	sold:  bool,
	loot:  Weapon, // only meaningful for .Weapon
	pos:   rl.Vector2, // the top of the crate this stands on
	crate: rl.Vector2, // the feet of the crate itself
	box:   int, // which crate sprite
	bob:   f32,
}

Shop :: struct {
	open:  bool, // false when a run has no stall room at all
	pos:   rl.Vector2, // the feet of the middle crate
	items: [SHOP_SLOTS]Shop_Item,
	sign:  int, // which pointer sprite hangs over the stall
}

// Builds the stall at a spot on the floor. `depth` tilts the gun it puts out, the
// same way a chest in that room would be tilted.
shop_make :: proc(pos: rl.Vector2, depth: int) -> Shop {
	s := Shop {
		open = true,
		pos  = pos,
		sign = rand.int_max(8),
	}

	// The first slot is always a gun: it is the offer that makes the room worth
	// walking into, and it is the one that changes most between runs.
	kinds: [SHOP_SLOTS]Shop_Kind
	kinds[0] = .Weapon

	// The other two are drawn without repeats, so the stall never sells the same
	// thing twice and every visit presents three real alternatives.
	pool := [?]Shop_Kind{.Heart, .Vessel, .Ammo, .Trigger}
	rand.shuffle(pool[:])
	kinds[1] = pool[0]
	kinds[2] = pool[1]

	for i in 0 ..< SHOP_SLOTS {
		item := &s.items[i]
		item.kind = kinds[i]
		item.box = rand.int_max(6)
		item.bob = rand.float32_range(0, math.TAU)
		item.crate = pos + {f32(i - 1) * SHOP_SLOT_GAP, 0}
		item.pos = item.crate - {0, CRATE_H}

		if item.kind == .Weapon {
			item.loot = weapon_roll(depth)
			item.price = WEAPON_PRICES[item.loot.rarity]
		} else {
			item.price = PRICES[item.kind]
		}
	}
	return s
}

// Crates are a little under two tiles tall; the goods stand on top of them.
@(private = "file")
CRATE_H :: 26.0

// The sign hangs close enough over the crates to read as part of the same stall,
// and no closer, or it sits on the goods.
@(private = "file")
SIGN_GAP :: 18.0

shop_item_pos :: proc(item: Shop_Item, time: f32) -> rl.Vector2 {
	return item.pos + {0, -10 + math.sin(time * 2 + item.bob) * 1.5}
}

// Which slot the player is standing at, or -1. Only the nearest one counts, so
// standing between two crates never offers both at once.
shop_slot_in_reach :: proc(s: Shop, p: Player) -> int {
	if !s.open {
		return -1
	}
	best, best_dist := -1, f32(SHOP_REACH)
	for i in 0 ..< SHOP_SLOTS {
		if s.items[i].sold {
			continue
		}
		d := abs(player_centre(p).x - s.items[i].crate.x)
		if abs(player_centre(p).y - s.items[i].crate.y) > 34 {
			continue
		}
		if d < best_dist {
			best, best_dist = i, d
		}
	}
	return best
}

// What the sign says, and what it costs.
shop_item_name :: proc(item: Shop_Item) -> string {
	switch item.kind {
	case .Weapon:
		return "GUN"
	case .Heart:
		return "MEND ONE HEART"
	case .Vessel:
		return "HEART CONTAINER"
	case .Ammo:
		return "FULL MAGAZINE"
	case .Trigger:
		return "TRIGGER JOB"
	}
	return "GOODS"
}

// The second line of the prompt: what the thing actually does.
shop_item_detail :: proc(item: Shop_Item) -> string {
	switch item.kind {
	case .Weapon:
		return "" // the weapon panel says everything already
	case .Heart:
		return "ONE HEART BACK"
	case .Vessel:
		return "+1 MAX HEART, FOR THIS RUN"
	case .Ammo:
		return "REFILL WHAT YOU CARRY"
	case .Trigger:
		return "+15% FIRE RATE, FOR THIS RUN"
	}
	return ""
}

// Whether buying would do anything at all. A full-health player buying a heart,
// or an unlimited sidearm buying ammo, would be throwing coins away — so the
// stall refuses instead, and the prompt says why.
shop_item_useless :: proc(item: Shop_Item, p: Player) -> (string, bool) {
	switch item.kind {
	case .Heart:
		if p.health >= p.max_health {
			return "ALREADY WHOLE", true
		}
	case .Vessel:
		if p.max_health >= HEALTH_CAP {
			return "NO ROOM FOR ANOTHER", true
		}
	case .Ammo:
		if p.weapon.infinite {
			return "THE SIDEARM NEVER RUNS DRY", true
		}
		if p.weapon.ammo >= p.weapon.ammo_max {
			return "ALREADY FULL", true
		}
	case .Weapon, .Trigger:
	}
	return "", false
}

// Handles the E key at the stall. Returns whether it consumed the press, so the
// same key can still open chests everywhere else.
shop_interact :: proc(g: ^Game) -> bool {
	if g.player.dead {
		return false
	}
	slot := shop_slot_in_reach(g.shop, g.player)
	if slot < 0 {
		return false
	}
	item := &g.shop.items[slot]

	if _, useless := shop_item_useless(item^, g.player); useless {
		return true // the prompt is already explaining itself
	}
	if g.player.coins < item.price {
		g.notice = "NOT ENOUGH COINS"
		g.notice_timer = 1.6
		return true
	}

	g.player.coins -= item.price
	item.sold = true
	pos := shop_item_pos(item^, g.time)

	switch item.kind {
	case .Weapon:
		player_take_weapon(g, item.loot)
		spawn_burst(g, pos, RARITY_COLORS[item.loot.rarity], 16, 150, 1.5)
		return true
	case .Heart:
		player_heal(&g.player)
		g.notice = "A HEART MENDED"
	case .Vessel:
		player_add_heart(&g.player)
		g.notice = "ONE MORE HEART TO LOSE"
	case .Ammo:
		g.player.weapon.ammo = g.player.weapon.ammo_max
		g.notice = "MAGAZINE FULL"
	case .Trigger:
		g.player.fire_rate += TRIGGER_BONUS
		g.notice = "THE TRIGGER RUNS LIGHTER NOW"
	}

	g.notice_timer = 2.4
	spawn_burst(g, pos, SHOP_COLORS[item.kind], 14, 140, 1.4)
	play(&g.assets, .Power_Up)
	return true
}

SHOP_COLORS := [Shop_Kind]rl.Color {
	.Weapon  = {236, 200, 110, 255},
	.Heart   = {228, 78, 92, 255},
	.Vessel  = {255, 120, 150, 255},
	.Ammo    = {236, 214, 130, 255},
	.Trigger = {150, 236, 255, 255},
}

// --------------------------------------------------------------------- drawing ---

shop_draw :: proc(g: ^Game) {
	s := &g.shop
	if !s.open {
		return
	}
	a := &g.assets

	// The sign first, so the crates overlap its post rather than the other way
	// round.
	sign := prop_texture(a, .Pointer, s.sign)
	if sign.id != 0 {
		rl.DrawTextureV(
			sign,
			{s.pos.x - f32(sign.width) / 2, s.pos.y - CRATE_H - SIGN_GAP - f32(sign.height)},
			rl.WHITE,
		)
	}

	for i in 0 ..< SHOP_SLOTS {
		item := s.items[i]
		crate := prop_texture(a, .Box, item.box)
		if crate.id != 0 {
			rl.DrawTextureV(
				crate,
				{item.crate.x - f32(crate.width) / 2, item.crate.y - f32(crate.height)},
				item.sold ? rl.Color{130, 124, 140, 255} : rl.WHITE,
			)
		}
		if !item.sold {
			shop_draw_goods(g, item)
		}
	}
}

// What stands on a crate. Guns get their own sprite; the rest are small icons
// drawn here, since the pack has no art for them.
@(private = "file")
shop_draw_goods :: proc(g: ^Game, item: Shop_Item) {
	pos := shop_item_pos(item, g.time)
	colour := SHOP_COLORS[item.kind]

	// A pool of the item's colour underneath, the same trick the chests use, so a
	// stall reads as lit from across the room.
	rl.BeginBlendMode(.ADDITIVE)
	glow := colour
	glow.a = 34
	rl.DrawCircleV(pos, 11 + math.sin(g.time * 3 + item.bob) * 1.5, glow)
	glow.a = 22
	rl.DrawCircleV(pos, 17, glow)
	rl.EndBlendMode()

	switch item.kind {
	case .Weapon:
		weapon_draw_flat(item.loot, &g.assets, pos, 0.7)
	case .Heart, .Vessel:
		// Two circles and a triangle, the same heart the HUD draws.
		rl.DrawCircleV(pos + {-2, -1.5}, 2.6, colour)
		rl.DrawCircleV(pos + {2, -1.5}, 2.6, colour)
		rl.DrawTriangle(pos + {-4.4, -1}, pos + {0, 4.6}, pos + {4.4, -1}, colour)
		if item.kind == .Vessel {
			rl.DrawCircleLinesV(pos, 8, {255, 220, 230, 160})
		}
	case .Ammo:
		// A stubby magazine.
		rl.DrawRectangleV(pos + {-3, -4}, {6, 9}, colour)
		rl.DrawRectangleV(pos + {-2, -6}, {4, 2}, {90, 80, 60, 255})
	case .Trigger:
		// A cog: a ring with four teeth.
		rl.DrawCircleLinesV(pos, 5, colour)
		rl.DrawCircleV(pos, 1.6, colour)
		for k in 0 ..< 4 {
			ang := f32(k) * math.TAU / 4 + g.time
			d := rl.Vector2{math.cos(ang), math.sin(ang)}
			rl.DrawLineV(pos + d * 5, pos + d * 7.5, colour)
		}
	}
}
