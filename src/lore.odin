package game

/*
The whole story of the game, kept in one place so the title card, the objective
tracker and the end screens can never drift apart. Nothing here affects the
simulation — it only names what the rules already do:

  the map is rebuilt every run   ->  the Hollow reshapes itself
  a key unseals the boss room    ->  the rune-key opens the warden's vault
  killing the golem wins         ->  the warden is what keeps the Hollow growing
*/

GAME_TITLE :: "ODDY"
GAME_TAGLINE :: "A DESCENT INTO THE HOLLOW"

// Lines are kept under about 44 characters: the virtual screen is 427px wide at
// 16:9 and the font runs a bit over 8px a character, so anything longer starts
// touching the edges — and a taller window makes the virtual screen narrower.
LORE_INTRO := [?]cstring {
	"THE HOLLOW UNDER GREYREACH TOOK THE MINE,",
	"THEN THE MINERS, THEN THE TOWN ABOVE IT.",
	"THE WARDEN BUILT TO KEEP THE DEEP SEALED",
	"HAS SPENT A LONG CENTURY FEEDING IT.",
}

// The three steps of a run, spelled out on the title card.
LORE_OBJECTIVES := [?]cstring {
	"1   FIND THE RUNE-KEY IN THE HOLLOW",
	"2   THE KEY UNSEALS THE WARDEN'S VAULT",
	"3   BREAK THE WARDEN. THAT IS THE WAY OUT.",
}

LORE_CONTROLS := [?]cstring {
	"A D   MOVE",
	"SPACE   JUMP, AGAIN IN AIR TO DOUBLE JUMP",
	"SPACE ON A WALL   WALL JUMP",
	"MOUSE   AIM      LEFT CLICK   SHOOT",
	"E   OPEN A CHEST, AGAIN TO TAKE THE GUN",
}

LORE_WIN_TITLE :: "THE WARDEN FALLS"
LORE_WIN_LINE :: "THE HOLLOW STOPS GROWING. FOR NOW."

LORE_DEAD_TITLE :: "THE HOLLOW TAKES YOU"
LORE_DEAD_LINE :: "THE STONE CLOSES OVER YOU AND RESHAPES ITSELF."

// The one-line goal shown under the map while playing. It is derived from run
// state, so it is always the next thing to actually do. Kept short: the line is
// right-aligned under the map and hangs into the play area.
objective_text :: proc(g: ^Game) -> cstring {
	switch {
	case g.boss_down:
		return "THE WAY OUT IS OPEN"
	case g.player.has_key:
		return "BREAK THE WARDEN"
	case:
		return "FIND THE RUNE-KEY"
	}
}
