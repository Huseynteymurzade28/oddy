#!/usr/bin/env bash
# Builds the game in soak mode (src/devsoak.odin) and runs it: every level is
# played by a button-mashing hero for hours of game time, looking for ways it
# can get stuck (a boss out of its arena, an exit that never opens, a death
# with no respawn). Name levels after it to check only those, e.g.
#   tools/dev/soak.sh W2_5
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
mkdir -p build
odin build src -out:build/lumi_soak -define:SOAK=true -o:speed
mv lumi_save.json build/save.soak.bak 2>/dev/null || true
status=0
build/lumi_soak "$@" 2>/dev/null || status=$?
rm -f lumi_save.json
mv build/save.soak.bak lumi_save.json 2>/dev/null || true
exit $status
