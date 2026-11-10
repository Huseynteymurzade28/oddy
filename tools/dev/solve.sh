#!/usr/bin/env bash
# Builds the levels from levels/rooms/, then the game in solver mode
# (src/devsolve.odin), and runs it: every room of every level that has rooms
# is played through by brute force, and any it cannot get through is named.
# Name levels after it to check only those, e.g.
#   tools/dev/solve.sh W1_2
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
tools/levels/build.py >/dev/null
mkdir -p build
odin build src -out:build/lumi_solve -define:SOLVE=true -o:speed
mv lumi_save.json build/save.solve.bak 2>/dev/null || true
build/lumi_solve "$@" 2>/dev/null || true
rm -f lumi_save.json
mv build/save.solve.bak lumi_save.json 2>/dev/null || true
