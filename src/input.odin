package game

import "core:math"
import rl "../libs/raylib"

/*
What the player asked for this frame, whichever device it came from. Nothing
outside this file reads the keyboard, the mouse or the touch screen: the game
reads `g.input`, so the same rules run on a desktop and on a phone.

On a phone the screen is split in two:

  left half   a floating stick — wherever the thumb lands is its centre.
              Sideways moves, pulling down drops through platforms.
  right half  the jump button sits in the corner; a touch anywhere else on
              that side is an aim stick that fires while held. Held still,
              the gun picks the nearest thing it can see; dragged, it points
              the way you drag, and keeps pointing there until you let go,
              even if the thumb drifts back to the middle.

The interact button only exists while there is something in reach.

Desktop builds can play with the touch layout too, using the mouse as one
finger: build with `-define:TOUCH=true`.
*/

TOUCH_ON_DESKTOP :: #config(TOUCH, false)
TOUCH_CONTROLS :: IS_MOBILE || TOUCH_ON_DESKTOP

STICK_RADIUS :: 26.0 // how far the knob travels, in virtual pixels
STICK_DEAD :: 3.0
AIM_RADIUS :: 26.0 // the aim stick's reach; past it the centre follows the thumb
AIM_DRAG :: 5.0 // how far the fire thumb moves before it counts as aiming
BUTTON_RADIUS :: 27.0
INTERACT_RADIUS :: 19.0

Input :: struct {
	move:      f32, // -1 .. 1
	down:      bool,
	jump:      bool, // pressed this frame
	jump_held: bool,
	fire:      bool,
	interact:  bool,
	confirm:   bool, // a key that presses the marked menu button
	nav:       int, // a key that moves the menu marker: -1 up, +1 down
	pause:     bool, // pause in play; back out of a menu

	// Where to aim. A mouse gives a point in the world; a dragged thumb gives a
	// direction; a plain tap on fire gives neither, and the gun picks a target.
	aim_point: rl.Vector2,
	has_point: bool,
	aim_dir:   rl.Vector2,
	has_dir:   bool,
}

// The thumbs currently down, remembered between frames so a touch keeps the
// job it started with even when it slides across the middle of the screen.
Touch_State :: struct {
	stick_id:     i32,
	stick_origin: rl.Vector2,
	stick_pos:    rl.Vector2,
	fire_id:      i32,
	fire_origin:  rl.Vector2,
	fire_pos:     rl.Vector2,
	aiming:       bool, // this fire thumb has been dragged, so it owns the aim
	aim_dir:      rl.Vector2,
	jump_id:      i32,
	interact_id:  i32,
	seen:         [dynamic]i32, // ids that were down last frame
	any_tap:      bool, // a new touch began this frame, anywhere
}

NO_TOUCH :: -1

