package game

import rl "../libs/raylib"

/*
What the player asked for this frame, whichever device it came from. Nothing
outside this file reads the keyboard or the touch screen: the game reads
`g.input`, so the same rules run on a desktop and on a phone.

On a phone the screen is split in two:

  left half   a floating stick: wherever the thumb lands is its centre. It
              steers, aims the dash in any of eight directions, and pulled
              down it drops through platforms.
  right half  two buttons in the corner: jump, and dash beside it.

Desktop builds can play with the touch layout too, using the mouse as one
finger: build with `-define:TOUCH=true`.
*/

TOUCH_ON_DESKTOP :: #config(TOUCH, false)
TOUCH_CONTROLS :: IS_MOBILE || TOUCH_ON_DESKTOP

STICK_RADIUS :: 26.0 // how far the knob travels, in virtual pixels
STICK_DEAD :: 3.0
BUTTON_RADIUS :: 27.0
DASH_RADIUS :: 23.0

Input :: struct {
	move:      f32, // -1 .. 1, left to right
	move_y:    f32, // -1 .. 1, up to down: only aims the dash
	down:      bool, // drop through a platform
	jump:      bool, // pressed this frame
	jump_held: bool,
	dash:      bool, // pressed this frame
	confirm:   bool, // a key that presses the marked menu button
	nav:       int, // a key that moves the menu marker: -1 up, +1 down
	pause:     bool, // pause in play; back out of a menu
}

// The thumbs currently down, remembered between frames so a touch keeps the
// job it started with even when it slides across the middle of the screen.
Touch_State :: struct {
	stick_id:     i32,
	stick_origin: rl.Vector2,
	stick_pos:    rl.Vector2,
	jump_id:      i32,
	dash_id:      i32,
	seen:         [dynamic]i32, // ids that were down last frame
	any_tap:      bool, // a new touch began this frame, anywhere
}

NO_TOUCH :: -1

touch_init :: proc(t: ^Touch_State) {
	t.stick_id = NO_TOUCH
	t.jump_id = NO_TOUCH
	t.dash_id = NO_TOUCH
}

touch_destroy :: proc(t: ^Touch_State) {
	delete(t.seen)
}

// Where the on-screen buttons sit, in virtual pixels. The HUD draws them from
// the same numbers.
jump_button_pos :: proc() -> rl.Vector2 {
	view := view_size()
	return {view.x - 38, view.y - 40}
}

// The dash sits up and to the left of jump, where the thumb rolls to it.
dash_button_pos :: proc() -> rl.Vector2 {
	view := view_size()
	return {view.x - 98, view.y - 62}
}

stick_hint_pos :: proc() -> rl.Vector2 {
	view := view_size()
	return {52, view.y - 48}
}

// A screen position in the virtual space the HUD is laid out in.
@(private = "file")
to_virtual :: proc(p: rl.Vector2) -> rl.Vector2 {
	return p / hud_scale()
}

@(private = "file")
touch_points :: proc() -> (ids: [dynamic]i32, pos: [dynamic]rl.Vector2) {
	ids = make([dynamic]i32, context.temp_allocator)
	pos = make([dynamic]rl.Vector2, context.temp_allocator)
	when IS_MOBILE {
		for i in 0 ..< rl.GetTouchPointCount() {
			append(&ids, rl.GetTouchPointId(i))
			append(&pos, to_virtual(rl.GetTouchPosition(i)))
		}
	} else {
		// The mouse is a single finger that never lifts its id.
		if rl.IsMouseButtonDown(.LEFT) {
			append(&ids, 0)
			append(&pos, to_virtual(rl.GetMousePosition()))
		}
	}
	return
}

@(private = "file")
contains :: proc(ids: []i32, id: i32) -> bool {
	for x in ids {
		if x == id {
			return true
		}
	}
	return false
}

input_poll :: proc(g: ^Game) -> Input {
	when TOUCH_CONTROLS {
		return poll_touch(g)
	} else {
		return poll_desktop(g)
	}
}

@(private = "file")
poll_desktop :: proc(g: ^Game) -> Input {
	in_: Input
	key :: rl.IsKeyDown
	hit :: rl.IsKeyPressed
	if key(.A) || key(.LEFT) {in_.move -= 1}
	if key(.D) || key(.RIGHT) {in_.move += 1}
	if key(.W) || key(.UP) {in_.move_y -= 1}
	if key(.S) || key(.DOWN) {in_.move_y += 1}
	in_.down = key(.S) || key(.DOWN)
	in_.jump = hit(.SPACE) || hit(.C) || hit(.J)
	in_.jump_held = key(.SPACE) || key(.C) || key(.J)
	in_.dash = hit(.LEFT_SHIFT) || hit(.RIGHT_SHIFT) || hit(.X) || hit(.K)
	in_.confirm = hit(.SPACE) || hit(.ENTER)
	in_.nav = menu_nav()
	in_.pause = hit(.ESCAPE) || hit(.P)
	return in_
}

