package game

import "core:math"
import "core:math/rand"
import rl "vendor:raylib"

/*
Guns are rolled, not authored. A class fixes the feel — how fast it fires, how
many pellets, how far the shots carry — and a rarity scales the numbers and
picks the name. Chests hand out the result, so no two runs arm you the same way.
*/

Weapon_Class :: enum u8 {
	Pistol,
	SMG,
	Rifle,
	Shotgun,
	Sniper,
	Minigun,
	Launcher,
	Laser,
}

Weapon_Rarity :: enum u8 {
	Common,
	Uncommon,
	Rare,
	Epic,
	Legendary,
}

Weapon :: struct {
	class:     Weapon_Class,
	rarity:    Weapon_Rarity,
	prefix:    string, // the rolled half of the name; the class supplies the rest
	sprite:    rl.Rectangle, // where it lives on the gun sheet
	scale:     f32,
	damage:    f32,
	fire_time: f32, // seconds between shots
	pellets:   int,
	spread:    f32, // radians, half-angle
	speed:     f32,
	range:     f32, // world units before the shot fades out
	pierce:    int, // extra enemies a shot can pass through
	explosive: bool,
	knockback: f32,
	ammo:      int,
	ammo_max:  int,
	infinite:  bool,
	tint:      rl.Color, // the colour of its tracer
}

// Sprites picked out of assets/sprites/weapons/1.png by hand.
@(private = "file")
CLASS_SPRITES := [Weapon_Class][]rl.Rectangle {
	.Pistol   = {{0, 118, 12, 10}, {80, 118, 15, 10}},
	.SMG      = {{0, 99, 17, 13}, {96, 101, 21, 11}, {128, 100, 26, 12}, {160, 100, 27, 12}},
	.Rifle    = {{0, 83, 31, 13}, {32, 86, 30, 10}, {64, 85, 32, 11}},
	.Shotgun  = {{0, 53, 27, 11}, {32, 51, 27, 13}},
	.Sniper   = {{112, 50, 36, 14}, {160, 50, 48, 14}},
	.Minigun  = {{0, 68, 35, 12}},
	.Launcher = {{48, 65, 34, 15}},
	.Laser    = {{64, 48, 39, 16}},
}

// Which shot sheet a class fires. Several share one: what separates an SMG from
// a minigun is the rate of fire, not the round.
@(private = "file")
CLASS_ART := [Weapon_Class]Bullet_Art {
	.Pistol   = .Pistol,
	.SMG      = .Pistol,
	.Minigun  = .Pistol,
	.Rifle    = .Sniper,
	.Sniper   = .Sniper,
	.Shotgun  = .Shotgun,
	.Launcher = .Shotgun,
	.Laser    = .Laser,
}

weapon_art :: proc(c: Weapon_Class) -> Bullet_Art {
	return CLASS_ART[c]
}

@(private = "file")
CLASS_SCALE := [Weapon_Class]f32 {
	.Pistol   = 0.85,
	.SMG      = 0.70,
	.Rifle    = 0.60,
	.Shotgun  = 0.62,
	.Sniper   = 0.50,
	.Minigun  = 0.55,
	.Launcher = 0.55,
	.Laser    = 0.50,
}

weapon_class_name :: proc(c: Weapon_Class) -> string {
	switch c {
	case .Pistol:
		return "Pistol"
	case .SMG:
		return "SMG"
	case .Rifle:
		return "Rifle"
	case .Shotgun:
		return "Shotgun"
	case .Sniper:
		return "Sniper"
	case .Minigun:
		return "Minigun"
	case .Launcher:
		return "Launcher"
	case .Laser:
		return "Laser"
	}
	return "Gun"
}

RARITY_NAMES := [Weapon_Rarity]string {
	.Common    = "Common",
	.Uncommon  = "Uncommon",
	.Rare      = "Rare",
	.Epic      = "Epic",
	.Legendary = "Legendary",
}

