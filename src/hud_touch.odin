package game

import "core:math"
import rl "../libs/raylib"

/*
The on-screen controls for a touch screen. Each one is a soft, coloured disc
with a white icon, so they read at a glance without reading a word: green to
jump, orange to shoot, gold to use. They sink a little and light up under a
thumb. Positions come from `input.odin`, which reads the touches against the
same numbers.
*/

@(private = "file")
JUMP_COLOUR :: rl.Color{86, 206, 140, 255}
@(private = "file")
FIRE_COLOUR :: rl.Color{255, 128, 82, 255}
@(private = "file")
USE_COLOUR :: rl.Color{255, 198, 76, 255}
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
		// Little arrows on the pad say which way it goes.
		a := rl.Color{255, 255, 255, held ? 120 : 80}
		for side in ([2]f32{-1, 1}) {
			tip := base + {side * (STICK_RADIUS + 1), 0}
			tri(tip * s, (tip + {-side * 4, 3.5}) * s, (tip + {-side * 4, -3.5}) * s, a)
		}
	}

	// --- aim stick: the gun goes where it is dragged ---------------------------
	{
		held := t.fire_id != NO_TOUCH
		base := held ? t.fire_origin : fire_button_pos()
		draw_pad(base, AIM_RADIUS + 6, FIRE_COLOUR, held)
		knob := base
		if held && t.aiming {
			knob += t.aim_dir * min(rl.Vector2Length(t.fire_pos - t.fire_origin), AIM_RADIUS)
		}
		draw_knob(knob, 14, FIRE_COLOUR, held)
		draw_crosshair_icon(knob, held)
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

	// --- use: only while something is in reach, and pulsing ------------------
	if interact_available(g) {
		held := t.interact_id != NO_TOUCH
		c := interact_button_pos()
		pulse := 0.5 + 0.5 * math.sin(g.time * 6)
		ring(c, INTERACT_RADIUS + 3 + pulse * 3, 1.5, {255, 214, 110, u8(40 + pulse * 120)})
		r := draw_button(c, INTERACT_RADIUS, USE_COLOUR, held)
		k := r / INTERACT_RADIUS
		// An open hand is a lot of pixels; a pointing hand reads as "touch".
		fill_rect(c.x - 2 * k, c.y - 9 * k, 4 * k, 11 * k, ICON)
		fill_rect(c.x - 6 * k, c.y - 1 * k, 12 * k, 8 * k, ICON)
		fill_rect(c.x - 7 * k, c.y + 1 * k, 2 * k, 4 * k, ICON)
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

@(private = "file")
draw_crosshair_icon :: proc(c: rl.Vector2, held: bool) {
	col := ICON
	ring(c, 6, 1.5, col)
	fill_rect(c.x - 10, c.y - 0.75, 5, 1.5, col)
	fill_rect(c.x + 5, c.y - 0.75, 5, 1.5, col)
	fill_rect(c.x - 0.75, c.y - 10, 1.5, 5, col)
	fill_rect(c.x - 0.75, c.y + 5, 1.5, 5, col)
	if held {
		fill_circle(c, 1.5, col)
	}
}
