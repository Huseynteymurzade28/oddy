package game

import "core:encoding/json"
import "core:fmt"
import "core:strings"
import rl "../libs/raylib"

/*
What the game remembers between sessions: which levels are cleared and how
well, which fruit has been kept, which secret exits are found, and the hero
you play as. One small JSON file, written after anything changes.

On Android raylib sends every file written to the app's private storage and
looks there too when reading, so the same relative name works on a phone and
on the desktop (where it lands in the working directory).
*/

SAVE_PATH :: "oddy_save.json"
SAVE_VERSION :: 1

Level_Save :: struct {
	cleared:     bool,
	best_time:   f32,
	best_deaths: int,
	fruit:       u64, // bit i: fruit i of the level has been kept
}

Save :: struct {
	version: int,
	skin:    Skin,
	levels:  map[string]Level_Save, // by LDtk identifier, e.g. "W1_3"
	secrets: map[string]bool, // secret levels whose way in has been found
}

save_destroy :: proc(s: ^Save) {
	for k in s.levels {
		delete(k)
	}
	delete(s.levels)
	for k in s.secrets {
		delete(k)
	}
	delete(s.secrets)
	s^ = {}
}

// Reads the save, or starts a fresh one if there is none or it cannot be
// read: a broken save should cost progress, never the game.
save_load :: proc(s: ^Save) {
	save_destroy(s)
	s.version = SAVE_VERSION
	// No FileExists here: it asks the file system directly, which on Android
	// is not where raylib put the save. Reading goes through raylib's own
	// redirection, and simply comes back empty when there is no save yet.
	size: i32
	bytes := rl.LoadFileData(SAVE_PATH, &size)
	if bytes == nil {
		return
	}
	defer rl.UnloadFileData(bytes)
	loaded: Save
	if err := json.unmarshal(bytes[:size], &loaded); err != nil {
		fmt.eprintln("save: cannot read", SAVE_PATH, err)
		save_destroy(&loaded)
		s.version = SAVE_VERSION
		return
	}
	s^ = loaded
	s.version = SAVE_VERSION
	if s.levels == nil {
		s.levels = make(map[string]Level_Save)
	}
	if s.secrets == nil {
		s.secrets = make(map[string]bool)
	}
}

save_write :: proc(s: ^Save) {
	data, err := json.marshal(s^, {pretty = true}, context.temp_allocator)
	if err != nil {
		fmt.eprintln("save: cannot encode", err)
		return
	}
	text := strings.clone_to_cstring(string(data), context.temp_allocator)
	if !rl.SaveFileText(SAVE_PATH, ([^]u8)(text)) {
		fmt.eprintln("save: cannot write", SAVE_PATH)
	}
}

save_level :: proc(s: ^Save, ident: string) -> Level_Save {
	return s.levels[ident] or_else {}
}

// Records a clear: the best time and the fewest deaths are kept apart, since
// they are separate medals and need not come from the same run.
save_record_clear :: proc(s: ^Save, ident: string, time: f32, deaths: int, fruit: u64) {
	l, had := s.levels[ident]
	if !l.cleared {
		l = {cleared = true, best_time = time, best_deaths = deaths}
	} else {
		l.best_time = min(l.best_time, time)
		l.best_deaths = min(l.best_deaths, deaths)
	}
	l.fruit |= fruit
	if !had {
		s.levels[strings.clone(ident)] = l
	} else {
		s.levels[ident] = l
	}
}

save_find_secret :: proc(s: ^Save, ident: string) {
	if ident not_in s.secrets {
		s.secrets[strings.clone(ident)] = true
	}
}
