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
	Dash,
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

Assets :: struct {
	player:  Player_Anims,
	flag:    Anim,
	tileset: rl.Texture2D,
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

	a.flag = anim_load("assets/sprites/objects/animated/flag.png", 64, 64, 10, 0.07, true)

	a.tileset = rl.LoadTexture("assets/sprites/tileset.png")

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
	// A stand-in until the new sound pass: the old shot is a fair whoosh.
	a.sfx[.Dash] = rl.LoadSound("assets/sounds/shoot.wav")
	rl.SetSoundVolume(a.sfx[.Coin], 0.45)
	rl.SetSoundVolume(a.sfx[.Dash], 0.35)

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

	rl.UnloadTexture(a.flag.texture)

	rl.UnloadTexture(a.tileset)
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
