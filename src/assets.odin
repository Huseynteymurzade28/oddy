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

// Pixel Adventure 1's traps, one field per sheet.
Trap_Anims :: struct {
	saw:              Anim,
	chain:            rl.Texture2D,
	spikes:           rl.Texture2D,
	trampoline:       Anim,
	trampoline_jump:  Anim,
	falling_platform: Anim,
	fan:              Anim,
	fire_off:         Anim,
	fire_hit:         Anim,
	fire_on:          Anim,
	platform:         Anim,
	refill:           Anim,
	refill_pop:       Anim,
	spike_head:       Anim,
	spike_head_blink: Anim,
	spike_head_hit:   Anim,
}

// Every creature in Pixel Adventure 2 ships about the same states; ones
// without a distinct walk point both fields at the same sheet.
Creature_Anims :: struct {
	idle: Anim,
	run:  Anim,
	hit:  Anim,
}

Checkpoint_Anims :: struct {
	pole:        Anim, // not yet reached
	flag_out:    Anim, // the flag going up
	flag:        Anim, // flying
	end:         Anim, // the trophy at the end of a level
	end_pressed: Anim,
}

Assets :: struct {
	player:  Player_Anims,
	traps:   Trap_Anims,
	enemy:   [Enemy_Kind]Creature_Anims,
	marks:   Checkpoint_Anims,
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

	T :: "assets/sprites/traps/"
	a.traps = {
		saw              = anim_load(T + "saw.png", 38, 38, 8, 0.04, true),
		chain            = rl.LoadTexture(T + "chain.png"),
		spikes           = rl.LoadTexture(T + "spikes.png"),
		trampoline       = anim_load(T + "trampoline_idle.png", 28, 28, 1),
		trampoline_jump  = anim_load(T + "trampoline_jump.png", 28, 28, 8, 0.04),
		falling_platform = anim_load(T + "falling_platform.png", 32, 10, 4, 0.06, true),
		fan              = anim_load(T + "fan.png", 24, 8, 4, 0.03, true),
		fire_off         = anim_load(T + "fire_off.png", 16, 32, 1),
		fire_hit         = anim_load(T + "fire_hit.png", 16, 32, 4, 0.08, true),
		fire_on          = anim_load(T + "fire_on.png", 16, 32, 3, 0.07, true),
		platform         = anim_load(T + "platform.png", 32, 8, 8, 0.05, true),
		refill           = anim_load(T + "refill_idle.png", 18, 18, 10, 0.07, true),
		refill_pop       = anim_load(T + "refill_hit.png", 18, 18, 4, 0.06),
		spike_head       = anim_load(T + "spike_head_idle.png", 54, 52, 1),
		spike_head_blink = anim_load(T + "spike_head_blink.png", 54, 52, 4, 0.08),
		spike_head_hit   = anim_load(T + "spike_head_hit.png", 54, 52, 4, 0.07),
	}

	C :: "assets/sprites/objects/checkpoint/"
	a.marks = {
		pole        = anim_load(C + "pole.png", 64, 64, 1),
		flag_out    = anim_load(C + "flag_out.png", 64, 64, 26, 0.03),
		flag        = anim_load(C + "flag_idle.png", 64, 64, 10, 0.07, true),
		end         = anim_load(C + "end_idle.png", 64, 64, 1),
		end_pressed = anim_load(C + "end_pressed.png", 64, 64, 8, 0.06),
	}

	// The creatures face left in the sheets. Fliers are anchored at the
	// bottom of the body, not of the cell.
	E :: "assets/sprites/enemies/"
	pig_run := anim_load(E + "pig/run.png", 36, 30, 12, 0.05, true)
	a.enemy[.Pig] = {
		idle = anim_load(E + "pig/idle.png", 36, 30, 9, 0.08, true),
		run  = pig_run,
		hit  = anim_load(E + "pig/hit.png", 36, 30, 5, 0.06),
	}
	slime := anim_load(E + "slime/move.png", 44, 30, 10, 0.07, true)
	a.enemy[.Slime] = {
		idle = slime,
		run  = slime,
		hit  = anim_load(E + "slime/hit.png", 44, 30, 5, 0.06),
	}
	a.enemy[.Rino] = {
		idle = anim_load(E + "rino/idle.png", 52, 34, 11, 0.08, true),
		run  = anim_load(E + "rino/run.png", 52, 34, 6, 0.05, true),
		hit  = anim_load(E + "rino/hit.png", 52, 34, 5, 0.07),
	}
	bat := anim_load(E + "bat/fly.png", 46, 30, 7, 0.07, true, 27)
	a.enemy[.Bat] = {
		idle = bat,
		run  = bat,
		hit  = anim_load(E + "bat/hit.png", 46, 30, 5, 0.06, false, 27),
	}
	bee := anim_load(E + "bee/idle.png", 36, 34, 6, 0.07, true, 33)
	a.enemy[.Bee] = {
		idle = bee,
		run  = bee,
		hit  = anim_load(E + "bee/hit.png", 36, 34, 5, 0.06, false, 33),
	}

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

	traps := [?]^Anim {
		&a.traps.saw, &a.traps.trampoline, &a.traps.trampoline_jump, &a.traps.falling_platform,
		&a.traps.fan, &a.traps.fire_off, &a.traps.fire_hit, &a.traps.fire_on, &a.traps.platform,
		&a.traps.refill, &a.traps.refill_pop, &a.traps.spike_head, &a.traps.spike_head_blink,
		&a.traps.spike_head_hit,
		&a.marks.pole, &a.marks.flag_out, &a.marks.flag, &a.marks.end, &a.marks.end_pressed,
	}
	unload_anims(traps[:])
	rl.UnloadTexture(a.traps.chain)
	rl.UnloadTexture(a.traps.spikes)
	for kind in Enemy_Kind {
		c := &a.enemy[kind]
		creature := [?]^Anim{&c.idle, &c.run, &c.hit}
		unload_anims(creature[:])
	}

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
