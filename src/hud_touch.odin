package game

import rl "../libs/raylib"

/*
The on-screen controls for a touch screen. Each one is a soft, coloured disc
with a white icon, so they read at a glance without reading a word: green to
jump, blue to dash. They sink a little and light up under a
thumb. Positions come from `input.odin`, which reads the touches against the
same numbers.
*/

@(private = "file")
JUMP_COLOUR :: rl.Color{86, 206, 140, 255}
@(private = "file")
DASH_COLOUR :: rl.Color{110, 170, 255, 255}
@(private = "file")
STICK_COLOUR :: rl.Color{150, 170, 255, 255}
@(private = "file")
ICON :: rl.Color{255, 255, 255, 235}

draw_touch_controls :: proc(g: ^Game) {
	t := &g.touch
	s := hud_scale()

	// --- move stick: wherever the thumb landed, or a hint where it usually goes
	{
		held := t.stick_id != NO_TOUCH
		base := held ? t.stick_origin : stick_hint_pos()
		draw_pad(base, STICK_RADIUS + 6, STICK_COLOUR, held)
		knob := base
		if held {
			d := t.stick_pos - t.stick_origin
			if l := rl.Vector2Length(d); l > STICK_RADIUS {
				d *= STICK_RADIUS / l
			}
			knob += d
		}
		draw_knob(knob, 12, STICK_COLOUR, held)
		// Where a dash would go right now: a bright wedge on the rim.
		if held {
			d := t.stick_pos - t.stick_origin
			k: f32 = STICK_RADIUS * 0.6
			aim := dash_aim(clamp(d.x / k, -1, 1), clamp(d.y / k, -1, 1), g.player.flip)
			tip := base + aim * (STICK_RADIUS + 7)
			side := rl.Vector2{-aim.y, aim.x}
			back := tip - aim * 7
			colour := DASH_COLOUR
			colour.a = g.player.dashes > 0 ? 230 : 90
			tri(tip * s, (back + side * 5) * s, (back - side * 5) * s, colour)
		}
		// Little arrows on the pad: it goes every way.
		a := rl.Color{255, 255, 255, held ? 120 : 80}
		for d in ([4]rl.Vector2{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) {
			tip := base + d * (STICK_RADIUS + 1)
			side := rl.Vector2{-d.y, d.x}
			tri(tip * s, (tip - d * 4 + side * 3.5) * s, (tip - d * 4 - side * 3.5) * s, a)
		}
	}

	// --- jump ------------------------------------------------------------------
	{
		held := t.jump_id != NO_TOUCH
		c := jump_button_pos()
		r := draw_button(c, BUTTON_RADIUS, JUMP_COLOUR, held)
		k := r / BUTTON_RADIUS
		// A chunky up arrow.
		shadow := rl.Color{0, 0, 0, 60}
		for pass in 0 ..< 2 {
			off := pass == 0 ? rl.Vector2{0, 1.5} : {}
			col := pass == 0 ? shadow : ICON
			p := c + off
			tri((p + {0, -11} * k) * s, (p + {-10, 0} * k) * s, (p + {10, 0} * k) * s, col)
			fill_rect(p.x - 4 * k, p.y - 0.5, 8 * k, 9 * k, col)
		}
	}

	// --- dash: dimmer while it is spent ---------------------------------------
	{
		held := t.dash_id != NO_TOUCH
		c := dash_button_pos()
		idle: u8 = g.player.dashes > 0 ? 150 : 70
		r := draw_button(c, DASH_RADIUS, DASH_COLOUR, held, idle)
		k := r / DASH_RADIUS
		// Two chevrons: a burst forward.
		w := 2.2 * k * s
		for i in 0 ..< 2 {
			x := c.x + (f32(i) * 6 - 4) * k
			rl.DrawLineEx({x - 3 * k, c.y - 6 * k} * s, {x + 3 * k, c.y} * s, w, ICON)
			rl.DrawLineEx({x + 3 * k, c.y} * s, {x - 3 * k, c.y + 6 * k} * s, w, ICON)
		}
	}
}

// A button: a drop shadow, a body lighter in the middle, a bright rim and a
// gloss along the top. Returns the radius it was drawn at, which is a little
// smaller while it is held, so the icon can shrink with it.
@(private = "file")
draw_button :: proc(c: rl.Vector2, r: f32, colour: rl.Color, held: bool, idle_alpha: u8 = 150) -> f32 {
	s := hud_scale()
	r := held ? r * 0.92 : r
	body := colour
	body.a = held ? 230 : idle_alpha
	centre := lerp_color(body, {255, 255, 255, body.a}, 0.35)
	fill_circle(c + {0, 2.5}, r, {10, 8, 20, 70})
	rl.DrawCircleGradient(c * s, r * s, centre, body)
	ring(c, r, 1.5, {255, 255, 255, held ? 230 : 150})
	rl.DrawRing(c * s, (r - 4) * s, (r - 2.5) * s, 205, 335, 24, {255, 255, 255, held ? 90 : 60})
	return r
}

// The base of a stick: a see-through disc with a coloured rim.
@(private = "file")
draw_pad :: proc(c: rl.Vector2, r: f32, colour: rl.Color, held: bool) {
	fill_circle(c, r, {14, 12, 26, held ? 80 : 30})
	rim := colour
	rim.a = held ? 200 : 90
	ring(c, r, 1.5, rim)
}

@(private = "file")
draw_knob :: proc(c: rl.Vector2, r: f32, colour: rl.Color, held: bool) {
	draw_button(c, r, colour, held, 105)
}
