package game

/*
Short buzzes on a phone, so a dash, a landing on a creature or a death is felt
as well as seen. On the desktop these do nothing. The Android side is a few
lines of C in `android/native/haptics.c`, built and linked by
`tools/build_android.sh`.
*/

Haptic :: enum {
	Dash,
	Stomp,
	Death,
	Checkpoint,
	Clear,
}

@(private = "file")
HAPTICS := [Haptic][2]i32 { // milliseconds, strength 1..255
	.Dash       = {12, 70},
	.Stomp      = {22, 140},
	.Death      = {55, 220},
	.Checkpoint = {30, 110},
	.Clear      = {70, 160},
}

when IS_MOBILE {
	foreign import native_haptics "../build/android/haptics.o"

	@(default_calling_convention = "c")
	foreign native_haptics {
		oddy_vibrate :: proc(ms, amplitude: i32) ---
		oddy_haptics_shutdown :: proc() ---
	}

	haptic :: proc(h: Haptic) {
		v := HAPTICS[h]
		oddy_vibrate(v[0], v[1])
	}

	haptics_shutdown :: proc() {
		oddy_haptics_shutdown()
	}
} else {
	haptic :: proc(h: Haptic) {
		_ = HAPTICS[h]
	}

	haptics_shutdown :: proc() {}
}
