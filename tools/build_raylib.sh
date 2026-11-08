#!/usr/bin/env bash
# Builds the static raylib libraries the game links against, from raylib's own
# source at the version the Odin bindings in libs/raylib describe (6.0).
#
#   tools/build_raylib.sh            desktop Linux + Android arm64
#   tools/build_raylib.sh linux      just one of them
#   tools/build_raylib.sh android
#
# Android needs the NDK: ANDROID_NDK, or the newest one under ~/Android/Sdk/ndk.
#
# The Android library is built with -Dmain=oddy_android_main: raylib's
# `android_main` calls a C `main`, and an Odin shared library cannot provide one
# (the loader would run it). src/main_android.odin exports that name instead.
set -euo pipefail

RAYLIB_TAG=6.0
ANDROID_API=29

root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/libs/raylib"
work="${TMPDIR:-/tmp}/oddy-raylib-$RAYLIB_TAG"
targets=("${@:-linux android}")
targets=(${targets[@]})

if [[ ! -d "$work/src" ]]; then
	git clone --quiet --depth 1 --branch "$RAYLIB_TAG" https://github.com/raysan5/raylib.git "$work"
fi

build_linux() {
	echo "== raylib $RAYLIB_TAG for desktop Linux"
	(cd "$work/src" && rm -f ./*.o && mkdir -p "$out/linux" &&
		make -j"$(nproc)" PLATFORM=PLATFORM_DESKTOP RAYLIB_RELEASE_PATH="$out/linux" >/dev/null)
}

build_android() {
	local ndk="${ANDROID_NDK:-}"
	if [[ -z "$ndk" ]]; then
		ndk="$(ls -d "$HOME"/Android/Sdk/ndk/* 2>/dev/null | sort -V | tail -1)"
	fi
	[[ -d "$ndk" ]] || { echo "no Android NDK: set ANDROID_NDK" >&2; exit 1; }

	echo "== raylib $RAYLIB_TAG for Android arm64 (NDK $(basename "$ndk"))"
	mkdir -p "$out/android-arm64"
	(cd "$work/src" && rm -f ./*.o &&
		make -j"$(nproc)" PLATFORM=PLATFORM_ANDROID ANDROID_NDK="$ndk" ANDROID_ARCH=arm64 \
			ANDROID_API_VERSION=$ANDROID_API RAYLIB_RELEASE_PATH="$out/android-arm64" \
			CUSTOM_CFLAGS="-Dmain=oddy_android_main -fPIC" >/dev/null)
}

for t in "${targets[@]}"; do
	case "$t" in
	linux) build_linux ;;
	android) build_android ;;
	*) echo "unknown target: $t" >&2; exit 1 ;;
	esac
done
ls -la "$out"/*/libraylib.a
