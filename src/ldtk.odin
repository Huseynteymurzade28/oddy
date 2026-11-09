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
               1 rock   2 one-way platform   3 spikes   4 water   5 crate
  Entities   an Entities layer with
               Player_Start  where you start; one per level
               Checkpoint    a flag you respawn at once touched
               Exit          the flag that finishes the level
               Hint          a line of text in the world (field `Text`)
               Gem, Gem_Line a gem; a row of gems along the rectangle
             and the traps and creatures in `things.odin` and `enemy.odin`.
             Every entity is read as the rectangle LDtk draws for it, so
             pivots and sizes can be changed in the editor freely.
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
	world:       int, // from the identifier: "W2_4" is world 2, level 4
	number:      int,
	secret:      bool, // "W1_S1": a level found through a secret exit
	name:        cstring,
	zone:        Zone,
	par:         f32, // seconds for the time medal; 0 for none
	fruit:       [dynamic]rl.Vector2,
	gems:        [dynamic]rl.Vector2,
	crates:      int, // crate tiles: each one breaks into GEMS_PER_CRATE
	secret_exit: rl.Vector2, // zero if the level has none
	has_boss:    bool,
	boss:        Boss_Kind,
	boss_pos:    rl.Vector2, // its feet
	unlocks:     string, // the level that secret exit opens
	width:       int, // cells
	height:      int,
	tiles:       []Tile,
	spawn:       rl.Vector2,
	exit:        rl.Vector2,
	checkpoints: [dynamic]rl.Vector2,
	hints:       [dynamic]Hint,
	things:      [dynamic]Thing_Data, // traps, moving pieces and creatures
}

// A trap or a creature as placed in LDtk. Which fields mean anything depends
// on the kind; the rest keep their defaults.
Thing_Data :: struct {
	kind:     Thing_Kind,
	rect:     rl.Rectangle, // the entity's rectangle in the level, in pixels
	speed:    f32, // px/s along a track
	interval: f32, // seconds between shots
	delay:    f32, // seconds before the first one
	dir:      [2]int, // which way an arrow shooter faces
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
	delete(d.things)
	delete(d.fruit)
	delete(d.gems)
	delete(d.unlocks)
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
	d.world, d.number, d.secret = parse_ident(d.ident)

	for f in arr(get(lv, "fieldInstances")) {
		value := str(get(f, "__value"))
		switch str(get(f, "__identifier")) {
		case "Name":
			if value != "" {
				delete(d.name)
				d.name = strings.clone_to_cstring(value)
			}
		case "Par":
			d.par = flt(get(f, "__value"))
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
				case 5:
					d.tiles[i] = .Crate
					d.crates += 1
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
				ident := str(get(e, "__identifier"))
				if kind, is_thing := thing_kind_from_name(ident); is_thing {
					append(&d.things, read_thing(e, kind, pos))
					continue
				}
				if kind, is_boss := boss_kind_from_name(ident); is_boss {
					t := read_thing(e, .Saw, pos) // only for its rectangle
					d.has_boss = true
					d.boss = kind
					d.boss_pos = {t.rect.x + t.rect.width / 2, t.rect.y + t.rect.height}
					continue
				}
				switch ident {
				case "Player_Start":
					d.spawn = pos
				case "Checkpoint":
					append(&d.checkpoints, pos)
				case "Exit":
					d.exit = pos
				case "Fruit":
					append(&d.fruit, pos)
				case "Gem":
					append(&d.gems, pos)
				case "Gem_Line":
					// A row (or column) of gems, one a tile, along the long
					// side of the rectangle drawn in LDtk.
					w := f32(num(get(e, "width")))
					h := f32(num(get(e, "height")))
					pv := arr(get(e, "__pivot"))
					px, py: f32 = 0, 0
					if len(pv) >= 2 {
						px, py = flt(pv[0]), flt(pv[1])
					}
					r := rl.Rectangle{pos.x - px * w, pos.y - py * h, w, h}
					if w >= h {
						for x := r.x + TILE / 2; x < r.x + w; x += TILE {
							append(&d.gems, rl.Vector2{x, r.y + h / 2})
						}
					} else {
						for y := r.y + TILE / 2; y < r.y + h; y += TILE {
							append(&d.gems, rl.Vector2{r.x + w / 2, y})
						}
					}
				case "Secret_Exit":
					d.secret_exit = pos
					for f in arr(get(e, "fieldInstances")) {
						if str(get(f, "__identifier")) == "Unlocks" {
							delete(d.unlocks)
							d.unlocks = strings.clone(str(get(f, "__value")))
						}
					}
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

// "W2_4" -> world 2, level 4; "W1_S1" -> world 1, secret level 1. Anything
// else is world 1, numbered 0, which sorts it ahead of the real levels.
@(private = "file")
parse_ident :: proc(ident: string) -> (world, number: int, secret: bool) {
	world = 1
	if len(ident) < 4 || ident[0] != 'W' {
		return
	}
	under := strings.index_byte(ident, '_')
	if under < 2 {
		return
	}
	world = max(1, atoi(ident[1:under]))
	rest := ident[under + 1:]
	if len(rest) > 0 && rest[0] == 'S' {
		secret = true
		rest = rest[1:]
	}
	number = atoi(rest)
	return
}

@(private = "file")
atoi :: proc(s: string) -> int {
	n := 0
	for c in s {
		if c < '0' || c > '9' {
			break
		}
		n = n * 10 + int(c - '0')
	}
	return n
}

@(private = "file")
read_thing :: proc(e: json.Value, kind: Thing_Kind, pos: rl.Vector2) -> Thing_Data {
	w := f32(num(get(e, "width")))
	h := f32(num(get(e, "height")))
	pivot := arr(get(e, "__pivot"))
	px, py: f32 = 0.5, 1
	if len(pivot) >= 2 {
		px, py = flt(pivot[0]), flt(pivot[1])
	}
	t := Thing_Data {
		kind     = kind,
		rect     = {pos.x - px * w, pos.y - py * h, w, h},
		speed    = 60,
		interval = 1.6,
		dir      = {1, 0},
	}
	for f in arr(get(e, "fieldInstances")) {
		v := get(f, "__value")
		switch str(get(f, "__identifier")) {
		case "Speed":
			t.speed = flt(v)
		case "Interval":
			t.interval = max(flt(v), 0.2)
		case "Delay":
			t.delay = flt(v)
		case "Dir":
			switch str(v) {
			case "Left":
				t.dir = {-1, 0}
			case "Up":
				t.dir = {0, -1}
			case "Down":
				t.dir = {0, 1}
			case:
				t.dir = {1, 0}
			}
		}
	}
	return t
}

// The LDtk entity names are the enum's names, so adding a kind to the enum is
// all it takes for the reader to know it.
thing_kind_from_name :: proc(name: string) -> (Thing_Kind, bool) {
	for k in Thing_Kind {
		if fmt.tprint(k) == name {
			return k, true
		}
	}
	return {}, false
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
flt :: proc(v: json.Value) -> f32 {
	#partial switch n in v {
	case json.Integer:
		return f32(n)
	case json.Float:
		return f32(n)
	}
	return 0
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