RARITY_COLORS := [Weapon_Rarity]rl.Color {
	.Common    = {214, 222, 232, 255},
	.Uncommon  = {124, 224, 140, 255},
	.Rare      = {110, 178, 255, 255},
	.Epic      = {198, 130, 255, 255},
	.Legendary = {255, 190, 82, 255},
}

@(private = "file")
RARITY_PREFIXES := [Weapon_Rarity][]string {
	.Common    = {"Rusty", "Worn", "Chipped", "Plain"},
	.Uncommon  = {"Honed", "Tuned", "Sturdy", "Oiled"},
	.Rare      = {"Gilded", "Sharp", "Coiled", "Bright"},
	.Epic      = {"Runed", "Savage", "Eclipse", "Thorned"},
	.Legendary = {"Ancient", "Starfall", "Mossheart", "Godspark"},
}

@(private = "file")
Base_Stats :: struct {
	damage:    f32,
	fire_time: f32,
	pellets:   int,
	spread:    f32,
	speed:     f32,
	range:     f32,
	pierce:    int,
	explosive: bool,
	knockback: f32,
	ammo:      int,
	tint:      rl.Color,
}

@(private = "file")
CLASS_BASE := [Weapon_Class]Base_Stats {
	.Pistol = {
		damage = 8,
		fire_time = 0.26,
		pellets = 1,
		spread = 0.02,
		speed = 330,
		range = 260,
		knockback = 40,
		ammo = 0,
		tint = {255, 236, 158, 255},
	},
	.SMG = {
		damage = 6,
		fire_time = 0.085,
		pellets = 1,
		spread = 0.10,
		speed = 350,
		range = 240,
		knockback = 25,
		ammo = 170,
		tint = {150, 236, 255, 255},
	},
	.Rifle = {
		damage = 12,
		fire_time = 0.16,
		pellets = 1,
		spread = 0.04,
		speed = 400,
		range = 320,
		knockback = 55,
		ammo = 110,
		tint = {255, 192, 96, 255},
	},
	.Shotgun = {
		damage = 5,
		fire_time = 0.58,
		pellets = 6,
		spread = 0.30,
		speed = 300,
		range = 150,
		knockback = 90,
		ammo = 44,
		tint = {255, 148, 96, 255},
	},
	.Sniper = {
		damage = 34,
		fire_time = 0.85,
		pellets = 1,
		spread = 0.005,
		speed = 640,
		range = 520,
		pierce = 2,
		knockback = 120,
		ammo = 26,
		tint = {196, 150, 255, 255},
	},
	.Minigun = {
		damage = 4,
		fire_time = 0.045,
		pellets = 1,
		spread = 0.16,
		speed = 340,
		range = 220,
		knockback = 14,
		ammo = 320,
		tint = {255, 132, 132, 255},
	},
	.Launcher = {
		damage = 24,
		fire_time = 0.95,
		pellets = 1,
		spread = 0.02,
		speed = 235,
		range = 420,
		explosive = true,
		knockback = 150,
		ammo = 18,
		tint = {255, 138, 70, 255},
	},
	.Laser = {
		damage = 9,
		fire_time = 0.105,
		pellets = 1,
		spread = 0.01,
		speed = 720,
		range = 400,
		pierce = 1,
		knockback = 20,
		ammo = 140,
		tint = {128, 255, 190, 255},
	},
}

@(private = "file")
RARITY_POWER := [Weapon_Rarity]f32 {
	.Common    = 1.00,
	.Uncommon  = 1.16,
	.Rare      = 1.36,
	.Epic      = 1.62,
	.Legendary = 2.00,
}

// The starting sidearm: weak, but it never runs dry, so a run can never soft-lock
// on an empty gun.
weapon_starter :: proc() -> Weapon {
	w := weapon_build(.Pistol, .Common, 0)
	w.prefix = "Trusty"
	w.infinite = true
	return w
}

