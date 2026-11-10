package game

import "core:math"
import rl "../libs/raylib"

/*
What happens to the picture after the world is drawn. The level, its light
and its air all go into one off-screen picture the size of the window; then:

  bloom     whatever is bright spills a little light over its edges. The
            picture is shrunk and only its highlights kept, then shrunk
            again and again (each step blurs it), and the stack is added
            back over the full-size one. Clouds and the sun glow softly
            round the edges of the ground, lava and crystals burn, Lumi
            shines.
  vignette  the corners fall away a little, to hold the eye in the middle.

Picking out the highlights is the one shader in the game. If it does not
compile on some phone, the bloom is simply left out.

The menus and the HUD are drawn afterwards, straight to the window.
*/

BLOOM_STEPS :: 5
// How strongly the glow is added back.
BLOOM_GAIN :: 0.5

// How bright a pixel has to be before it glows, per world: daylight and
// white cloud set the bar high in the first two; the deep is dimmer, and
// there it is the lava that should burn.
BLOOM_THRESHOLD := [Zone]f32 {
	.Mossy   = 0.80,
	.Drowned = 0.84,
	.Ember   = 0.64,
}

when IS_MOBILE {
	@(private = "file")
	HIGHLIGHTS_FS: cstring : `#version 100
precision mediump float;
varying vec2 fragTexCoord;
uniform sampler2D texture0;
uniform float threshold;
void main() {
	vec3 c = texture2D(texture0, fragTexCoord).rgb;
	float luma = dot(c, vec3(0.299, 0.587, 0.114));
	float v = mix(luma, max(c.r, max(c.g, c.b)), 0.35);
	float k = clamp((v - threshold) / (1.0 - threshold), 0.0, 1.0);
	gl_FragColor = vec4(c * k, 1.0);
}
`
} else {
	@(private = "file")
	HIGHLIGHTS_FS: cstring : `#version 330
in vec2 fragTexCoord;
uniform sampler2D texture0;
uniform float threshold;
out vec4 finalColor;
void main() {
	vec3 c = texture(texture0, fragTexCoord).rgb;
	float luma = dot(c, vec3(0.299, 0.587, 0.114));
	float v = mix(luma, max(c.r, max(c.g, c.b)), 0.35);
	float k = clamp((v - threshold) / (1.0 - threshold), 0.0, 1.0);
	finalColor = vec4(c * k, 1.0);
}
`
}

Post :: struct {
	scene:      rl.RenderTexture2D,
	size:       [2]i32,
	bloom:      [BLOOM_STEPS]rl.RenderTexture2D,
	vignette:   rl.Texture2D,
	highlights: rl.Shader,
	threshold:  i32, // the shader's uniform
	loaded:     bool,
	bloom_ok:   bool,
}

post_destroy :: proc(p: ^Post) {
	if p.scene.id != 0 {
		rl.UnloadRenderTexture(p.scene)
		for b in p.bloom {
			rl.UnloadRenderTexture(b)
		}
	}
	if p.vignette.id != 0 {
		rl.UnloadTexture(p.vignette)
	}
	if p.bloom_ok {
		rl.UnloadShader(p.highlights)
	}
	p^ = {}
}

@(private = "file")
post_fit :: proc(p: ^Post) {
	size := [2]i32{rl.GetScreenWidth(), rl.GetScreenHeight()}
	if p.scene.id != 0 && p.size == size {
		return
	}
	if p.scene.id != 0 {
		rl.UnloadRenderTexture(p.scene)
		for b in p.bloom {
			rl.UnloadRenderTexture(b)
		}
	}
	p.size = size
	p.scene = rl.LoadRenderTexture(size.x, size.y)
	rl.SetTextureFilter(p.scene.texture, .BILINEAR)
	rl.SetTextureWrap(p.scene.texture, .CLAMP)
	// The first step is one texel per virtual pixel, each one after it half
	// the last.
	view := view_size()
	w, h := i32(math.ceil(view.x)), i32(PIXEL_HEIGHT)
	for &b in p.bloom {
		b = rl.LoadRenderTexture(max(w, 4), max(h, 4))
		rl.SetTextureFilter(b.texture, .BILINEAR)
		rl.SetTextureWrap(b.texture, .CLAMP)
		w /= 2
		h /= 2
	}
	if !p.loaded {
		p.loaded = true
		p.highlights = rl.LoadShaderFromMemory(nil, HIGHLIGHTS_FS)
		p.bloom_ok = p.highlights.id != 0 && p.highlights.id != rl.rlGetShaderIdDefault()
		if p.bloom_ok {
			p.threshold = rl.GetShaderLocation(p.highlights, "threshold")
		}
		img := rl.GenImageGradientRadial(96, 96, 0.42, rl.WHITE, {168, 160, 196, 255})
		p.vignette = rl.LoadTextureFromImage(img)
		rl.UnloadImage(img)
		rl.SetTextureFilter(p.vignette, .BILINEAR)
		rl.SetTextureWrap(p.vignette, .CLAMP)
	}
}

