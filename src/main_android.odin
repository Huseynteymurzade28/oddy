package game

import "base:runtime"
import "core:c"

// Only the Android build uses these; this keeps the others from complaining.
_ :: runtime
_ :: c

/*
The Android entry point. raylib owns `android_main` (the NativeActivity glue
calls it on its own thread once the activity exists); it was built with
`-Dmain=oddy_android_main`, so where it would call a C `main` it lands here.

Odin's runtime has already been started by the library's `-init` hook by the
time this runs, so all this has to do is give the thread a context.
*/
when IS_MOBILE {
	@(export, link_name = "oddy_android_main")
	oddy_android_main :: proc "c" (argc: c.int, argv: [^]cstring) -> c.int {
		context = runtime.default_context()
		run()
		return 0
	}
}
