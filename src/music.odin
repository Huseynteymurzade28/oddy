package game

import rl "../libs/raylib"

/*
The music: one track for the menus, one for each world, one for the bosses,
all from Juhani Junkala (CC0). Changing track crossfades rather than cuts,
and the pause card turns the music down rather than off.
*/

Track :: enum u8 {
	Menu,
	Moss,
	Drowned,
	Ember,
	Boss,
}

@(private = "file")
TRACK_FILES := [Track]cstring {
	.Menu    = "assets/music/menu.ogg",
	.Moss    = "assets/music/moss.ogg",
	.Drowned = "assets/music/drowned.ogg",
	.Ember   = "assets/music/ember.ogg",
	.Boss    = "assets/music/boss.ogg",
}

MUSIC_VOLUME :: 0.38
MUSIC_FADE :: 1.2 // seconds for a full crossfade

Music_Player :: struct {
	tracks:  [Track]rl.Music,
	volume:  [Track]f32, // where each one is in its fade
	current: Track,
	started: bool,
}

music_load :: proc(m: ^Music_Player) {
	for t in Track {
		m.tracks[t] = rl.LoadMusicStream(TRACK_FILES[t])
		m.tracks[t].looping = true
	}
}

music_unload :: proc(m: ^Music_Player) {
	for t in Track {
		rl.UnloadMusicStream(m.tracks[t])
	}
}

// What should be playing right now.
@(private = "file")
wanted_track :: proc(g: ^Game) -> Track {
	switch g.state {
	case .Title, .Map:
		return .Menu
	case .Playing, .Paused, .Cleared:
		if g.boss.present && !g.boss.beaten && g.boss.state != .Waiting {
			return .Boss
		}
		switch g.level.zone {
		case .Mossy:
			return .Moss
		case .Drowned:
			return .Drowned
		case .Ember:
			return .Ember
		}
	}
	return .Menu
}

music_update :: proc(g: ^Game, dt: f32) {
	m := &g.music
	want := wanted_track(g)
	if !m.started || want != m.current {
		m.current = want
		m.started = true
		if !rl.IsMusicStreamPlaying(m.tracks[want]) {
			rl.PlayMusicStream(m.tracks[want])
		}
	}
	duck: f32 = g.state == .Paused ? 0.4 : 1
	for t in Track {
		target: f32 = t == m.current ? 1 : 0
		step := dt / MUSIC_FADE
		m.volume[t] = target > m.volume[t] ? min(m.volume[t] + step, target) : max(m.volume[t] - step, target)
		if !rl.IsMusicStreamPlaying(m.tracks[t]) {
			continue
		}
		if m.volume[t] <= 0 && t != m.current {
			rl.StopMusicStream(m.tracks[t]) // the next time it plays, from the top
			continue
		}
		rl.SetMusicVolume(m.tracks[t], m.volume[t] * MUSIC_VOLUME * duck * music_scale)
		rl.UpdateMusicStream(m.tracks[t])
	}
}
