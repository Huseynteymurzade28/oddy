package game

/*
The whole story of the game, kept in one place so the title card, the objective
tracker and the end screens can never drift apart. Nothing here affects the
simulation — it only names what the rules already do:

  the map is rebuilt every run   ->  the Hollow reshapes itself
  a key unseals the boss room    ->  the rune-key opens the warden's vault
  killing the boss wins          ->  the warden is what keeps the Hollow growing
  a different boss each run      ->  the warden wears a new shape every descent
*/

GAME_TITLE :: "ODDY"
GAME_TAGLINE :: "A DESCENT INTO THE HOLLOW"

// Lines are kept under about 44 characters: the virtual screen is 427px wide at
// 16:9 and the font runs a bit over 8px a character, so anything longer starts
// touching the edges — and a taller window makes the virtual screen narrower.
LORE_INTRO := [?]cstring {
	"FIND THE RUNE-KEY. OPEN THE VAULT.",
	"BREAK WHATEVER GUARDS IT.",
}


// The how-to-play board. The parchment can be under 300px wide on a narrow
// screen and the font is about 8.5px a character, so lines stay under 34.
LORE_HOW_TO := [?]cstring {
	"A D  MOVE     S  DROP THROUGH",
	"SPACE  JUMP, AGAIN IN THE AIR",
	"MOUSE  AIM AND SHOOT",
	"E  OPEN CHESTS AND BUY",
	"ESC  PAUSE",
}

LORE_HOW_TO_TOUCH := [?]cstring {
	"LEFT THUMB  MOVE, PULL DOWN TO DROP",
	"GREEN  JUMP, AGAIN IN THE AIR",
	"ORANGE  DRAG TO AIM, HOLD TO FIRE",
	"HELD STILL, IT AIMS BY ITSELF",
	"GOLD  OPEN CHESTS AND BUY",
}

// The win card names whatever was in the vault: "THE OOZE KING FALLS".
LORE_WIN_LINE :: "THE HOLLOW STOPS GROWING. FOR NOW."

LORE_DEAD_TITLE :: "THE HOLLOW TAKES YOU"
LORE_DEAD_LINE :: "THE STONE CLOSES OVER YOU, AND SHIFTS."

// The one-line goal shown under the map while playing. It is derived from run
// state, so it is always the next thing to actually do. Kept short: the line is
// right-aligned under the map and hangs into the play area.
objective_text :: proc(g: ^Game) -> cstring {
	switch {
	case g.boss_down:
		return "THE WAY OUT IS OPEN"
	case g.player.has_key:
		return "THE VAULT IS OPEN"
	case:
		return "FIND THE RUNE-KEY"
	}
}
