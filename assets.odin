package game

import rl "vendor:raylib"

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
	shatter: Anim, // armour coming off, played between the two phases
}

Assets :: struct {
	player:  Player_Anims,
	enemy:   [Enemy_Kind]Creature_Anims,
	golem:   Golem_Anims,
	chest:   Anim,
	coin:    Anim,
	key:     Anim,
	rune:    Anim,
	flag:    Anim,
	tileset: rl.Texture2D,
	weapons: rl.Texture2D,
	layers:  [BG_LAYERS]rl.Texture2D,
	font:    rl.Font,
	sfx:     [Sfx]rl.Sound,
	music:   rl.Music,
}

BG_LAYERS :: 5

// Creature sheets are 64x64 cells with the artwork padded inside them, so each
// one needs to say how far down its cell the ground line sits.
@(private = "file")
GROUND :: f32(48)

assets_load :: proc(a: ^Assets) {
	P :: "assets/sprites/player/"
	a.player = {
		idle        = anim_load(P + "Idle.png", 32, 32, 11, 0.12, true),
		run         = anim_load(P + "Run.png", 32, 32, 12, 0.06, true),
		jump        = anim_load(P + "Jump.png", 32, 32, 1),
		fall        = anim_load(P + "Fall.png", 32, 32, 1),
		double_jump = anim_load(P + "Double Jump.png", 32, 32, 6, 0.05),
		wall_slide  = anim_load(P + "Wall Jump.png", 32, 32, 5, 0.10, true),
		hit         = anim_load(P + "Hit.png", 32, 32, 7, 0.05),
	}

	R :: "assets/sprites/Rat/"
	a.enemy[.Rat] = {
		idle   = anim_load(R + "Rat_Idle.png", 64, 64, 4, 0.15, true, GROUND),
		run    = anim_load(R + "Rat_Run.png", 64, 64, 6, 0.07, true, GROUND),
		attack = anim_load(R + "Rat_Attack.png", 64, 64, 8, 0.06, false, GROUND),
		hit    = anim_load(R + "Rat_Hit.png", 64, 64, 4, 0.06, false, GROUND),
		death  = anim_load(R + "Rat_Death.png", 64, 64, 5, 0.09, false, GROUND),
	}

	S :: "assets/sprites/Slime/"
	a.enemy[.Slime] = {
		idle   = anim_load(S + "Slime_Spiked_Idle.png", 64, 64, 4, 0.16, true, GROUND),
		run    = anim_load(S + "Slime_Spiked_Run.png", 64, 64, 4, 0.10, true, GROUND),
		attack = anim_load(S + "Slime_Spiked_Jump.png", 64, 64, 8, 0.07, false, GROUND),
		hit    = anim_load(S + "Slime_Spiked_Hit.png", 64, 64, 4, 0.06, false, GROUND),
		death  = anim_load(S + "Slime_Spiked_Death.png", 64, 64, 6, 0.08, false, GROUND),
	}

	C :: "assets/sprites/Crab/"
	a.enemy[.Crab] = {
		idle   = anim_load(C + "Crab_Idle.png", 64, 64, 4, 0.16, true, GROUND),
		run    = anim_load(C + "Crab_Run.png", 64, 64, 6, 0.08, true, GROUND),
		attack = anim_load(C + "Crab_AttackA.png", 64, 64, 10, 0.06, false, GROUND),
		hit    = anim_load(C + "Crab_Hit.png", 64, 64, 3, 0.07, false, GROUND),
		death  = anim_load(C + "Crab_Death.png", 64, 64, 5, 0.09, false, GROUND),
	}

	// The bat and the skull hover, so their ground line is the bottom of the
	// body rather than the bottom of the cell.
	B :: "assets/sprites/Bat/"
	bat_fly := anim_load(B + "Bat_Fly.png", 64, 64, 4, 0.08, true, 43)
	a.enemy[.Bat] = {
		idle   = bat_fly,
		run    = bat_fly,
		attack = anim_load(B + "Bat_Attack.png", 64, 64, 7, 0.06, false, 43),
		hit    = anim_load(B + "Bat_Hit.png", 64, 64, 5, 0.06, false, 43),
		death  = anim_load(B + "Bat_Death.png", 64, 64, 11, 0.06, false, 43),
	}

	K :: "assets/sprites/Skull/Bones_SingleSkull_"
	skull_fly := anim_load(K + "Fly.png", 64, 64, 8, 0.08, true, 39)
	a.enemy[.Skull] = {
		idle   = anim_load(K + "Idle.png", 64, 64, 4, 0.15, true, 39),
		run    = skull_fly,
		attack = skull_fly,
		hit    = anim_load(K + "Hit.png", 64, 64, 4, 0.06, false, 39),
		death  = anim_load(K + "Death.png", 64, 64, 10, 0.07, false, 39),
	}

	E :: "assets/sprites/Pebble/Pebble_"
	pebble_run := anim_load(E + "Run.png", 64, 64, 5, 0.08, true, 37)
	a.enemy[.Pebble] = {
		idle   = anim_load(E + "Idle.png", 64, 64, 4, 0.16, true, 37),
		run    = pebble_run,
		attack = pebble_run,
		hit    = anim_load(E + "Hit.png", 64, 64, 5, 0.06, false, 37),
		death  = anim_load(E + "Death.png", 64, 64, 7, 0.07, false, 37),
	}

	GA :: "assets/sprites/Golem/Armored/Golem_Armor_"
	GB :: "assets/sprites/Golem/No Armor/Golem_"
	a.golem = {
		armor = {
			idle   = anim_load(GA + "Idle.png", 64, 64, 4, 0.16, true, GROUND),
			run    = anim_load(GA + "Run.png", 64, 64, 4, 0.12, true, GROUND),
			attack = anim_load(GA + "AttackA.png", 64, 64, 11, 0.06, false, GROUND),
			hit    = anim_load(GA + "Hit.png", 64, 64, 5, 0.06, false, GROUND),
			death  = anim_load(GA + "ArmorBreak.png", 64, 64, 5, 0.10, false, GROUND),
		},
		broken = {
			idle   = anim_load(GB + "IdleA.png", 64, 64, 4, 0.16, true, GROUND),
			run    = anim_load(GB + "Run.png", 64, 64, 4, 0.12, true, GROUND),
			attack = anim_load(GB + "AttackA.png", 64, 64, 12, 0.05, false, GROUND),
			hit    = anim_load(GB + "HitA.png", 64, 64, 5, 0.06, false, GROUND),
			death  = anim_load(GB + "DeathB.png", 64, 64, 9, 0.10, false, GROUND),
		},
		slam    = anim_load(GB + "AttackB.png", 64, 64, 7, 0.07, false, GROUND),
		shatter = anim_load(GA + "ArmorBreak.png", 64, 64, 5, 0.10, false, GROUND),
	}

	O :: "assets/sprites/Animated objects/"
	a.chest = anim_load(O + "Chest.png", 32, 32, 4, 0.09)
	a.coin = anim_load(O + "Coin.png", 10, 10, 4, 0.09, true)
	a.key = anim_load(O + "Key.png", 12, 8, 4, 0.12, true)
	a.rune = anim_load(O + "Rune.png", 16, 16, 4, 0.12, true)
	a.flag = anim_load(O + "Flag.png", 48, 48, 4, 0.15, true)

	a.tileset = rl.LoadTexture("assets/sprites/Tiles/Tileset.png")
	a.weapons = rl.LoadTexture("assets/sprites/weapons/1.png")

	// Layer 1 is the farthest away; 5 is the canopy right in front of the camera.
	layer_paths := [BG_LAYERS]cstring {
		"assets/sprites/Background/Layers/1.png",
		"assets/sprites/Background/Layers/2.png",
		"assets/sprites/Background/Layers/3.png",
		"assets/sprites/Background/Layers/4.png",
		"assets/sprites/Background/Layers/5.png",
	}
	for path, i in layer_paths {
		a.layers[i] = rl.LoadTexture(path)
		rl.SetTextureWrap(a.layers[i], .REPEAT)
	}

	// The font is authored at 8px; drawing it at integer multiples of that with
	// point filtering keeps it pixel-perfect.
	a.font = rl.LoadFontEx("assets/fonts/PixelOperator8-Bold.ttf", 8, nil, 0)
	rl.SetTextureFilter(a.font.texture, .POINT)

	a.sfx[.Coin] = rl.LoadSound("assets/sounds/coin.wav")
	a.sfx[.Jump] = rl.LoadSound("assets/sounds/jump.wav")
	a.sfx[.Hurt] = rl.LoadSound("assets/sounds/hurt.wav")
	a.sfx[.Power_Up] = rl.LoadSound("assets/sounds/power_up.wav")
	a.sfx[.Explode] = rl.LoadSound("assets/sounds/explosion.wav")
	a.sfx[.Shoot] = rl.LoadSound("assets/sounds/tap.wav")
	rl.SetSoundVolume(a.sfx[.Explode], 0.30)
	rl.SetSoundVolume(a.sfx[.Coin], 0.45)
	rl.SetSoundVolume(a.sfx[.Shoot], 0.28)

	a.music = rl.LoadMusicStream("assets/music/time_for_adventure.mp3")
	a.music.looping = true
	rl.SetMusicVolume(a.music, 0.30)
}

@(private = "file")
unload_creature :: proc(c: ^Creature_Anims) {
	// The bat, skull and pebble alias one texture into two fields; unloading the
	// same id twice is harmless, but zeroing keeps it honest.
	anims := [?]^Anim{&c.idle, &c.run, &c.attack, &c.hit, &c.death}
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
	for anim in player {
		rl.UnloadTexture(anim.texture)
	}

	for kind in Enemy_Kind {
		unload_creature(&a.enemy[kind])
	}
	unload_creature(&a.golem.armor)
	unload_creature(&a.golem.broken)
	rl.UnloadTexture(a.golem.slam.texture)

	for anim in ([?]^Anim{&a.chest, &a.coin, &a.key, &a.rune, &a.flag}) {
		rl.UnloadTexture(anim.texture)
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
