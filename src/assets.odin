package game

import rl "vendor:raylib"

/*
Everything the game loads lives here, and the layout of `assets/` mirrors the
layout of this file: one folder per thing that owns a set of sprites. Nothing
else in the code opens a file, so moving or replacing art is a one-file change.
*/

Sfx :: enum {
	Coin,
	Jump,
	Hurt,
	Power_Up,
	Explode,
	Shoot,
}

Player_Anims :: struct {
	idle:        Anim,
	run:         Anim,
	jump:        Anim,
	fall:        Anim,
	double_jump: Anim,
	wall_slide:  Anim,
	hit:         Anim,
}

// Every creature in the pack ships the same five states, so one struct covers
// all of them. Creatures without a distinct walk or attack simply point two
// fields at the same file.
Creature_Anims :: struct {
	idle:   Anim,
	run:    Anim,
	attack: Anim,
	hit:    Anim,
	death:  Anim,
}

// The golem is the only enemy that changes form mid-fight, so it gets a full
// second set of animations for its unarmoured phase.
Golem_Anims :: struct {
	armor:  Creature_Anims,
	broken: Creature_Anims,
	slam:   Anim, // the unarmoured wind-up that throws shockwaves
}

// `assets/sprites/objects/` splits two ways: `animated/` holds sprite sheets that
// play, and the rest are folders of numbered still images used as scenery. A kind
// is a folder, so a room can pick a variant without the code naming every file.
Prop_Kind :: enum u8 {
	Grass,
	Bush,
	Stone,
	Ridge,
	Fence,
	Box,
	Tree,
	Willow,
	Ladder,
	Pointer,
}

PROP_VARIANTS :: 10

Prop_Set :: struct {
	tex:   [PROP_VARIANTS]rl.Texture2D,
	count: int,
}

Assets :: struct {
	player:  Player_Anims,
	enemy:   [Enemy_Kind]Creature_Anims,
	golem:   Golem_Anims,
	bullets: [Bullet_Art]Anim,
	chest:   Anim,
	coin:    Anim,
	key:     Anim,
	rune:    Anim,
	flag:    Anim,
	props:   [Prop_Kind]Prop_Set,
	tileset: rl.Texture2D,
	weapons: rl.Texture2D,
	layers:  [BG_LAYERS]rl.Texture2D,
	font:    rl.Font,
	sfx:     [Sfx]rl.Sound,
	music:   rl.Music,
}

BG_LAYERS :: 5

// Which folder each prop kind reads, and how many variants are in it.
@(private = "file")
PROP_SOURCE := [Prop_Kind]struct {
	folder: cstring,
	count:  int,
} {
	.Grass   = {"grass", 10},
	.Bush    = {"bushes", 9},
	.Stone   = {"stones", 5},
	.Ridge   = {"ridges", 6},
	.Fence   = {"fence", 3},
	.Box     = {"boxes", 6},
	.Tree    = {"trees", 3},
	.Willow  = {"willows", 3},
	.Ladder  = {"ladders", 6},
	.Pointer = {"pointers", 8},
}

// Creature sheets are 64x64 cells with the artwork padded inside them, so each
// one needs to say how far down its cell the ground line sits.
@(private = "file")
GROUND :: f32(48)

