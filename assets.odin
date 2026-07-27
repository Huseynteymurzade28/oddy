package game

import rl "vendor:raylib"

Sfx :: enum {
	Coin,
	Jump,
	Hurt,
	Power_Up,
	Stomp,
	Tap,
}

Assets :: struct {
	player_idle: Sprite_Sheet,
	player_run:  Sprite_Sheet,
	slime:       [Enemy_Kind]Sprite_Sheet,
	coin:        Sprite_Sheet,
	fruit:       Sprite_Sheet,
	tileset:     rl.Texture2D,
	platforms:   rl.Texture2D,
	font:        rl.Font,
	sfx:         [Sfx]rl.Sound,
	music:       rl.Music,
}

// Clips are named here rather than at their use sites so the frame layout of
// each sheet is documented in one place.
CLIP_PLAYER_IDLE :: Clip{first = 0, count = 2, frame_time = 0.40, loop = true}
CLIP_PLAYER_RUN :: Clip{first = 0, count = 4, frame_time = 0.09, loop = true}
CLIP_PLAYER_JUMP :: Clip{first = 2, count = 1}
CLIP_PLAYER_FALL :: Clip{first = 3, count = 1}
CLIP_SLIME_WALK :: Clip{first = 0, count = 8, frame_time = 0.12, loop = true}
CLIP_SLIME_DIE :: Clip{first = 8, count = 4, frame_time = 0.06}
CLIP_COIN_SPIN :: Clip{first = 0, count = 12, frame_time = 0.06, loop = true}

assets_load :: proc(a: ^Assets) {
	a.player_idle = sheet_load("assets/sprites/player_idle.png", 16, 16)
	a.player_run = sheet_load("assets/sprites/player_run.png", 16, 16)
	a.slime[.Green] = sheet_load("assets/sprites/slime_green.png", 24, 24)
	a.slime[.Purple] = sheet_load("assets/sprites/slime_purple.png", 24, 24)
	a.coin = sheet_load("assets/sprites/coin.png", 16, 16)
	a.fruit = sheet_load("assets/sprites/fruit.png", 16, 16)

	a.tileset = rl.LoadTexture("assets/sprites/world_tileset.png")
	a.platforms = rl.LoadTexture("assets/sprites/platforms.png")

	// The font is authored at 8px; drawing it at integer multiples of that with
	// point filtering keeps it pixel-perfect.
	a.font = rl.LoadFontEx("assets/fonts/PixelOperator8-Bold.ttf", 8, nil, 0)
	rl.SetTextureFilter(a.font.texture, .POINT)

	a.sfx[.Coin] = rl.LoadSound("assets/sounds/coin.wav")
	a.sfx[.Jump] = rl.LoadSound("assets/sounds/jump.wav")
	a.sfx[.Hurt] = rl.LoadSound("assets/sounds/hurt.wav")
	a.sfx[.Power_Up] = rl.LoadSound("assets/sounds/power_up.wav")
	a.sfx[.Stomp] = rl.LoadSound("assets/sounds/explosion.wav")
	a.sfx[.Tap] = rl.LoadSound("assets/sounds/tap.wav")
	rl.SetSoundVolume(a.sfx[.Stomp], 0.35)
	rl.SetSoundVolume(a.sfx[.Coin], 0.5)

	a.music = rl.LoadMusicStream("assets/music/time_for_adventure.mp3")
	a.music.looping = true
	rl.SetMusicVolume(a.music, 0.35)
}

assets_unload :: proc(a: ^Assets) {
	rl.UnloadTexture(a.player_idle.texture)
	rl.UnloadTexture(a.player_run.texture)
	for kind in Enemy_Kind {
		rl.UnloadTexture(a.slime[kind].texture)
	}
	rl.UnloadTexture(a.coin.texture)
	rl.UnloadTexture(a.fruit.texture)
	rl.UnloadTexture(a.tileset)
	rl.UnloadTexture(a.platforms)
	rl.UnloadFont(a.font)
	for s in Sfx {
		rl.UnloadSound(a.sfx[s])
	}
	rl.UnloadMusicStream(a.music)
}

play :: proc(a: ^Assets, s: Sfx) {
	rl.PlaySound(a.sfx[s])
}
