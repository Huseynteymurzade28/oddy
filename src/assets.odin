package game

import "core:math/rand"
import rl "../libs/raylib"

/*
Everything the game loads lives here, and the layout of `assets/` mirrors the
layout of this file: one folder per thing that owns a set of sprites. Nothing
else in the code opens a file, so moving or replacing art is a one-file change.
*/

// Juhani Junkala's "Essential Retro Video Game Sound Effects Collection" (CC0).
Sfx :: enum {
	Jump,
	Land,
	Dash,
	Death,
	Respawn,
	Stomp,
	Bounce,
	Checkpoint,
	Refill,
	Clear,
	Slam,
	Arrow,
	Menu_Move,
	Menu_Select,
	Gem,
	Crate,
}

@(private = "file")
SFX_FILES := [Sfx]struct {
	name:   cstring,
	volume: f32,
} {
	.Jump        = {"jump", 0.45},
	.Land        = {"land", 0.35},
	.Dash        = {"dash", 0.55},
	.Death       = {"death", 0.7},
	.Respawn     = {"respawn", 0.4},
	.Stomp       = {"stomp", 0.6},
	.Bounce      = {"bounce", 0.5},
	.Checkpoint  = {"checkpoint", 0.5},
	.Refill      = {"refill", 0.45},
	.Clear       = {"clear", 0.6},
	.Slam        = {"slam", 0.5},
	.Arrow       = {"arrow", 0.35},
	.Menu_Move   = {"menu_move", 0.4},
	.Menu_Select = {"menu_select", 0.45},
	.Gem         = {"gem", 0.4},
	.Crate       = {"crate", 0.6},
}

// Sounds that repeat a lot are played a hair off pitch each time, so a run of
// jumps does not sound like a machine.
@(private = "file")
SFX_VARY :: bit_set[Sfx]{.Jump, .Land, .Dash, .Stomp, .Arrow, .Crate}