assets_load :: proc(a: ^Assets) {
	P :: "assets/sprites/player/"
	a.player = {
		idle        = anim_load(P + "idle.png", 32, 32, 11, 0.12, true),
		run         = anim_load(P + "run.png", 32, 32, 12, 0.06, true),
		jump        = anim_load(P + "jump.png", 32, 32, 1),
		fall        = anim_load(P + "fall.png", 32, 32, 1),
		double_jump = anim_load(P + "double_jump.png", 32, 32, 6, 0.05),
		wall_slide  = anim_load(P + "wall_slide.png", 32, 32, 5, 0.10, true),
		hit         = anim_load(P + "hit.png", 32, 32, 7, 0.05),
	}

	R :: "assets/sprites/enemies/rat/"
	a.enemy[.Rat] = {
		idle   = anim_load(R + "idle.png", 64, 64, 4, 0.15, true, GROUND),
		run    = anim_load(R + "run.png", 64, 64, 6, 0.07, true, GROUND),
		attack = anim_load(R + "attack.png", 64, 64, 8, 0.06, false, GROUND),
		hit    = anim_load(R + "hit.png", 64, 64, 4, 0.06, false, GROUND),
		death  = anim_load(R + "death.png", 64, 64, 5, 0.09, false, GROUND),
	}

	S :: "assets/sprites/enemies/slime/"
	a.enemy[.Slime] = {
		idle   = anim_load(S + "idle.png", 64, 64, 4, 0.16, true, GROUND),
		run    = anim_load(S + "run.png", 64, 64, 4, 0.10, true, GROUND),
		attack = anim_load(S + "attack.png", 64, 64, 8, 0.07, false, GROUND),
		hit    = anim_load(S + "hit.png", 64, 64, 4, 0.06, false, GROUND),
		death  = anim_load(S + "death.png", 64, 64, 6, 0.08, false, GROUND),
	}

	C :: "assets/sprites/enemies/crab/"
	a.enemy[.Crab] = {
		idle   = anim_load(C + "idle.png", 64, 64, 4, 0.16, true, GROUND),
		run    = anim_load(C + "run.png", 64, 64, 6, 0.08, true, GROUND),
		attack = anim_load(C + "attack.png", 64, 64, 10, 0.06, false, GROUND),
		hit    = anim_load(C + "hit.png", 64, 64, 3, 0.07, false, GROUND),
		death  = anim_load(C + "death.png", 64, 64, 5, 0.09, false, GROUND),
	}

	// The bat and the skull hover, so their ground line is the bottom of the
	// body rather than the bottom of the cell.
	B :: "assets/sprites/enemies/bat/"
	bat_fly := anim_load(B + "fly.png", 64, 64, 4, 0.08, true, 43)
	a.enemy[.Bat] = {
		idle   = bat_fly,
		run    = bat_fly,
		attack = anim_load(B + "attack.png", 64, 64, 7, 0.06, false, 43),
		hit    = anim_load(B + "hit.png", 64, 64, 5, 0.06, false, 43),
		death  = anim_load(B + "death.png", 64, 64, 11, 0.06, false, 43),
	}

	K :: "assets/sprites/enemies/skull/"
	skull_fly := anim_load(K + "fly.png", 64, 64, 8, 0.08, true, 39)
	a.enemy[.Skull] = {
		idle   = anim_load(K + "idle.png", 64, 64, 4, 0.15, true, 39),
		run    = skull_fly,
		attack = skull_fly,
		hit    = anim_load(K + "hit.png", 64, 64, 4, 0.06, false, 39),
		death  = anim_load(K + "death.png", 64, 64, 10, 0.07, false, 39),
	}

	E :: "assets/sprites/enemies/pebble/"
	pebble_run := anim_load(E + "run.png", 64, 64, 5, 0.08, true, 37)
	a.enemy[.Pebble] = {
		idle   = anim_load(E + "idle.png", 64, 64, 4, 0.16, true, 37),
		run    = pebble_run,
		attack = pebble_run,
		hit    = anim_load(E + "hit.png", 64, 64, 5, 0.06, false, 37),
		death  = anim_load(E + "death.png", 64, 64, 7, 0.07, false, 37),
	}

	G :: "assets/sprites/enemies/golem/"
	a.golem = {
		armor = {
			idle = anim_load(G + "armor_idle.png", 64, 64, 4, 0.16, true, GROUND),
			run = anim_load(G + "armor_run.png", 64, 64, 4, 0.12, true, GROUND),
			attack = anim_load(G + "armor_attack.png", 64, 64, 11, 0.06, false, GROUND),
			hit = anim_load(G + "armor_hit.png", 64, 64, 5, 0.06, false, GROUND),
			// The armour coming apart is the armoured phase's "death": it plays
			// when that half of the health bar runs out, and the broken set takes
			// over once it finishes.
			death = anim_load(G + "armor_break.png", 64, 64, 5, 0.10, false, GROUND),
		},
		broken = {
			idle = anim_load(G + "idle.png", 64, 64, 4, 0.16, true, GROUND),
			run = anim_load(G + "run.png", 64, 64, 4, 0.12, true, GROUND),
			attack = anim_load(G + "attack.png", 64, 64, 12, 0.05, false, GROUND),
			hit = anim_load(G + "hit.png", 64, 64, 5, 0.06, false, GROUND),
			death = anim_load(G + "death.png", 64, 64, 9, 0.10, false, GROUND),
		},
		slam = anim_load(G + "slam.png", 64, 64, 7, 0.07, false, GROUND),
	}

	// One strip per shot type — barrel, flight, impact — laid out left to right.
	// BULLET_ART says which frames mean what.
	U :: "assets/sprites/bullets/"
	a.bullets[.Pistol] = anim_load(U + "pistol.png", 12, 8, 8, SHOT_FRAME_TIME)
	a.bullets[.Sniper] = anim_load(U + "sniper.png", 16, 22, 6, SHOT_FRAME_TIME)
	a.bullets[.Shotgun] = anim_load(U + "shotgun.png", 20, 28, 7, SHOT_FRAME_TIME)
	a.bullets[.Laser] = anim_load(U + "laser.png", 40, 22, 9, SHOT_FRAME_TIME)

	O :: "assets/sprites/objects/animated/"
	a.chest = anim_load(O + "chest.png", 32, 32, 4, 0.09)
	a.coin = anim_load(O + "coin.png", 10, 10, 4, 0.09, true)
	a.key = anim_load(O + "key.png", 12, 8, 4, 0.12, true)
	a.rune = anim_load(O + "rune.png", 16, 16, 4, 0.12, true)
	a.flag = anim_load(O + "flag.png", 48, 48, 4, 0.15, true)

	for kind in Prop_Kind {
		src := PROP_SOURCE[kind]
		a.props[kind].count = min(src.count, PROP_VARIANTS)
		for i in 0 ..< a.props[kind].count {
			path := rl.TextFormat("assets/sprites/objects/%s/%d.png", src.folder, i32(i + 1))
			a.props[kind].tex[i] = rl.LoadTexture(path)
		}
	}

	a.tileset = rl.LoadTexture("assets/sprites/tileset.png")
	a.weapons = rl.LoadTexture("assets/sprites/weapons.png")

	// Layer 1 is the farthest away; 5 is the canopy right in front of the camera.
	for i in 0 ..< BG_LAYERS {
		a.layers[i] = rl.LoadTexture(rl.TextFormat("assets/sprites/background/%d.png", i32(i + 1)))
		rl.SetTextureWrap(a.layers[i], .REPEAT)
	}

	// The font is authored at 8px; drawing it at integer multiples of that with
	// point filtering keeps it pixel-perfect.
	a.font = rl.LoadFontEx("assets/fonts/pixel_operator_bold.ttf", 8, nil, 0)
	rl.SetTextureFilter(a.font.texture, .POINT)

	a.sfx[.Coin] = rl.LoadSound("assets/sounds/coin.wav")
	a.sfx[.Jump] = rl.LoadSound("assets/sounds/jump.wav")
	a.sfx[.Hurt] = rl.LoadSound("assets/sounds/hurt.wav")
	a.sfx[.Power_Up] = rl.LoadSound("assets/sounds/power_up.wav")
	a.sfx[.Explode] = rl.LoadSound("assets/sounds/explosion.wav")
	a.sfx[.Shoot] = rl.LoadSound("assets/sounds/shoot.wav")
	rl.SetSoundVolume(a.sfx[.Explode], 0.30)
	rl.SetSoundVolume(a.sfx[.Coin], 0.45)
	rl.SetSoundVolume(a.sfx[.Shoot], 0.28)

	a.music = rl.LoadMusicStream("assets/music/theme.mp3")
	a.music.looping = true
	rl.SetMusicVolume(a.music, 0.30)
}

