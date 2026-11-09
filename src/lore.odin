package game

/*
The words the game shows, kept in one place so the title, the map, the help
board and the cards can never drift apart.

The story, such as it is: far under the town of Greyreach is the Hollow, and
the Hollow goes down in layers. At the top it has gone to garden; below that
is a town the water took long ago; at the bottom is its warm heart. Something
keeps the way down from each layer to the next. Oddy goes down anyway.
*/

GAME_TITLE :: "ODDY"
GAME_TAGLINE :: "ALL THE WAY DOWN THE HOLLOW"

// Lines are kept under about 44 characters: the virtual screen is 427px wide at
// 16:9 and the font runs a bit over 8px a character.
LORE_INTRO := [?]cstring {
	"REACH THE TROPHY. ONE TOUCH OF ANYTHING",
	"SHARP AND YOU START AT THE LAST FLAG.",
}

// The how-to-play board. The parchment can be under 300px wide on a narrow
// screen and the font is about 8.5px a character, so lines stay under 34.
LORE_HOW_TO := [?]cstring {
	"A D  MOVE     S  DROP THROUGH",
	"SPACE  JUMP, OFF WALLS TOO",
	"SHIFT  DASH, AIMED WITH WASD",
	"LAND ON CREATURES. DASH INTO CRATES.",
	"IN WATER, TAP JUMP TO SWIM.",
}

LORE_HOW_TO_TOUCH := [?]cstring {
	"LEFT THUMB  MOVE AND AIM",
	"PULL DOWN TO DROP THROUGH",
	"GREEN  JUMP, OFF WALLS TOO",
	"BLUE  DASH THE WAY YOU AIM",
	"LAND ON CREATURES. DASH INTO CRATES.",
}

LORE_CLEAR_TITLE :: "LEVEL CLEAR"
LORE_SECRET_TITLE :: "SECRET EXIT"

// Two lines under each world's name on the map.
WORLD_BLURBS := [WORLDS][2]cstring {
	{"THE TOP OF THE HOLLOW, GONE TO GARDEN.", "SOMETHING BIG AND GREEN KEEPS THE WAY DOWN."},
	{"A TOWN THE WATER TOOK, LONG AGO.", "HER WINGS FILL THE OLD HALL."},
	{"THE HOLLOW'S WARM HEART.", "A STONE THAT WALKS STANDS GUARD."},
}

// The card after the last boss.
LORE_END_TITLE :: "THE HOLLOW IS QUIET"
LORE_END_LINE :: "ODDY CLIMBS BACK UP TO THE SUN."