@(private = "file")
poll_touch :: proc(g: ^Game) -> Input {
	t := &g.touch
	in_: Input
	ids, pos := touch_points()
	view := view_size()

	// Thumbs that lifted give their job back.
	if !contains(ids[:], t.stick_id) {
		t.stick_id = NO_TOUCH
	}
	if !contains(ids[:], t.jump_id) {
		t.jump_id = NO_TOUCH
	}
	if !contains(ids[:], t.dash_id) {
		t.dash_id = NO_TOUCH
	}

	t.any_tap = false
	for id, i in ids {
		p := pos[i]
		if id == t.stick_id {
			t.stick_pos = p
			continue
		}
		if id == t.jump_id || id == t.dash_id || contains(t.seen[:], id) {
			continue // a touch that started on nothing stays on nothing
		}

		// A new touch: it takes whichever job its position asks for. The two
		// buttons split the right side between them by distance, so a thumb
		// landing between them still presses one.
		t.any_tap = true
		to_jump := rl.Vector2Distance(p, jump_button_pos())
		to_dash := rl.Vector2Distance(p, dash_button_pos())
		switch {
		case g.state == .Playing && rl.CheckCollisionPointRec(p, grow(pause_button_rect(), 6)):
			in_.pause = true
		case p.x < view.x * 0.45:
			t.stick_id = id
			t.stick_origin = p
			t.stick_pos = p
		case to_dash < to_jump:
			t.dash_id = id
			in_.dash = true
		case:
			t.jump_id = id
			in_.jump = true
		}
	}

	clear(&t.seen)
	append(&t.seen, ..ids[:])

	if t.stick_id != NO_TOUCH {
		d := t.stick_pos - t.stick_origin
		// The centre follows a thumb that wanders too far, so the stick never
		// needs re-planting halfway through a level.
		if l := rl.Vector2Length(d); l > STICK_RADIUS {
			t.stick_origin += d * (1 - STICK_RADIUS / l)
			d = t.stick_pos - t.stick_origin
		}
		if rl.Vector2Length(d) > STICK_DEAD {
			in_.move = clamp(d.x / (STICK_RADIUS * 0.6), -1, 1)
			in_.move_y = clamp(d.y / (STICK_RADIUS * 0.6), -1, 1)
		}
		in_.down = d.y > STICK_RADIUS * 0.6 && abs(d.x) < d.y
	}
	in_.jump_held = t.jump_id != NO_TOUCH

	// Menus have their own buttons (see `ui.odin`). Back on Android, or
	// Escape with the mouse, pauses. Back arrives as a press and a release in
	// the same frame, which `IsKeyPressed` never sees, so it is read off the
	// queue of presses.
	for k := rl.GetKeyPressed(); k != .KEY_NULL; k = rl.GetKeyPressed() {
		if k == .BACK || k == .ESCAPE {
			in_.pause = true
		}
	}
	when !IS_MOBILE {
		// Keep the keyboard working while testing the touch layout on a desktop.
		if rl.IsKeyDown(.A) {in_.move -= 1}
		if rl.IsKeyDown(.D) {in_.move += 1}
		if rl.IsKeyDown(.W) {in_.move_y -= 1}
		if rl.IsKeyDown(.S) {in_.move_y += 1}
		if rl.IsKeyPressed(.SPACE) {in_.jump = true}
		if rl.IsKeyDown(.SPACE) {in_.jump_held = true}
		if rl.IsKeyPressed(.LEFT_SHIFT) {in_.dash = true}
		if rl.IsKeyPressed(.ENTER) {in_.confirm = true}
		in_.nav = menu_nav()
	}
	return in_
}

@(private = "file")
menu_nav :: proc() -> int {
	if rl.IsKeyPressed(.UP) || rl.IsKeyPressed(.W) {
		return -1
	}
	if rl.IsKeyPressed(.DOWN) || rl.IsKeyPressed(.S) {
		return 1
	}
	return 0
}

@(private = "file")
grow :: proc(r: rl.Rectangle, by: f32) -> rl.Rectangle {
	return {r.x - by, r.y - by, r.width + by * 2, r.height + by * 2}
}
