package game

import "core:encoding/json"
import "core:fmt"
import "core:strings"
import rl "../libs/raylib"

/*
Reading the levels out of `levels/oddy.ldtk`, the LDtk project they are drawn
in. Only the parts the game needs are read; everything else in the file is the
editor's business.

What the project has to contain (and does, as LDtk saves it):

  Collision  an IntGrid layer, 16px cells:
               1 rock   2 one-way platform   3 spikes   4 water
  Entities   an Entities layer with
               Player_Start  where you start; one per level
               Checkpoint    a flag you respawn at once touched
               Exit          the flag that finishes the level
               Hint          a line of text in the world (field `Text`)
             All four have their pivot at the bottom centre.
  levels     each with a `Name` (String) and a `Zone` (enum Mossy, Drowned,
             Ember), and played in the order they are listed in LDtk.

How the rock looks is not in the file: the game nine-slices it from which of
its neighbours are solid (see `tilemap.odin`), so drawing a shape in the
Collision layer is all a level needs.
*/

LEVELS_PATH :: "levels/oddy.ldtk"

Hint :: struct {
	pos:  rl.Vector2, // bottom centre of the text
	text: cstring,
}

// One level as it is in the file. `level.odin` builds the live level from it.
Level_Data :: struct {
	ident:       string,
	name:        cstring,
	zone:        Zone,
	width:       int, // cells
	height:      int,
	tiles:       []Tile,
	spawn:       rl.Vector2,
	exit:        rl.Vector2,
	checkpoints: [dynamic]rl.Vector2,
	hints:       [dynamic]Hint,
}

level_data_destroy :: proc(d: ^Level_Data) {
	delete(d.ident)
	delete(d.name)
	delete(d.tiles)
	delete(d.checkpoints)
	for h in d.hints {
		delete(h.text)
	}
	delete(d.hints)
	d^ = {}
}

levels_destroy :: proc(levels: ^[dynamic]Level_Data) {
	for &d in levels {
		level_data_destroy(&d)
	}
	delete(levels^)
	levels^ = {}
}

// Reads every level in the project. On failure the list comes back empty and
// the error says why, so the caller can carry on with something to show.
ldtk_load :: proc(path: cstring) -> (levels: [dynamic]Level_Data, err: string) {
	size: i32
	bytes := rl.LoadFileData(path, &size)
	if bytes == nil {
		return {}, fmt.tprintf("cannot read %s", path)
	}
	defer rl.UnloadFileData(bytes)

	root, perr := json.parse(bytes[:size], parse_integers = true)
	defer json.destroy_value(root)
	if perr != .None {
		return {}, fmt.tprintf("%s is not valid JSON (%v)", path, perr)
	}

	for lv in arr(get(root, "levels")) {
		d, ok := read_level(lv)
		if !ok {
			level_data_destroy(&d)
			levels_destroy(&levels)
			return {}, fmt.tprintf("level %s in %s is missing its Collision layer", str(get(lv, "identifier")), path)
		}
		append(&levels, d)
	}
	if len(levels) == 0 {
		return {}, fmt.tprintf("%s has no levels", path)
	}
	return levels, ""
}

@(private = "file")
read_level :: proc(lv: json.Value) -> (d: Level_Data, ok: bool) {
	d.ident = strings.clone(str(get(lv, "identifier")))
	d.name = strings.clone_to_cstring(d.ident)
	d.zone = .Mossy

	for f in arr(get(lv, "fieldInstances")) {
		value := str(get(f, "__value"))
		switch str(get(f, "__identifier")) {
		case "Name":
			if value != "" {
				delete(d.name)
				d.name = strings.clone_to_cstring(value)
			}
		case "Zone":
			for z in Zone {
				if fmt.tprint(z) == value {
					d.zone = z
				}
			}
		}
	}

	for layer in arr(get(lv, "layerInstances")) {
		switch str(get(layer, "__identifier")) {
		case "Collision":
			d.width = num(get(layer, "__cWid"))
			d.height = num(get(layer, "__cHei"))
			csv := arr(get(layer, "intGridCsv"))
			d.tiles = make([]Tile, d.width * d.height)
			for v, i in csv {
				if i >= len(d.tiles) {
					break
				}
				switch num(v) {
				case 1:
					d.tiles[i] = .Rock
				case 2:
					d.tiles[i] = .Platform
				case 3:
					d.tiles[i] = .Spike
				case 4:
					d.tiles[i] = .Water
				}
			}
			ok = true
		case "Entities":
			for e in arr(get(layer, "entityInstances")) {
				px := arr(get(e, "px"))
				if len(px) < 2 {
					continue
				}
				pos := rl.Vector2{f32(num(px[0])), f32(num(px[1]))}
				switch str(get(e, "__identifier")) {
				case "Player_Start":
					d.spawn = pos
				case "Checkpoint":
					append(&d.checkpoints, pos)
				case "Exit":
					d.exit = pos
				case "Hint":
					text := ""
					for f in arr(get(e, "fieldInstances")) {
						if str(get(f, "__identifier")) == "Text" {
							text = str(get(f, "__value"))
						}
					}
					append(&d.hints, Hint{pos = pos, text = strings.clone_to_cstring(text)})
				}
			}
		}
	}
	return
}

// ------------------------------------------------- reading a JSON tree ---
// Each of these answers with an empty value for anything missing or of the
// wrong kind, so the reading above never has to check twice.

@(private = "file")
get :: proc(v: json.Value, key: string) -> json.Value {
	if obj, is_obj := v.(json.Object); is_obj {
		return obj[key]
	}
	return nil
}

@(private = "file")
arr :: proc(v: json.Value) -> []json.Value {
	if a, ok := v.(json.Array); ok {
		return a[:]
	}
	return nil
}

@(private = "file")
str :: proc(v: json.Value) -> string {
	if s, ok := v.(json.String); ok {
		return s
	}
	return ""
}

@(private = "file")
num :: proc(v: json.Value) -> int {
	#partial switch n in v {
	case json.Integer:
		return int(n)
	case json.Float:
		return int(n)
	}
	return 0
}
