package game

/*
The settings, kept in the save: how loud the music and the sounds are,
whether the phone buzzes, and two comforts for anyone who wants the game
gentler: a slower game speed, and a dash that never runs out. Each one is a
button on the settings card that steps to the next value when pressed.
*/

Settings :: struct {
	set:          bool, // false in a save from before settings: use the defaults
	music:        int, // percent
	sound:        int,
	vibration:    bool,
	speed:        int, // percent
	endless_dash: bool,
}

SETTINGS_DEFAULT :: Settings {
	set          = true,
	music        = 80,
	sound        = 80,
	vibration    = true,
	speed        = 100,
	endless_dash = false,
}

GAME_SPEEDS := [4]int{100, 85, 70, 55}

// What the rest of the game reads, so the settings need not be passed around.
sound_scale: f32 = 0.8
music_scale: f32 = 0.8
vibration_on := true

settings_apply :: proc(s: ^Settings) {
	if !s.set {
		s^ = SETTINGS_DEFAULT
	}
	sound_scale = f32(s.sound) / 100
	music_scale = f32(s.music) / 100
	vibration_on = s.vibration
}

// The next value along for one setting, wrapping round.
settings_step :: proc(g: ^Game, action: Menu_Action) {
	s := &g.save.settings
	switch action {
	case .Set_Music:
		s.music = (s.music + 20) % 120
	case .Set_Sound:
		s.sound = (s.sound + 20) % 120
	case .Set_Vibration:
		s.vibration = !s.vibration
		if s.vibration {
			vibration_on = true
			haptic(.Checkpoint) // so you feel what you turned on
		}
	case .Set_Speed:
		at := 0
		for v, i in GAME_SPEEDS {
			if v == s.speed {
				at = i
			}
		}
		s.speed = GAME_SPEEDS[(at + 1) % len(GAME_SPEEDS)]
	case .Set_Dash:
		s.endless_dash = !s.endless_dash
	case .None, .Play, .How_To, .Back, .Resume, .Restart, .Next, .To_Map, .Menu, .Quit, .Settings:
	}
	settings_apply(s)
	save_write(&g.save)
}

game_speed :: proc(g: ^Game) -> f32 {
	return f32(max(g.save.settings.speed, 25)) / 100
}
