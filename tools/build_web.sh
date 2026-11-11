#!/usr/bin/env bash
# Builds the web page (build-web/NoMercyRecompiled.html, .js, .wasm, .data) from the USA Rev 1 ROM, on Linux with
# emsdk active (N64Recomp-browser's README, Using it in a recomp, says what else: naga, spirv-opt, ccache), clang, Ninja
# and Python 3:
#
#   bash tools/build_web.sh <USA Rev 1 ROM> [--prepare]
#   bash tools/build_web.sh --patches          step 1 alone: no ROM, and only git and CMake
#
# 1. The submodules and N64Recomp-browser's web support on them (lib/N64Recomp-browser/patches/apply.cmake, project by
#    project), from clean whenever lib/N64Recomp-browser, a submodule's commit or web/patches moved since the last time
#    (build-web-prep/web-patched records it): apply.cmake can't take a checkout from one version of its patches to
#    another. The submodules are this port's own forks of rt64, plume, N64ModernRuntime, N64Recomp and RecompFrontend
#    (their wcw branches, shared with its sister recomps), far from the upstream commits the web's patches are made on.
#    For the files where the two change the same lines (web/patches/files.txt) the web's change is
#    web/patches/<project>.patch instead, merged by hand on top of the port's from the N64Recomp-browser commit
#    files.txt names, with what the web has changed in them since merged in by apply.cmake --since (only a change that
#    meets the port's own lines stops the build, for another merge by hand). A file marked own there keeps the port's
#    code alone: the web's change to it is left out, then and later.
# 2. N64Recomp and RSPRecomp, built natively: upstream's N64Recomp at the commit BUILDING.md names, with the web's
#    N64Recomp patch on it, in build-web-prep/N64Recomp. The page needs the code the web-patched N64Recomp writes;
#    lib/N64ModernRuntime/N64Recomp, the port's own, only gives the runtime its headers and library, as on the desktop.
# 3. The recompiled game and the audio microcode, as BUILDING.md's step 4 makes them, in the checkout: N64Recomp, then
#    the whole post-regen pipeline (every step is required: one left out makes a build that boots and corrupts itself
#    later), then RSPRecomp. Not tools/romhack/list_repaired_functions.py: its list warns about ROM-patch mods, and a
#    page has none (no live recompiler). Made again only when what it reads changed (build-web-prep/recompiled-stamp).
# 4. The page, with emcmake, in build-web (web/page.cmake). --prepare stops before it.
# --patches stops after step 1. N64Recomp-browser's CI runs it with its own checkout as lib/N64Recomp-browser and the
# submodules checked out, so a web change there that meets this port's own lines in a file left out is red where it is
# made: merge it into the patch by hand then.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
[[ $# -ge 1 ]] || { echo "usage: $0 <USA Rev 1 ROM> [--prepare] | --patches" >&2; exit 2; }
patches_only=0
[[ "$1" == --patches ]] && patches_only=1
[[ $patches_only == 1 ]] || rom="$(realpath "$1")"
prepare_only=0
[[ "${2:-}" == --prepare ]] && prepare_only=1
cd "$root"
jobs="$(nproc)"
browser=lib/N64Recomp-browser
prep=build-web-prep
# BUILDING.md's N64Recomp, which the post-regen pipeline is written against.
n64recomp_url=https://github.com/N64Recomp/N64Recomp
n64recomp_commit=ffb39cdad1da5de07eaaa48bd1db4a89a7986771
mkdir -p $prep

step() { printf '\n== %s\n' "$*"; }

# --- 1. Submodules and patches ---
step "Submodules"
[[ -f lib/rt64/CMakeLists.txt && -f lib/rt64/src/contrib/plume/CMakeLists.txt &&
   -f lib/N64ModernRuntime/N64Recomp/CMakeLists.txt && -f lib/RecompFrontend/CMakeLists.txt &&
   -f $browser/patches/apply.cmake ]] ||
    git submodule update --init --recursive lib/rt64 lib/N64ModernRuntime lib/RecompFrontend $browser

step "Patches"
# <name> <checkout> [files left to web/patches/<name>.patch, merged from the commit files.txt names, or left out]
shared() { awk -v p="$1" '!/^#/ && $1 == p { printf "%s ", $2 }' web/patches/files.txt; }
merged() { awk -v p="$1" '!/^#/ && $1 == p && $3 != "own" { printf "%s ", $2 }' web/patches/files.txt; }
merged_from="$(sed -n 's/^# merged from N64Recomp-browser //p' web/patches/files.txt)"
web_patches="rt64 lib/rt64 $(shared rt64)
plume lib/rt64/src/contrib/plume $(shared plume)
hlslpp lib/rt64/src/contrib/hlslpp $(shared hlslpp)
N64ModernRuntime lib/N64ModernRuntime $(shared N64ModernRuntime)
N64Recomp lib/N64ModernRuntime/N64Recomp $(shared N64Recomp)
RecompFrontend lib/RecompFrontend $(shared RecompFrontend)"
stamp="$(git -C $browser rev-parse HEAD) $(git submodule status lib/rt64 lib/N64ModernRuntime lib/RecompFrontend |
    cut -c2-41 | tr '\n' ' ')$( (cat web/patches/*.patch web/patches/files.txt; echo "$web_patches") | sha1sum | cut -c1-40)"
# A checkout reset since (rt64 clean) is patched again whatever the stamp says.
if [[ "$(cat $prep/web-patched 2> /dev/null)" != "$stamp" ]] || git -C lib/rt64 diff --quiet; then
    for s in lib/rt64 lib/N64ModernRuntime lib/RecompFrontend; do
        git -C $s submodule foreach --recursive -q 'git reset -q --hard && git clean -fdq'
        git -C $s reset -q --hard && git -C $s clean -fdq
        rm -f "$(git -C $s rev-parse --path-format=absolute --git-dir)"/n64recomp-browser-*
    done
    while read -r name checkout skip; do
        cmake -P $browser/patches/apply.cmake "$name" "$checkout" $skip
        [[ ! -f web/patches/$name.patch ]] || git -C "$checkout" apply --whitespace=nowarn "$root/web/patches/$name.patch"
        since="$(merged "$name")"
        [[ -z "$since" ]] || cmake -P $browser/patches/apply.cmake "$name" "$checkout" --since "$merged_from" $since
    done <<< "$web_patches"
    echo "$stamp" > $prep/web-patched
fi

[[ $patches_only == 1 ]] && exit 0

# --- 2. N64Recomp and RSPRecomp ---
step "N64Recomp"
recomp_src=$prep/N64Recomp
if [[ "$(git -C $recomp_src rev-parse HEAD 2> /dev/null)" != "$n64recomp_commit" ]]; then
    rm -rf $recomp_src $prep/tools
    git clone -q $n64recomp_url $recomp_src
    git -C $recomp_src checkout -q $n64recomp_commit
    git -C $recomp_src submodule update -q --init --recursive
fi
# Patched again when the web's patch moved (apply.cmake does nothing to a checkout it patched already).
cmake -P $browser/patches/apply.cmake N64Recomp $recomp_src
tools=$prep/tools
[[ -f $tools/build.ninja ]] || cmake -S $recomp_src -B $tools -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ > /dev/null
ninja -C $tools N64RecompCLI RSPRecomp > /dev/null

# --- 3. The recompiled game and the audio microcode ---
step "Recompiled code"
python3 - "$rom" nomercy.z64 <<'PY'
import hashlib, pathlib, sys
source, target = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
data = bytearray(source.read_bytes())
magic = bytes(data[:4]).hex()
if magic == "37804012":
    data[0::2], data[1::2] = data[1::2], data[0::2]
elif magic == "40123780":
    for i in range(0, len(data) - 3, 4):
        data[i:i + 4] = data[i:i + 4][::-1]
sha1 = hashlib.sha1(data).hexdigest()
if sha1 != "91cee3d096f4a76644d8b35b9aead6448909abd1":
    raise SystemExit(f"{source}: not WWF No Mercy (USA, Rev 1) (SHA-1 {sha1})")
if not target.exists() or target.read_bytes() != data:
    target.write_bytes(data)
PY
inputs="$( (cat nomercy.z64 nomercy.toml syms/*.t* syms/*.txt rsp/nomercy_audio.toml tools/fix_*.py \
    tools/readd_hand_edits.py tools/audit_coresidency.py $tools/N64Recomp $tools/RSPRecomp) | sha1sum | cut -c1-40)"
if [[ "$(cat $prep/recompiled-stamp 2> /dev/null)" != "$inputs" || ! -f RecompiledFuncs/funcs.h ||
      ! -f rsp/nomercy_audio.cpp ]]; then
    log=$prep/n64recomp.log
    rm -f RecompiledFuncs/*.c RecompiledFuncs/*.h RecompiledFuncs/repaired_functions.txt rsp/nomercy_audio.cpp
    run() { echo "+ $*" >> $log; "$@" >> $log 2>&1 || { tail -30 $log; exit 1; }; }
    : > $log
    run "$root/$tools/N64Recomp" nomercy.toml
    run python3 tools/fix_stumps.py
    run python3 tools/fix_switches.py
    run python3 tools/fix_jraddend.py
    run python3 tools/fix_backbranches.py
    ! grep -q MISSING $log || { grep MISSING $log | head; echo "fix_backbranches.py: functions missing" >&2; exit 1; }
    run python3 tools/fix_selfentry.py
    run python3 tools/readd_hand_edits.py
    run python3 tools/audit_coresidency.py
    run "$root/$tools/RSPRecomp" rsp/nomercy_audio.toml
    echo "$inputs" > $prep/recompiled-stamp
fi
[[ $prepare_only == 1 ]] && exit 0

# --- 4. The page ---
step "Page"
embuilder build sdl2-mt freetype-legacysjlj > /dev/null 2>&1
# Configured again when web/rt64_shaders.txt came after the last configure: web/page.cmake sets the list only if the file
# is there, and ninja has nothing to reconfigure for in a commit that only adds it.
[[ -f build-web/build.ninja ]] && { [[ ! -f web/rt64_shaders.txt ]] ||
    grep -q "^RT64_PREBUILT_SHADER_LIST:FILEPATH=.*/web/rt64_shaders.txt" build-web/CMakeCache.txt; } || emcmake cmake -S . -B build-web -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DRT64_NAGA_EXECUTABLE="$(command -v naga)" -DPython3_EXECUTABLE="$(command -v python3)" > $prep/configure.log 2>&1 ||
    { tail -30 $prep/configure.log; rm -f build-web/build.ninja; exit 1; }
cmake --build build-web --target NoMercyRecompiled -j"$jobs"
ls -l build-web/NoMercyRecompiled.{html,js,wasm,data}
