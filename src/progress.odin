package game

/*
The rules that turn the save into what is open and what is earned: which
levels and worlds you can play, the three medals of a level, and the heroes
you have unlocked. Everything here is worked out from the save each time it
is asked, so there is no second copy of progress to fall out of step.

  A level is open when it is the first of an open world, or the level before
  it is cleared. A secret level is open once its secret exit has been taken.
  A world is open when the last level of the world before it is cleared.

  Medals, per level:
    Time       cleared within the level's par time
    Deathless  cleared without dying
    Fruit      every fruit in it kept (a level with none gives it on a clear)

  Heroes: Virtual Guy from the start, Ninja Frog for 5 fruit, Pink Man for 6
  medals, Mask Dude for clearing a secret level.
*/

WORLDS :: 3
LEVELS_PER_WORLD :: 5

WORLD_NAMES := [WORLDS]cstring{"THE MOSS", "THE DROWNED HALLS", "THE EMBER DEEP"}
WORLD_ZONES := [WORLDS]Zone{.Mossy, .Drowned, .Ember}

Medal :: enum u8 {
	Time,
	Deathless,
	Fruit,
}
Medals :: bit_set[Medal]

SKIN_FRUIT :: 5
SKIN_MEDALS :: 6

level_medals :: proc(g: ^Game, index: int) -> Medals {
	d := &g.levels[index]
	l := save_level(&g.save, d.ident)
	if !l.cleared {
		return {}
	}
	m := Medals{}
	if d.par > 0 && l.best_time <= d.par {
		m += {.Time}
	}
	if l.best_deaths == 0 {
		m += {.Deathless}
	}
	if fruit_count(l.fruit) >= len(d.fruit) {
		m += {.Fruit}
	}
	return m
}

fruit_count :: proc(bits: u64) -> int {
	n := 0
	for i in 0 ..< 64 {
		if bits & (1 << u64(i)) != 0 {
			n += 1
		}
	}
	return n
}

// The level numbered `number` in `world`, as an index into `g.levels`.
find_level :: proc(g: ^Game, world, number: int, secret := false) -> (int, bool) {
	for d, i in g.levels {
		if d.world == world && d.number == number && d.secret == secret {
			return i, true
		}
	}
	return -1, false
}

world_open :: proc(g: ^Game, world: int) -> bool {
	if world <= 1 {
		return true
	}
	last, ok := find_level(g, world - 1, LEVELS_PER_WORLD)
	return ok && save_level(&g.save, g.levels[last].ident).cleared
}

level_open :: proc(g: ^Game, index: int) -> bool {
	d := &g.levels[index]
	if d.secret {
		return d.ident in g.save.secrets
	}
	if !world_open(g, d.world) {
		return false
	}
	if d.number <= 1 {
		return true
	}
	prev, ok := find_level(g, d.world, d.number - 1)
	return ok && save_level(&g.save, g.levels[prev].ident).cleared
}

// The next main level after this one, if it exists and is open.
next_level :: proc(g: ^Game, index: int) -> (int, bool) {
	d := &g.levels[index]
	next, ok := find_level(g, d.world, d.number + 1)
	if !ok && !d.secret {
		next, ok = find_level(g, d.world + 1, 1)
	}
	if !ok || !level_open(g, next) {
		return -1, false
	}
	return next, true
}

Totals :: struct {
	fruit:          int,
	gems:           int,
	medals:         int,
	secrets_beaten: int,
}

progress_totals :: proc(g: ^Game) -> Totals {
	t: Totals
	for d, i in g.levels {
		l := save_level(&g.save, d.ident)
		t.fruit += fruit_count(l.fruit)
		t.gems += l.best_gems
		t.medals += card(level_medals(g, i))
		if d.secret && l.cleared {
			t.secrets_beaten += 1
		}
	}
	return t
}

skin_unlocked :: proc(g: ^Game, skin: Skin) -> bool {
	t := progress_totals(g)
	switch skin {
	case .Virtual_Guy:
		return true
	case .Ninja_Frog:
		return t.fruit >= SKIN_FRUIT
	case .Pink_Man:
		return t.medals >= SKIN_MEDALS
	case .Mask_Dude:
		return t.secrets_beaten > 0
	}
	return false
}

// How to unlock a hero, in two short lines: the cards are narrow on a phone.
skin_hint :: proc(skin: Skin) -> [2]cstring {
	switch skin {
	case .Virtual_Guy:
		return {"", ""}
	case .Ninja_Frog:
		return {"KEEP", "5 FRUIT"}
	case .Pink_Man:
		return {"EARN", "6 MEDALS"}
	case .Mask_Dude:
		return {"BEAT A", "SECRET LEVEL"}
	}
	return {"", ""}
}
