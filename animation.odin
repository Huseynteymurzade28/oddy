package game

import rl "vendor:raylib"

// A sprite sheet is a texture cut into a uniform grid of frames, numbered
// left-to-right then top-to-bottom.
Sprite_Sheet :: struct {
	texture: rl.Texture2D,
	frame_w: f32,
	frame_h: f32,
	columns: int,
}

sheet_load :: proc(path: cstring, frame_w, frame_h: int) -> Sprite_Sheet {
	tex := rl.LoadTexture(path)
	return {
		texture = tex,
		frame_w = f32(frame_w),
		frame_h = f32(frame_h),
		columns = max(1, int(tex.width) / frame_w),
	}
}

sheet_source :: proc(s: Sprite_Sheet, index: int, flip: bool) -> rl.Rectangle {
	r := rl.Rectangle {
		x      = f32(index % s.columns) * s.frame_w,
		y      = f32(index / s.columns) * s.frame_h,
		width  = s.frame_w,
		height = s.frame_h,
	}
	if flip {
		r.width = -r.width
	}
	return r
}

// Every entity in the game keeps its position at its feet, so frames are drawn
// with the origin at the bottom centre of the cell.
sheet_draw :: proc(s: Sprite_Sheet, index: int, pos: rl.Vector2, flip: bool, tint := rl.WHITE) {
	dest := rl.Rectangle{pos.x, pos.y, s.frame_w, s.frame_h}
	origin := rl.Vector2{s.frame_w / 2, s.frame_h}
	rl.DrawTexturePro(s.texture, sheet_source(s, index, flip), dest, origin, 0, tint)
}

// A run of consecutive frames inside a sheet.
Clip :: struct {
	first:      int,
	count:      int,
	frame_time: f32,
	loop:       bool,
}

Animator :: struct {
	sheet:    ^Sprite_Sheet,
	clip:     Clip,
	frame:    int,
	timer:    f32,
	finished: bool,
}

// Switching to the clip that is already playing is a no-op, so callers can set
// the desired clip every frame without restarting it.
animator_play :: proc(a: ^Animator, sheet: ^Sprite_Sheet, clip: Clip) {
	if a.sheet == sheet && a.clip == clip {
		return
	}
	a.sheet = sheet
	a.clip = clip
	a.frame = 0
	a.timer = 0
	a.finished = false
}

animator_update :: proc(a: ^Animator, dt: f32) {
	if a.clip.count <= 1 || a.clip.frame_time <= 0 || a.finished {
		return
	}
	a.timer += dt
	for a.timer >= a.clip.frame_time {
		a.timer -= a.clip.frame_time
		a.frame += 1
		if a.frame >= a.clip.count {
			if a.clip.loop {
				a.frame = 0
			} else {
				a.frame = a.clip.count - 1
				a.finished = true
				break
			}
		}
	}
}

animator_draw :: proc(a: Animator, pos: rl.Vector2, flip: bool, tint := rl.WHITE) {
	if a.sheet == nil {
		return
	}
	sheet_draw(a.sheet^, a.clip.first + a.frame, pos, flip, tint)
}