// Everything drawn between this and `post_end` goes into the scene.
post_begin :: proc(g: ^Game) {
	post_fit(&g.post)
	rl.BeginTextureMode(g.post.scene)
}

// One whole picture into the target being drawn to, stretched to fill it.
@(private = "file")
blit :: proc(from: rl.RenderTexture2D, w, h: f32, tint := rl.WHITE) {
	// Render textures are stored upside down.
	src := rl.Rectangle{0, 0, f32(from.texture.width), -f32(from.texture.height)}
	rl.DrawTexturePro(from.texture, src, {0, 0, w, h}, {}, 0, tint)
}

post_end :: proc(g: ^Game) {
	p := &g.post
	sw, sh := f32(p.size.x), f32(p.size.y)

	// The corners, darkened.
	rl.BeginBlendMode(.MULTIPLIED)
	rl.DrawTexturePro(p.vignette, {0, 0, 96, 96}, {-sw * 0.12, -sh * 0.12, sw * 1.24, sh * 1.24}, {}, 0, rl.WHITE)
	rl.EndBlendMode()
	// Drawing see-through things has left holes in the picture's alpha:
	// fill them, or it would be blended as if it were see-through itself.
	rl.BeginBlendMode(.ADD_COLORS)
	rl.DrawRectangle(0, 0, p.size.x, p.size.y, {0, 0, 0, 255})
	rl.EndBlendMode()
	rl.EndTextureMode()

	if !p.bloom_ok {
		return
	}

	// The highlights, at one texel per virtual pixel.
	first := p.bloom[0]
	threshold := BLOOM_THRESHOLD[g.level.zone]
	rl.BeginTextureMode(first)
	rl.ClearBackground(rl.BLACK)
	rl.BeginShaderMode(p.highlights)
	rl.SetShaderValue(p.highlights, p.threshold, &threshold, .FLOAT)
	blit(p.scene, f32(first.texture.width), f32(first.texture.height))
	rl.EndShaderMode()
	rl.EndTextureMode()

	// Down the steps, each a blur of the one before...
	for i in 1 ..< BLOOM_STEPS {
		to := p.bloom[i]
		rl.BeginTextureMode(to)
		rl.ClearBackground(rl.BLACK)
		blit(p.bloom[i - 1], f32(to.texture.width), f32(to.texture.height))
		rl.EndTextureMode()
	}
	// ...and back up, mixing each half and half into the one above, so the
	// second ends up holding the glow at every width at once. The first is
	// left out: it is not blurred at all.
	for i := BLOOM_STEPS - 1; i >= 2; i -= 1 {
		to := p.bloom[i - 1]
		rl.BeginTextureMode(to)
		blit(p.bloom[i], f32(to.texture.width), f32(to.texture.height), {255, 255, 255, 128})
		rl.EndTextureMode()
	}
}

// The finished scene onto the window, and its glow over it.
post_present :: proc(g: ^Game) {
	p := &g.post
	sw, sh := f32(p.size.x), f32(p.size.y)
	blit(p.scene, sw, sh)
	if p.bloom_ok {
		gain: f32 = BLOOM_GAIN
		k := u8(255 * gain)
		rl.BeginBlendMode(.ADD_COLORS)
		blit(p.bloom[1], sw, sh, {k, k, k, 255})
		rl.EndBlendMode()
	}
}
