package game

import rl "../libs/raylib"

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
	ui:      Ui_Art,
	sfx:     [Sfx]rl.Sound,
	music:   rl.Music,
}

BG_LAYERS :: 5

// The menu art: Kenney's Pixel UI pack, nine-sliced (see `ui.odin`).
Ui_Colour :: enum {
	Green,
	Yellow,
	Red,
	Blue,
	Grey,
}

Ui_Art :: struct {
	button: [Ui_Colour][2]rl.Texture2D, // [colour][0 = up, 1 = pressed]
	panel:  rl.Texture2D, // a wooden board
	inlay:  rl.Texture2D, // parchment, set into a board
}

@(private = "file")
UI_COLOUR_NAMES := [Ui_Colour]cstring {
	.Green  = "green",
	.Yellow = "yellow",
	.Red    = "red",
	.Blue   = "blue",
	.Grey   = "grey",
}

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

	// The creatures are Pixel Adventure 2's. The kinds keep their old names
	// in code; what they look like now:
	//   Rat -> angry pig, Slime -> slime, Crab -> rhino, Bat -> bat,
	//   Skull -> ghost, Pebble -> bee, Golem -> a big rock that breaks down
	//   into a smaller one.
	// The pack has no death animations, so a creature dies on its hit sheet and
	// then fades out. An attack plays the run once through.
	once :: proc(a: Anim, frame_time: f32 = 0) -> Anim {
		b := a
		b.loop = false
		if frame_time > 0 {
			b.frame_time = frame_time
		}
		return b
	}

	R :: "assets/sprites/enemies/pig/"
	pig_run := anim_load(R + "run.png", 36, 30, 12, 0.05, true)
	a.enemy[.Rat] = {
		idle   = anim_load(R + "idle.png", 36, 30, 9, 0.08, true),
		run    = pig_run,
		attack = once(pig_run, 0.045),
		hit    = anim_load(R + "hit.png", 36, 30, 5, 0.06),
		death  = anim_load(R + "death.png", 36, 30, 5, 0.09),
	}

	S :: "assets/sprites/enemies/slime/"
	slime_move := anim_load(S + "move.png", 44, 30, 10, 0.07, true)
	slime_hit := anim_load(S + "hit.png", 44, 30, 5, 0.06)
	a.enemy[.Slime] = {
		idle   = slime_move,
		run    = slime_move,
		attack = once(slime_move, 0.06),
		hit    = slime_hit,
		death  = once(slime_hit, 0.1),
	}

	C :: "assets/sprites/enemies/rino/"
	rino_run := anim_load(C + "run.png", 52, 34, 6, 0.06, true)
	a.enemy[.Crab] = {
		idle   = anim_load(C + "idle.png", 52, 34, 11, 0.08, true),
		run    = rino_run,
		attack = once(rino_run, 0.07),
		hit    = anim_load(C + "hit.png", 52, 34, 5, 0.06),
		death  = anim_load(C + "death.png", 52, 34, 4, 0.1),
	}

	// Fliers are anchored at the bottom of the body, not of the cell.
	B :: "assets/sprites/enemies/bat/"
	bat_fly := anim_load(B + "fly.png", 46, 30, 7, 0.07, true, 27)
	bat_hit := anim_load(B + "hit.png", 46, 30, 5, 0.06, false, 27)
	a.enemy[.Bat] = {
		idle   = bat_fly,
		run    = bat_fly,
		attack = once(bat_fly, 0.06),
		hit    = bat_hit,
		death  = once(bat_hit, 0.1),
	}

	K :: "assets/sprites/enemies/ghost/"
	ghost := anim_load(K + "idle.png", 44, 30, 10, 0.08, true, 30)
	a.enemy[.Skull] = {
		idle   = ghost,
		run    = ghost,
		attack = once(ghost, 0.05),
		hit    = anim_load(K + "hit.png", 44, 30, 5, 0.06, false, 30),
		death  = anim_load(K + "death.png", 44, 30, 4, 0.1, false, 30),
	}

	E :: "assets/sprites/enemies/bee/"
	bee := anim_load(E + "idle.png", 36, 34, 6, 0.07, true, 33)
	bee_hit := anim_load(E + "hit.png", 36, 34, 5, 0.06, false, 33)
	a.enemy[.Pebble] = {
		idle   = bee,
		run    = bee,
		attack = anim_load(E + "attack.png", 36, 34, 8, 0.06, false, 33),
		hit    = bee_hit,
		death  = once(bee_hit, 0.1),
	}

	G :: "assets/sprites/enemies/rock/"
	big_run := anim_load(G + "big_run.png", 38, 34, 14, 0.05, true)
	small_run := anim_load(G + "small_run.png", 32, 28, 14, 0.045, true)
	a.golem = {
		armor = {
			idle = anim_load(G + "big_idle.png", 38, 34, 14, 0.07, true),
			run = big_run,
			attack = once(big_run, 0.035),
			hit = anim_load(G + "big_hit.png", 38, 34, 5, 0.05),
			// The armour coming apart is the armoured phase's "death": it plays
			// when that half of the health bar runs out, and the broken set takes
			// over once it finishes.
			death = anim_load(G + "big_break.png", 38, 34, 8, 0.08),
		},
		broken = {
			idle = anim_load(G + "small_idle.png", 32, 28, 13, 0.06, true),
			run = small_run,
			attack = once(small_run, 0.03),
			hit = anim_load(G + "small_hit.png", 32, 28, 5, 0.05),
			death = anim_load(G + "small_death.png", 32, 28, 6, 0.12),
		},
		slam = anim_load(G + "slam.png", 32, 28, 7, 0.07),
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
	a.flag = anim_load(O + "flag.png", 64, 64, 10, 0.07, true)

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

	for c in Ui_Colour {
		a.ui.button[c][0] = rl.LoadTexture(rl.TextFormat("assets/ui/button_%s.png", UI_COLOUR_NAMES[c]))
		a.ui.button[c][1] = rl.LoadTexture(rl.TextFormat("assets/ui/button_%s_pressed.png", UI_COLOUR_NAMES[c]))
	}
	a.ui.panel = rl.LoadTexture("assets/ui/panel.png")
	a.ui.inlay = rl.LoadTexture("assets/ui/panel_inlay.png")

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
	for c in Ui_Colour {
		rl.UnloadTexture(a.ui.button[c][0])
		rl.UnloadTexture(a.ui.button[c][1])
	}
	rl.UnloadTexture(a.ui.panel)
	rl.UnloadTexture(a.ui.inlay)
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