// Unloads a set of animations, skipping anything already gone: several
// creatures alias one sheet into two fields, so the same id can show up twice.
@(private = "file")
unload_anims :: proc(anims: []^Anim) {
	for anim, i in anims {
		if anim.texture.id == 0 {
			continue
		}
		id := anim.texture.id
		rl.UnloadTexture(anim.texture)
		for other in anims[i:] {
			if other.texture.id == id {
				other.texture.id = 0
			}
		}
	}
}

@(private = "file")
unload_creature :: proc(c: ^Creature_Anims) {
	anims := [?]^Anim{&c.idle, &c.run, &c.attack, &c.hit, &c.death}
	unload_anims(anims[:])
}

assets_unload :: proc(a: ^Assets) {
	player := [?]^Anim {
		&a.player.idle,
		&a.player.run,
		&a.player.jump,
		&a.player.fall,
		&a.player.double_jump,
		&a.player.wall_slide,
		&a.player.hit,
	}
	unload_anims(player[:])

	for kind in Enemy_Kind {
		unload_creature(&a.enemy[kind])
	}
	unload_creature(&a.golem.armor)
	unload_creature(&a.golem.broken)
	rl.UnloadTexture(a.golem.slam.texture)

	for art in Bullet_Art {
		rl.UnloadTexture(a.bullets[art].texture)
	}
	objects := [?]^Anim{&a.chest, &a.coin, &a.key, &a.rune, &a.flag}
	unload_anims(objects[:])

	for kind in Prop_Kind {
		for i in 0 ..< a.props[kind].count {
			rl.UnloadTexture(a.props[kind].tex[i])
		}
	}

	rl.UnloadTexture(a.tileset)
	rl.UnloadTexture(a.weapons)
	for i in 0 ..< BG_LAYERS {
		rl.UnloadTexture(a.layers[i])
	}
	rl.UnloadFont(a.font)
	for s in Sfx {
		rl.UnloadSound(a.sfx[s])
	}
	rl.UnloadMusicStream(a.music)
}

play :: proc(a: ^Assets, s: Sfx) {
	rl.PlaySound(a.sfx[s])
}

// One variant of a prop kind, wrapping the index so callers can roll a number
// without knowing how many files that folder holds.
prop_texture :: proc(a: ^Assets, kind: Prop_Kind, variant: int) -> rl.Texture2D {
	set := a.props[kind]
	if set.count <= 0 {
		return {}
	}
	return set.tex[variant % set.count]
}