@(private = "file")
weapon_build :: proc(class: Weapon_Class, rarity: Weapon_Rarity, jitter: f32) -> Weapon {
	base := CLASS_BASE[class]
	power := RARITY_POWER[rarity]
	sprites := CLASS_SPRITES[class]

	// `jitter` is how much the individual rolls may wander, so two guns of the
	// same class and rarity still differ.
	roll :: proc(value, spread: f32) -> f32 {
		return value * rand.float32_range(1 - spread, 1 + spread)
	}

	return {
		class = class,
		rarity = rarity,
		prefix = rand.choice(RARITY_PREFIXES[rarity]),
		sprite = sprites[rand.int_max(len(sprites))],
		scale = CLASS_SCALE[class],
		damage = roll(base.damage * power, jitter),
		fire_time = roll(base.fire_time / math.sqrt(power), jitter * 0.5),
		pellets = base.pellets,
		spread = roll(base.spread, jitter * 0.6),
		speed = roll(base.speed, jitter * 0.3),
		range = roll(base.range * power, jitter * 0.3),
		pierce = base.pierce + (rarity >= .Epic ? 1 : 0),
		explosive = base.explosive,
		knockback = base.knockback * power,
		ammo = int(f32(base.ammo) * power),
		ammo_max = int(f32(base.ammo) * power),
		infinite = base.ammo == 0,
		tint = base.tint,
	}
}

// Rolls a fresh gun. Deeper rooms tilt the rarity table upward, so pushing
// further into the map is what pays for better loot.
weapon_roll :: proc(depth: int) -> Weapon {
	luck := rand.float32() + f32(depth) * 0.06

	rarity: Weapon_Rarity
	switch {
	case luck > 0.97:
		rarity = .Legendary
	case luck > 0.88:
		rarity = .Epic
	case luck > 0.70:
		rarity = .Rare
	case luck > 0.42:
		rarity = .Uncommon
	case:
		rarity = .Common
	}

	// The starter pistol class is left out: a chest should never feel like a
	// downgrade to what you already carry for free.
	class := Weapon_Class(1 + rand.int_max(len(Weapon_Class) - 1))
	return weapon_build(class, rarity, 0.18)
}

weapon_dps :: proc(w: Weapon) -> f32 {
	return w.damage * f32(w.pellets) / max(w.fire_time, 0.001)
}

// ------------------------------------------------------------------ drawing ---

// Guns are drawn from the grip so they pivot in the hand, and mirrored across
// their own barrel when aiming left so they never hang upside down.
@(private = "file")
GRIP :: rl.Vector2{3, 0.62} // x in pixels, y as a fraction of the sprite height

weapon_muzzle :: proc(w: Weapon, hand: rl.Vector2, angle: f32) -> rl.Vector2 {
	gx, gy := GRIP.x, w.sprite.height * GRIP.y
	off := rl.Vector2{w.sprite.width - gx, w.sprite.height * 0.34 - gy} * w.scale
	if abs(angle) > math.PI / 2 {
		off.y = -off.y
	}
	c, s := math.cos(angle), math.sin(angle)
	return hand + {off.x * c - off.y * s, off.x * s + off.y * c}
}

weapon_draw :: proc(w: Weapon, a: ^Assets, hand: rl.Vector2, angle: f32) {
	flip := abs(angle) > math.PI / 2
	src := w.sprite
	gy := w.sprite.height * GRIP.y
	if flip {
		src.height = -src.height
		gy = w.sprite.height - gy
	}
	dest := rl.Rectangle{hand.x, hand.y, w.sprite.width * w.scale, w.sprite.height * w.scale}
	origin := rl.Vector2{GRIP.x * w.scale, gy * w.scale}
	rl.DrawTexturePro(a.weapons, src, dest, origin, angle * math.DEG_PER_RAD, rl.WHITE)
}

// The floating version, used for a gun waiting to be picked up and for the
// weapon panel in the HUD.
weapon_draw_flat :: proc(w: Weapon, a: ^Assets, centre: rl.Vector2, scale: f32) {
	dest := rl.Rectangle {
		centre.x,
		centre.y,
		w.sprite.width * scale,
		w.sprite.height * scale,
	}
	origin := rl.Vector2{dest.width / 2, dest.height / 2}
	rl.DrawTexturePro(a.weapons, w.sprite, dest, origin, 0, rl.WHITE)
}
