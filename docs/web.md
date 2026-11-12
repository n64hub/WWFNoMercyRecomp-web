# Building the web page

The desktop build is in BUILDING.md. This is the page: the same game built with Emscripten into one web page that
draws through WebGPU, with [N64Recomp-browser](https://github.com/n64hub/N64Recomp-browser)'s web support. The game's
code is recompiled at build time from your own dump of WWF No Mercy (USA, Rev 1, the ROM BUILDING.md names); the page
holds none of it but the recompiled code, and takes the dump from its launcher's Load ROM.

## Tools

On Linux (or WSL): [emsdk](https://emscripten.org/docs/getting_started/downloads.html) active (`emsdk install
latest`), clang, CMake 3.20+, Ninja, Python 3, and [naga](https://github.com/gfx-rs/wgpu/tree/trunk/naga) (`cargo
install naga-cli`). N64Recomp-browser's README (Using it in a recomp, What the build needs) has the rest: spirv-opt,
and [ccache](https://ccache.dev) on `PATH`, which N64Recomp-browser's `frontend/build_speed.cmake` puts in front of
every compile.

## Build

```bash
git clone --recurse-submodules https://github.com/n64hub/WWFNoMercyRecomp-web
cd WWFNoMercyRecomp-web
bash tools/build_web.sh <your USA Rev 1 dump>
```

`tools/build_web.sh` (its header says each step) patches the submodules, builds N64Recomp and RSPRecomp natively,
recompiles the game in the checkout as BUILDING.md's step 4 does, the whole post-regen pipeline included, and builds
the page in `build-web` (`web/page.cmake`): `NoMercyRecompiled.html`, `.js`, `.wasm` and `.data`.

The page builds its WebGPU pipelines from `web/rt64_shaders.txt` (its header says what was played), the boot's before
the game starts and a match's when one first draws. `bash web/record_shaders.sh build-web <dump>` records it again from
`web/shader_plan.json` in headless Chrome (about 11 minutes); build the page again after. `web/play_plan.json` plays
the page for N64Recomp-browser's `tools/play_page.mjs`, a match of 1P against the CPU, and `web/game_state.js` is what
both plans read the game by.

The submodules are this port's own forks of rt64, N64ModernRuntime and RecompFrontend (their `wcw` branches, shared with
its sister recomps), far from the upstream commits N64Recomp-browser's patches are made on, and they change many of
the same lines. For the files where the two meet (`web/patches/files.txt`, whose header says what each merge kept) the
web's change is `web/patches/<project>.patch`, merged by hand on top of the port's, and what N64Recomp-browser has
changed in them since is merged in by its `apply.cmake --since`. A change there that meets the port's own lines stops
the build: merge it into `web/patches` by hand then, as `files.txt` says. `bash tools/build_web.sh --patches` does only
that step, without a ROM; N64Recomp-browser's CI runs it on every change there and compiles the merged files.

The recompiled game comes from upstream's N64Recomp at the commit BUILDING.md names with N64Recomp-browser's N64Recomp
patch on it: the page needs the C that the web-patched N64Recomp writes (its tail calls, `RECOMP_TAIL_CALL`).
`lib/N64ModernRuntime/N64Recomp` only gives the runtime its headers and library, as on the desktop.

Serve `build-web` with `Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: require-corp`
(threads need SharedArrayBuffer), or with `coi_serviceworker.js` beside the page where headers can't be set, and open
it in a browser with WebGPU. The ROM, settings and saves are kept in the browser's storage.

## What the page does differently

- Framerate: Smooth interpolates to the display's rate (60, 120, 144), not a fixed 60, as every page does; the port's
  frame pairing spreads any rate over the game's frames. The menu shows it as Display (Smooth). Resolution is Auto,
  the canvas's size, as on the desktop.
- Render to RAM is off (`src/main/main.cpp`): the game's CPU never reads a frame the RDP drew, nor writes into one.
  Its two 480x240 framebuffers' addresses go only into display lists (an overlay draws the last frame as a texture,
  the RDP's read, which RT64 does on the GPU), the swap and the scheduler's compares, and the routine that
  zeroes them has no caller. On a page each copy waits 5-6 ms for the browser's readback, on every one of the tasks a
  frame is drawn in.
- Sound goes to N64Recomp-browser's `audio_output.h`, played on the browser's audio thread, resampled to its rate
  (`src/main/main.cpp`), not SDL's queue.
- Left out: ray tracing, the CRT filter and HDR, which need D3D12 or librashader; RetroAchievements
  (`src/ra/ra_client.cpp` is a stub off Windows); and the bundled mods in `assets/mods` (camera, cheats, quick match,
  model import and its starter packs): a page has no live recompiler to run a mod's code, so `web/page.cmake` leaves
  the folder out of the page and `install_bundled_mods` installs none. The launcher has no Mods or Exit on a page
  (`src/main/main.cpp`): there are none to show, and a program that ends leaves the page dead. MSAA: RT64 has none on
  WebGPU, which gives no sample positions.
- On wasm32 the runtime's entry prologue indices are 32 bits (`entry_prologue_rules.hpp`), and a save backup's time is
  converted without `clock_cast`, which Emscripten's libc++ lacks (`save_backups.cpp`). Both are in
  `web/patches/N64ModernRuntime.patch`, as is the Controller Pak's log of its bank reads and writes and identity
  switches, off on a page (`si.cpp`): the game probes the pak every few frames in a match, and a page sends each line
  of stderr to its page's thread.
