#!/usr/bin/env bash
# Records web/rt64_shaders.txt, the shaders the page builds before the game and as each arena first draws, by code
# rather than by playing: N64Recomp-browser's tools/record_shaders.mjs serves the page built in <build dir>, drives it
# in headless Chrome through web/shader_plan.json, a page load a section (the boot and the menus, then a match in each
# arena), and writes the list. Needs node 22 or later and Chrome, and takes about 15 minutes. Then build the page
# again, so that it prebuilds the new list.
#
#   bash web/record_shaders.sh <build dir> <ROM> [--profile <dir>] [--port <n>] [--only <section>,...]
set -euo pipefail
[ $# -ge 2 ] || { sed -n '8p' "$0"; exit 1; }
cd "$(dirname "$0")/.."
build="$1" rom="$2"
shift 2
exec node lib/N64Recomp-browser/tools/record_shaders.mjs web/shader_plan.json "$build" "$rom" web/rt64_shaders.txt "$@"