touch_init :: proc(t: ^Touch_State) {
	t.stick_id = NO_TOUCH
	t.fire_id = NO_TOUCH
	t.jump_id = NO_TOUCH
	t.interact_id = NO_TOUCH
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

// Where the aim stick rests when no thumb is on it. It is only a hint: the
// stick starts wherever the thumb lands.
fire_button_pos :: proc() -> rl.Vector2 {
	view := view_size()
	return {view.x - 110, view.y - 46}
}

interact_button_pos :: proc() -> rl.Vector2 {
	view := view_size()
	return {view.x - 44, view.y - 104}
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
	if rl.IsKeyDown(.A) || rl.IsKeyDown(.LEFT) {
		in_.move -= 1
	}
	if rl.IsKeyDown(.D) || rl.IsKeyDown(.RIGHT) {
		in_.move += 1
	}
	in_.down = rl.IsKeyDown(.S) || rl.IsKeyDown(.DOWN)
	in_.jump = rl.IsKeyPressed(.SPACE) || rl.IsKeyPressed(.W) || rl.IsKeyPressed(.UP)
	in_.jump_held = rl.IsKeyDown(.SPACE) || rl.IsKeyDown(.W) || rl.IsKeyDown(.UP)
	in_.fire = rl.IsMouseButtonDown(.LEFT)
	in_.interact = rl.IsKeyPressed(.E)
	in_.confirm = rl.IsKeyPressed(.SPACE) || rl.IsKeyPressed(.ENTER)
	in_.nav = menu_nav()
	in_.pause = rl.IsKeyPressed(.ESCAPE) || rl.IsKeyPressed(.P)
	in_.aim_point = rl.GetScreenToWorld2D(rl.GetMousePosition(), g.camera)
	in_.has_point = true
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
	if !contains(ids[:], t.fire_id) {
		t.fire_id = NO_TOUCH
	}
	if !contains(ids[:], t.jump_id) {
		t.jump_id = NO_TOUCH
	}
	if !contains(ids[:], t.interact_id) {
		t.interact_id = NO_TOUCH
	}

	t.any_tap = false
	interact_shown := g.state == .Playing && interact_available(g)

	for id, i in ids {
		p := pos[i]
		if id == t.stick_id {
			t.stick_pos = p
			continue
		}
		if id == t.fire_id {
			t.fire_pos = p
			continue
		}
		if id == t.jump_id || id == t.interact_id || contains(t.seen[:], id) {
			continue // a touch that started on nothing stays on nothing
		}

		// A new touch: it takes whichever job its position asks for.
		t.any_tap = true
		switch {
		case g.state == .Playing && rl.CheckCollisionPointRec(p, grow(pause_button_rect(), 6)):
			in_.pause = true
		case interact_shown && rl.Vector2Distance(p, interact_button_pos()) < INTERACT_RADIUS + 6:
			t.interact_id = id
			in_.interact = true
		case rl.Vector2Distance(p, jump_button_pos()) < BUTTON_RADIUS + 10:
			t.jump_id = id
			in_.jump = true
		case p.x < view.x * 0.45:
			t.stick_id = id
			t.stick_origin = p
			t.stick_pos = p
		case:
			t.fire_id = id
			t.fire_origin = p
			t.fire_pos = p
			t.aiming = false
		}
	}

	clear(&t.seen)
	append(&t.seen, ..ids[:])

	if t.stick_id != NO_TOUCH {
		d := t.stick_pos - t.stick_origin
		// The centre follows a thumb that wanders too far, so the stick never
		// needs re-planting halfway through a fight.
		if l := rl.Vector2Length(d); l > STICK_RADIUS {
			t.stick_origin += d * (1 - STICK_RADIUS / l)
			d = t.stick_pos - t.stick_origin
		}
		if abs(d.x) > STICK_DEAD {
			in_.move = clamp(d.x / (STICK_RADIUS * 0.6), -1, 1)
		}
		in_.down = d.y > STICK_RADIUS * 0.6 && abs(d.x) < d.y
	}

	in_.jump_held = t.jump_id != NO_TOUCH
	in_.fire = t.fire_id != NO_TOUCH
	if in_.fire {
		d := t.fire_pos - t.fire_origin
		l := rl.Vector2Length(d)
		// Like the move stick, the centre is dragged along behind a thumb
		// that goes past the rim, so swinging the aim round is always a short
		// move whichever way it was pointing.
		if l > AIM_RADIUS {
			t.fire_origin += d * (1 - AIM_RADIUS / l)
			d = t.fire_pos - t.fire_origin
			l = AIM_RADIUS
		}
		if l > AIM_DRAG {
			t.aiming = true
		}
		if t.aiming && l > 2 {
			t.aim_dir = d / l
		}
		if t.aiming {
			in_.aim_dir = t.aim_dir
			in_.has_dir = true
		}
	} else {
		t.aiming = false
	}

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
		if rl.IsKeyPressed(.SPACE) {in_.jump = true}
		if rl.IsKeyDown(.SPACE) {in_.jump_held = true}
		if rl.IsKeyPressed(.E) {in_.interact = true}
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

// The angle the gun should point when the player has not said where: the
// nearest live creature in this room that the gun can actually see, or else
// straight ahead.
auto_aim :: proc(g: ^Game) -> (angle: f32, target: rl.Vector2, found: bool) {
	p := &g.player
	hand := player_hand(p^)
	best_d := p.weapon.range
	for e in g.enemies {
		if !e.alive || room_coords(e.pos) != g.room {
			continue
		}
		c := enemy_centre(e)
		d := rl.Vector2Distance(hand, c)
		if d >= best_d || !line_of_sight(&g.map_tiles, hand, c) {
			continue
		}
		best_d = d
		target = c
		found = true
	}
	if found {
		to := target - hand
		return math.atan2(to.y, to.x), target, true
	}
	return p.flip ? math.PI : 0, {}, false
}

// Is there any rock between two points? Sampled every half tile, which is fine
// for a gun that only fires at what is in the same room.
line_of_sight :: proc(m: ^Tilemap, a, b: rl.Vector2) -> bool {
	d := b - a
	steps := int(rl.Vector2Length(d) / (TILE / 2)) + 1
	for i in 1 ..< steps {
		p := a + d * (f32(i) / f32(steps))
		if is_blocking(tile_at(m, int(math.floor(p.x / TILE)), int(math.floor(p.y / TILE)))) {
			return false
		}
	}
	return true
}

// Is there a chest or a stall crate close enough to use? Decides whether the
// interact button is on screen at all.
interact_available :: proc(g: ^Game) -> bool {
	if g.player.dead {
		return false
	}
	if shop_slot_in_reach(g.shop, g.player) >= 0 {
		return true
	}
	for c in g.chests {
		if !c.taken && chest_in_reach(c, g.player) {
			return true
		}
	}
	return false
}
