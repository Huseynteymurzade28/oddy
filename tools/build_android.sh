#!/usr/bin/env bash
# Builds build/oddy.apk: the game as a NativeActivity for arm64 phones.
#
#   tools/build_android.sh           build and sign the APK
#   tools/build_android.sh install   ...then install it on the connected device
#   tools/build_android.sh run       ...then install and start it
#
# Needs the Android SDK (ANDROID_HOME, default ~/Android/Sdk) with build-tools,
# a platform and the NDK, a JDK for apksigner, and the Android raylib from
# tools/build_raylib.sh. Signs with the debug keystore Android Studio makes.
#
# The APK's assets/ holds the repo's assets/ and levels/ folders as-is, so the
# game's "assets/..." and "levels/..." paths resolve through raylib's AAssetManager fopen wrapper.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
sdk="${ANDROID_HOME:-$HOME/Android/Sdk}"
ndk="${ANDROID_NDK:-$(ls -d "$sdk"/ndk/* | sort -V | tail -1)}"
tools="$(ls -d "$sdk"/build-tools/* | sort -V | tail -1)"
platform="$(ls -d "$sdk"/platforms/android-* | sort -V | tail -1)"
min_sdk=29
# Compiled against the newest platform, but targeting 35: from 36 on, Android
# stops sending Back to apps that have not moved to predictive back.
target_sdk=35
keystore="${ODDY_KEYSTORE:-$HOME/.android/debug.keystore}"

build="$root/build/android"
apk="$root/build/oddy.apk"
rm -rf "$build"
mkdir -p "$build/stage/assets" "$build/lib/arm64-v8a"

[[ -f "$root/libs/raylib/android-arm64/libraylib.a" ]] ||
	{ echo "run tools/build_raylib.sh android first" >&2; exit 1; }

echo "== compiling liboddy.so (arm64-v8a)"
ODIN_ANDROID_NDK="$ndk" ODIN_ANDROID_SDK="$sdk" \
	odin build "$root/src" -target:linux_arm64 -subtarget:android -minimum-os-version:$min_sdk \
	-build-mode:shared -o:speed -extra-linker-flags:"-Wl,--wrap=fopen" \
	-out:"$build/lib/arm64-v8a/liboddy.so"

echo "== packaging"
cp -r "$root/assets" "$build/stage/assets/assets"
cp -r "$root/levels" "$build/stage/assets/levels"
"$tools/aapt2" compile --dir "$root/android/res" -o "$build/res.zip"
"$tools/aapt2" link -o "$build/unaligned.apk" -I "$platform/android.jar" \
	--manifest "$root/android/AndroidManifest.xml" \
	--min-sdk-version $min_sdk --target-sdk-version "$target_sdk" \
	-A "$build/stage/assets" "$build/res.zip"

# Native libraries go in uncompressed, so zipalign can page-align them.
python3 -I - "$build/unaligned.apk" "$build" <<'EOF'
import sys, zipfile, os
apk, build = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(apk, "a") as z:
    for dirpath, _, files in os.walk(os.path.join(build, "lib")):
        for f in files:
            path = os.path.join(dirpath, f)
            z.write(path, os.path.relpath(path, build), compress_type=zipfile.ZIP_STORED)
EOF

"$tools/zipalign" -f -P 16 4 "$build/unaligned.apk" "$build/aligned.apk"
"$tools/apksigner" sign --ks "$keystore" --ks-pass pass:android --key-pass pass:android \
	--out "$apk" "$build/aligned.apk"
echo "== $apk ($(du -h "$apk" | cut -f1))"

adb="$sdk/platform-tools/adb"
case "${1:-}" in
install) "$adb" install -r "$apk" ;;
run)
	"$adb" install -r "$apk"
	"$adb" shell am start -n com.flear.oddy/android.app.NativeActivity
	;;
esac
