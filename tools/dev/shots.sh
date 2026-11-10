#!/usr/bin/env bash
# Builds the game in screenshot mode (src/devshots.odin), runs its script and
# collects the pictures in build/shots/. Pass extra odin flags after it, e.g.
#   tools/dev/shots.sh -define:TOUCH=true
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
mkdir -p build/shots
odin build src -out:build/lumi_shots -define:SHOTS=true "$@"
# raylib saves screenshots in the working directory, by file name only.
rm -f [0-9][0-9]*_*.png
mv lumi_save.json build/shots/save.bak 2>/dev/null || true
timeout 120 build/lumi_shots >/dev/null 2>&1 || true
rm -f lumi_save.json
mv build/shots/save.bak lumi_save.json 2>/dev/null || true
rm -f build/shots/*.png
mv [0-9][0-9]*_*.png build/shots/
ls build/shots
