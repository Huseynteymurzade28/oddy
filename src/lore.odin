package game

/*
The words the game shows, kept in one place so the title card, the help board
and the end card can never drift apart. The story itself is being rewritten
for the world map (the worlds as layers of the Hollow); this is the
placeholder until then.
*/

GAME_TITLE :: "ODDY"
GAME_TAGLINE :: "A DESCENT INTO THE HOLLOW"

// Lines are kept under about 44 characters: the virtual screen is 427px wide at
// 16:9 and the font runs a bit over 8px a character.
LORE_INTRO := [?]cstring {
	"REACH THE FLAG. ONE TOUCH OF ANYTHING",
	"SHARP AND YOU START AT THE LAST ONE.",
}

// The how-to-play board. The parchment can be under 300px wide on a narrow
// screen and the font is about 8.5px a character, so lines stay under 34.
LORE_HOW_TO := [?]cstring {
	"A D  MOVE     S  DROP THROUGH",
	"SPACE  JUMP, OFF WALLS TOO",
	"SHIFT  DASH, AIMED WITH WASD",
	"ONE DASH IN THE AIR, BACK ON LANDING",
	"ESC  PAUSE",
}

LORE_HOW_TO_TOUCH := [?]cstring {
	"LEFT THUMB  MOVE AND AIM",
	"PULL DOWN TO DROP THROUGH",
	"GREEN  JUMP, OFF WALLS TOO",
	"BLUE  DASH THE WAY YOU AIM",
	"ONE DASH IN THE AIR, BACK ON LANDING",
}

LORE_CLEAR_TITLE :: "LEVEL CLEAR"