Player_Anims :: struct {
	idle:        Anim,
	run:         Anim,
	jump:        Anim,
	fall:        Anim,
	double_jump: Anim,
	wall_slide:  Anim,
	hit:         Anim,
	appear:      Anim, // the puff you arrive in
	disappear:   Anim, // the puff you leave in
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

// The four heroes of Pixel Adventure 1. All ship the same sheets.
Skin :: enum u8 {
	Virtual_Guy,
	Ninja_Frog,
	Pink_Man,
	Mask_Dude,
}

SKIN_FOLDERS := [Skin]cstring {
	.Virtual_Guy = "virtual_guy",
	.Ninja_Frog  = "ninja_frog",
	.Pink_Man    = "pink_man",
	.Mask_Dude   = "mask_dude",
}

SKIN_NAMES := [Skin]cstring {
	.Virtual_Guy = "VIRTUAL GUY",
	.Ninja_Frog  = "NINJA FROG",
	.Pink_Man    = "PINK MAN",
	.Mask_Dude   = "MASK DUDE",
}

FRUIT_KINDS :: 8

Assets :: struct {
	// The hero being played. A copy of one of `skins`, so the animator can
	// point into it whichever hero it is.
	player:  Player_Anims,
	skins:   [Skin]Player_Anims,
	fruit:   [FRUIT_KINDS]Anim,
	fruit_got: Anim, // the sparkle a fruit leaves when it is kept
	gem:     Anim,
	critters: rl.Texture2D, // butterflies and a bird, drawn by tools/art
	traps:   Trap_Anims,
	enemy:   [Enemy_Kind]Creature_Anims,
	warden:  Creature_Anims, // world 3's boss: the big rock
	marks:   Checkpoint_Anims,
	// Oddy's own art, drawn by tools/art/make_art.py: per world, the
	// terrain sheet and the parallax layers.
	terrain: [Zone]rl.Texture2D,
	layers:  [Zone][BG_LAYERS]rl.Texture2D,
	font:    rl.Font,
	ui:      Ui_Art,
	sfx:     [Sfx]rl.Sound,
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
	for skin in Skin {
		dir := SKIN_FOLDERS[skin]
		path :: proc(dir, file: cstring) -> cstring {
			return rl.TextFormat("assets/sprites/skins/%s/%s.png", dir, file)
		}
		a.skins[skin] = {
			idle        = anim_load(path(dir, "idle"), 32, 32, 11, 0.12, true),
			run         = anim_load(path(dir, "run"), 32, 32, 12, 0.06, true),
			jump        = anim_load(path(dir, "jump"), 32, 32, 1),
			fall        = anim_load(path(dir, "fall"), 32, 32, 1),
			double_jump = anim_load(path(dir, "double_jump"), 32, 32, 6, 0.05),
			wall_slide  = anim_load(path(dir, "wall_slide"), 32, 32, 5, 0.10, true),
			hit         = anim_load(path(dir, "hit"), 32, 32, 7, 0.05),
		}
	}
	// 96px cells with the puff centred: anchored so `pos` is the feet of a
	// 32px character standing in the middle. Shared by every hero.
	P :: "assets/sprites/player/"
	appear := anim_load(P + "appear.png", 96, 96, 7, 0.045, false, 64)
	disappear := anim_load(P + "disappear.png", 96, 96, 7, 0.045, false, 64)
	for skin in Skin {
		a.skins[skin].appear = appear
		a.skins[skin].disappear = disappear
	}
	assets_use_skin(a, .Virtual_Guy)

	F :: "assets/sprites/fruit/"
	fruit_files := [FRUIT_KINDS]cstring{"apple", "cherries", "kiwi", "bananas", "melon", "orange", "pineapple", "strawberry"}
	for name, i in fruit_files {
		// Centred in its 32px cell, so anchored at the middle.
		a.fruit[i] = anim_load(rl.TextFormat(F + "%s.png", name), 32, 32, 17, 0.05, true, 16)
	}
	a.fruit_got = anim_load(F + "collected.png", 32, 32, 6, 0.05, false, 16)
	a.gem = anim_load("assets/sprites/fx/gem.png", 12, 12, 6, 0.08, true, 6)
	a.critters = rl.LoadTexture("assets/sprites/fx/critters.png")

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
	a.warden = {
		idle = anim_load(E + "rock/big_idle.png", 38, 34, 14, 0.07, true),
		run  = anim_load(E + "rock/big_run.png", 38, 34, 14, 0.04, true),
		hit  = anim_load(E + "rock/big_hit.png", 38, 34, 5, 0.05),
	}
	bee := anim_load(E + "bee/idle.png", 36, 34, 6, 0.07, true, 33)
	a.enemy[.Bee] = {
		idle = bee,
		run  = bee,
		hit  = anim_load(E + "bee/hit.png", 36, 34, 5, 0.06, false, 33),
	}

	ZONE_FILES := [Zone]cstring {
		.Mossy   = "mossy",
		.Drowned = "drowned",
		.Ember   = "ember",
	}
	for zone in Zone {
		name := ZONE_FILES[zone]
		a.terrain[zone] = rl.LoadTexture(rl.TextFormat("assets/sprites/terrain/%s.png", name))
		for i in 0 ..< BG_LAYERS {
			tex := rl.LoadTexture(rl.TextFormat("assets/sprites/background/%s_%d.png", name, i32(i)))
			rl.SetTextureWrap(tex, .REPEAT)
			a.layers[zone][i] = tex
		}
	}

	// Layer 1 is the farthest away; 5 is the canopy right in front of the camera.

	// The font is authored at 8px; drawing it at integer multiples of that with
	// point filtering keeps it pixel-perfect.
	a.font = rl.LoadFontEx("assets/fonts/pixel_operator_bold.ttf", 8, nil, 0)
	rl.SetTextureFilter(a.font.texture, .POINT)

	for sfx in Sfx {
		f := SFX_FILES[sfx]
		a.sfx[sfx] = rl.LoadSound(rl.TextFormat("assets/sounds/%s.wav", f.name))
		rl.SetSoundVolume(a.sfx[sfx], f.volume)
	}

	for c in Ui_Colour {
		a.ui.button[c][0] = rl.LoadTexture(rl.TextFormat("assets/ui/button_%s.png", UI_COLOUR_NAMES[c]))
		a.ui.button[c][1] = rl.LoadTexture(rl.TextFormat("assets/ui/button_%s_pressed.png", UI_COLOUR_NAMES[c]))
	}
	a.ui.panel = rl.LoadTexture("assets/ui/panel.png")
	a.ui.inlay = rl.LoadTexture("assets/ui/panel_inlay.png")

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
	for skin in Skin {
		k := &a.skins[skin]
		hero := [?]^Anim{&k.idle, &k.run, &k.jump, &k.fall, &k.double_jump, &k.wall_slide, &k.hit}
		unload_anims(hero[:])
	}
	puffs := [?]^Anim{&a.skins[.Virtual_Guy].appear, &a.skins[.Virtual_Guy].disappear}
	unload_anims(puffs[:])
	for &f in a.fruit {
		rl.UnloadTexture(f.texture)
	}
	rl.UnloadTexture(a.fruit_got.texture)
	rl.UnloadTexture(a.gem.texture)
	rl.UnloadTexture(a.critters)

	traps := [?]^Anim {
		&a.traps.saw, &a.traps.trampoline, &a.traps.trampoline_jump, &a.traps.falling_platform,
		&a.traps.fan, &a.traps.fire_off, &a.traps.fire_hit, &a.traps.fire_on,
		&a.traps.refill, &a.traps.refill_pop, &a.traps.spike_head, &a.traps.spike_head_blink,
		&a.traps.spike_head_hit,
		&a.marks.pole, &a.marks.flag_out, &a.marks.flag, &a.marks.end, &a.marks.end_pressed,
	}
	unload_anims(traps[:])
	rl.UnloadTexture(a.traps.chain)
	rl.UnloadTexture(a.traps.spikes)
	{
		w := [?]^Anim{&a.warden.idle, &a.warden.run, &a.warden.hit}
		unload_anims(w[:])
	}
	for kind in Enemy_Kind {
		c := &a.enemy[kind]
		creature := [?]^Anim{&c.idle, &c.run, &c.hit}
		unload_anims(creature[:])
	}

	for zone in Zone {
		rl.UnloadTexture(a.terrain[zone])
		for i in 0 ..< BG_LAYERS {
			rl.UnloadTexture(a.layers[zone][i])
		}
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
}

// Puts on a hero. Everything that animates the player points into
// `a.player`, so changing it in place is all a change of hero takes.
assets_use_skin :: proc(a: ^Assets, skin: Skin) {
	a.player = a.skins[skin]
}

// The same sound at a chosen pitch: a run of gems climbs the scale.
play_pitched :: proc(a: ^Assets, s: Sfx, pitch: f32) {
	rl.SetSoundPitch(a.sfx[s], pitch)
	rl.PlaySound(a.sfx[s])
}

play :: proc(a: ^Assets, s: Sfx) {
	if s in SFX_VARY {
		rl.SetSoundPitch(a.sfx[s], rand.float32_range(0.93, 1.07))
	}
	rl.PlaySound(a.sfx[s])
}
