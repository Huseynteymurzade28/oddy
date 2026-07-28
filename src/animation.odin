package game

import rl "vendor:raylib"

/*
Every animation in the art pack is its own file: a strip of equally sized cells
read left-to-right, then top-to-bottom. So one loaded texture is one animation,
and `Anim` carries both the image and its timing.
*/
Anim :: struct {
	texture:    rl.Texture2D,
	frame_w:    f32,
	frame_h:    f32,
	columns:    int,
	count:      int, // usable frames; trailing cells in a sheet are often blank
	frame_time: f32,
	loop:       bool,
	// Distance from the top of a cell down to the point that lines up with the
	// entity's position. The sprites are drawn from their feet, but the cells
	// are padded, so this differs per creature.
	anchor_y:   f32,
}

// `anchor_y` of -1 means "the bottom of the cell", which is right for anything
// authored without padding (the player, the chest).
anim_load :: proc(
	path: cstring,
	frame_w, frame_h, count: int,
	frame_time: f32 = 0,
	loop := false,
	anchor_y: f32 = -1,
) -> Anim {
	tex := rl.LoadTexture(path)
	return {
		texture = tex,
		frame_w = f32(frame_w),
		frame_h = f32(frame_h),
		columns = max(1, int(tex.width) / frame_w),
		count = count,
		frame_time = frame_time,
		loop = loop,
		anchor_y = anchor_y < 0 ? f32(frame_h) : anchor_y,
	}
}

anim_source :: proc(a: ^Anim, frame: int, flip: bool) -> rl.Rectangle {
	r := rl.Rectangle {
		x      = f32(frame % a.columns) * a.frame_w,
		y      = f32(frame / a.columns) * a.frame_h,
		width  = a.frame_w,
		height = a.frame_h,
	}
	if flip {
		r.width = -r.width
	}
	return r
}

anim_draw_frame :: proc(
	a: ^Anim,
	frame: int,
	pos: rl.Vector2,
	flip: bool,
	tint := rl.WHITE,
	scale: f32 = 1,
) {
	if a.texture.id == 0 {
		return
	}
	dest := rl.Rectangle{pos.x, pos.y, a.frame_w * scale, a.frame_h * scale}
	origin := rl.Vector2{a.frame_w * scale / 2, a.anchor_y * scale}
	rl.DrawTexturePro(a.texture, anim_source(a, frame, flip), dest, origin, 0, tint)
}

// Draws one cell centred on `pos` and turned to face `angle` (degrees). Used by
// anything that points along a heading instead of standing on the ground.
anim_draw_rotated :: proc(
	a: ^Anim,
	frame: int,
	pos: rl.Vector2,
	angle: f32,
	tint := rl.WHITE,
	scale: f32 = 1,
) {
	if a.texture.id == 0 {
		return
	}
	dest := rl.Rectangle{pos.x, pos.y, a.frame_w * scale, a.frame_h * scale}
	origin := rl.Vector2{dest.width / 2, dest.height / 2}
	rl.DrawTexturePro(a.texture, anim_source(a, frame, false), dest, origin, angle, tint)
}

// ------------------------------------------------------------------ playback ---

Animator :: struct {
	anim:     ^Anim,
	frame:    int,
	timer:    f32,
	finished: bool,
}

// Re-playing the animation that is already running is a no-op, so callers can
// set the animation they want every frame without ever restarting it.
animator_play :: proc(a: ^Animator, anim: ^Anim) {
	if a.anim == anim {
		return
	}
	a.anim = anim
	a.frame = 0
	a.timer = 0
	a.finished = false
}

// Restart even if it is the animation already playing — for hit reactions and
// attacks, which have to replay from the first frame on every trigger.
animator_restart :: proc(a: ^Animator, anim: ^Anim) {
	a.anim = anim
	a.frame = 0
	a.timer = 0
	a.finished = false
}

animator_update :: proc(a: ^Animator, dt: f32) {
	if a.anim == nil || a.anim.count <= 1 || a.anim.frame_time <= 0 || a.finished {
		return
	}
	a.timer += dt
	for a.timer >= a.anim.frame_time {
		a.timer -= a.anim.frame_time
		a.frame += 1
		if a.frame >= a.anim.count {
			if a.anim.loop {
				a.frame = 0
			} else {
				a.frame = a.anim.count - 1
				a.finished = true
				break
			}
		}
	}
}

// How far through a non-looping animation we are, 0..1. Attacks use it to decide
// when the damaging part of the swing happens.
animator_progress :: proc(a: Animator) -> f32 {
	if a.anim == nil || a.anim.count <= 0 {
		return 1
	}
	return f32(a.frame) / f32(a.anim.count - 1 if a.anim.count > 1 else 1)
}

animator_draw :: proc(a: Animator, pos: rl.Vector2, flip: bool, tint := rl.WHITE, scale: f32 = 1) {
	if a.anim == nil {
		return
	}
	anim_draw_frame(a.anim, a.frame, pos, flip, tint, scale)
}
