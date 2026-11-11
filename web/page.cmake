# The game as a page for a browser (emcmake cmake), NoMercyRecompiled.html, through lib/N64Recomp-browser: RT64 on
# WebGPU in the page's canvas, sound on the browser's audio thread, the ROM, the saves and the settings in the
# browser's storage. CMakeLists.txt includes this in place of the rest of itself when it configures with Emscripten;
# tools/build_web.sh makes what it needs first (the web patches on the submodules, the recompiled game from the
# web-patched N64Recomp and the post-regen pipeline, the audio microcode).
#
# What differs from the desktop build:
# - rt64, N64ModernRuntime and RecompFrontend are the submodules with N64Recomp-browser's web support patched in
#   (tools/build_web.sh, and web/patches where this port's own changes meet it). RT64 draws through WebGPU whatever
#   the settings say; ray tracing, the CRT filter and HDR are D3D12's or librashader's and are left out.
# - No file dialog: RecompFrontend's launcher asks the page for the ROM and keeps it under HOME, which the page keeps
#   in the browser's IndexedDB.
# - assets/ and recompcontrollerdb.txt are the page's .data, at the root of its file system, where the desktop build
#   copies them beside the executable. Not assets/mods: a page has no live recompiler to run the bundled mods' code
#   (N64Recomp-browser's README), and without the folder src/main/main.cpp installs none.
# - No RetroAchievements: src/ra/ra_client.cpp is a stub off Windows, so rcheevos isn't built.
# - No repaired-functions list: it warns about ROM-patch mods, and a page has none.

if (NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

# Threads are pthreads (SharedArrayBuffer), and the runtime ends a game thread by throwing. -msimd128 is wasm SIMD,
# which every browser with WebGPU has; -mtail-call makes the recompiled code's tail calls return_calls. With -msimd128
# xxHash would take its NEON path through Emscripten's arm_neon.h, which doesn't compile in C++ there.
add_compile_options(-pthread -fwasm-exceptions -msimd128 -mtail-call "-DXXH_HAS_INCLUDE(x)=0")
add_link_options(-pthread -fwasm-exceptions -mtail-call)
add_compile_definitions(HLSL_CPU)
# ccache when it is on PATH, for shorter builds; before rt64 and the runtime are added.
include(${CMAKE_SOURCE_DIR}/lib/N64Recomp-browser/frontend/build_speed.cmake)
# The shaders the page specializes at build time and builds before the game draws with them (web/rt64_shaders.txt
# says how it was recorded); before rt64 is added.
if (EXISTS "${CMAKE_SOURCE_DIR}/web/rt64_shaders.txt")
    set(RT64_PREBUILT_SHADER_LIST "${CMAKE_SOURCE_DIR}/web/rt64_shaders.txt" CACHE FILEPATH "" FORCE)
endif()

set(NMR ${CMAKE_SOURCE_DIR}/lib/N64ModernRuntime)
set(RT64DIR ${CMAKE_SOURCE_DIR}/lib/rt64)

set(RT64_STATIC TRUE)
set(RT64_SDL_WINDOW_VULKAN TRUE)
add_subdirectory(${RT64DIR} ${CMAKE_BINARY_DIR}/rt64)
target_include_directories(rt64 PRIVATE ${CMAKE_BINARY_DIR}/rt64/src)

set(BUILD_SHARED_LIBS OFF)
add_subdirectory(${NMR})

# The page: N64Recomp-browser's frontend/ (the page shell, the ROM's and saves' storage, the sound, the service worker).
add_subdirectory(${CMAKE_SOURCE_DIR}/lib/N64Recomp-browser/frontend ${CMAKE_BINARY_DIR}/web_frontend)
# fmt 11.1 (N64Recomp's) leans on <cstdlib> arriving through other headers, which Emscripten's libc++ doesn't do.
if (TARGET fmt)
    target_compile_options(fmt PRIVATE -include cstdlib)
endif()

# The recompiled game. WebAssembly turns a call to an undeclared function into a trap, so it may call none.
file(GLOB FUNC_C_SOURCES CONFIGURE_DEPENDS ${CMAKE_SOURCE_DIR}/RecompiledFuncs/*.c)
if (NOT FUNC_C_SOURCES)
    message(FATAL_ERROR "RecompiledFuncs/ is empty: tools/build_web.sh recompiles the game first")
endif()
add_library(RecompiledFuncs STATIC ${FUNC_C_SOURCES})
target_compile_options(RecompiledFuncs PRIVATE -Wno-everything -fno-strict-aliasing -fwrapv
    -Werror=implicit-function-declaration)
target_include_directories(RecompiledFuncs PRIVATE
    ${CMAKE_SOURCE_DIR}/include
    ${NMR}/ultramodern/include
    ${NMR}/librecomp/include
    ${NMR}/N64Recomp/include)

# RecompFrontend's UI shaders: DXC runs on the machine that builds, which for a page isn't the target, and RT64's
# build_*_shader functions read these from the caller's scope (CMakeLists.txt says why).
set(DXC_COMMON_OPTS "-I${RT64DIR}/src")
set(DXC_DXIL_OPTS "-Wno-ignored-attributes")
set(DXC_SPV_OPTS "-spirv" "-fspv-target-env=vulkan1.0" "-fvk-use-dx-layout")
set(DXC_PS_OPTS "${DXC_COMMON_OPTS}" "-E" "PSMain" "-T ps_6_0" "-D DYNAMIC_RENDER_PARAMS")
set(DXC_VS_OPTS "${DXC_COMMON_OPTS}" "-E" "VSMain" "-T vs_6_0" "-D DYNAMIC_RENDER_PARAMS" "-fvk-invert-y")
set(DXC_CS_OPTS "${DXC_COMMON_OPTS}" "-E" "CSMain" "-T cs_6_0")
set(DXC_GS_OPTS "${DXC_COMMON_OPTS}" "-E" "GSMain" "-T gs_6_0")
if (CMAKE_HOST_WIN32)
    set(DXC "${RT64DIR}/src/contrib/dxc/bin/x64/dxc.exe")
elseif (CMAKE_HOST_APPLE)
    set(DXC "DYLD_LIBRARY_PATH=${RT64DIR}/src/contrib/dxc/lib/arm64" "${RT64DIR}/src/contrib/dxc/bin/arm64/dxc-macos")
elseif (CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "x86_64|amd64|AMD64")
    set(DXC "LD_LIBRARY_PATH=${RT64DIR}/src/contrib/dxc/lib/x64" "${RT64DIR}/src/contrib/dxc/bin/x64/dxc-linux")
else()
    set(DXC "LD_LIBRARY_PATH=${RT64DIR}/src/contrib/dxc/lib/arm64" "${RT64DIR}/src/contrib/dxc/bin/arm64/dxc-linux")
endif()

set(RECOMP_FRONTEND_N64MODERNRUNTIME_PATH ${NMR})
set(RECOMP_FRONTEND_RT64_PATH ${RT64DIR})
add_subdirectory(${CMAKE_SOURCE_DIR}/lib/RecompFrontend)

add_executable(NoMercyRecompiled)

# The launcher's thumbnail and logo, as on the desktop.
foreach (IMAGE icon:app logo:logo)
    string(REPLACE ":" ";" IMAGE ${IMAGE})
    list(GET IMAGE 0 NAME)
    list(GET IMAGE 1 FILE)
    add_custom_command(OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/${NAME}_bytes.c ${CMAKE_CURRENT_BINARY_DIR}/${NAME}_bytes.h
        COMMAND file_to_c ${CMAKE_SOURCE_DIR}/icons/${FILE}.png ${NAME}_bytes ${CMAKE_CURRENT_BINARY_DIR}/${NAME}_bytes.c
            ${CMAKE_CURRENT_BINARY_DIR}/${NAME}_bytes.h
        DEPENDS ${CMAKE_SOURCE_DIR}/icons/${FILE}.png file_to_c)
    target_sources(NoMercyRecompiled PRIVATE ${CMAKE_CURRENT_BINARY_DIR}/${NAME}_bytes.c)
endforeach()

# CMakeLists.txt's SOURCES, but rcheevos, and with an empty repaired-functions list.
set(REPAIRED_CPP ${CMAKE_CURRENT_BINARY_DIR}/repaired_functions.cpp)
file(CONFIGURE OUTPUT ${REPAIRED_CPP} CONTENT
    "// Generated by web/page.cmake: a page has no ROM-patch mods to check.\nvoid wcw_register_repaired_functions() {}\n")
target_sources(NoMercyRecompiled PRIVATE
    ${CMAKE_SOURCE_DIR}/src/main/main.cpp
    ${CMAKE_SOURCE_DIR}/src/main/register_overlays.cpp
    ${REPAIRED_CPP}
    ${CMAKE_SOURCE_DIR}/src/game/recomp_api.cpp
    ${CMAKE_SOURCE_DIR}/src/game/raytracing.cpp
    ${CMAKE_SOURCE_DIR}/src/game/entry_prologues.cpp
    ${CMAKE_SOURCE_DIR}/src/ra/ra_client.cpp
    ${CMAKE_SOURCE_DIR}/rsp/nomercy_audio.cpp)
set_source_files_properties(${CMAKE_SOURCE_DIR}/rsp/nomercy_audio.cpp PROPERTIES COMPILE_OPTIONS "-w")
target_include_directories(NoMercyRecompiled PRIVATE
    ${CMAKE_SOURCE_DIR}/include
    ${NMR}/N64Recomp/include
    ${RT64DIR}/src
    ${CMAKE_SOURCE_DIR}/lib/RecompFrontend/recompinput/include
    ${CMAKE_SOURCE_DIR}/lib/RecompFrontend/recompui/include
    ${CMAKE_SOURCE_DIR}/src/ra/rcheevos/include
    ${EMSCRIPTEN_SYSROOT}/include/SDL2
    ${CMAKE_CURRENT_BINARY_DIR})
target_compile_options(NoMercyRecompiled PRIVATE -fno-strict-aliasing -fms-extensions -sUSE_SDL=2)
target_link_libraries(NoMercyRecompiled PRIVATE RecompiledFuncs recompui recompinput librecomp ultramodern rt64)

# The page (lib/N64Recomp-browser/frontend), with the shipped files in its .data. No ROM: the player loads theirs on
# the page, and it stays in the browser.
n64recomp_browser_frontend_page(NoMercyRecompiled)
file(GLOB ASSETS RELATIVE ${CMAKE_SOURCE_DIR}/assets ${CMAKE_SOURCE_DIR}/assets/*)
list(REMOVE_ITEM ASSETS mods)
foreach (ASSET IN LISTS ASSETS)
    target_link_options(NoMercyRecompiled PRIVATE "SHELL:--preload-file ${CMAKE_SOURCE_DIR}/assets/${ASSET}@/assets/${ASSET}")
endforeach()
target_link_options(NoMercyRecompiled PRIVATE
    "SHELL:--preload-file ${CMAKE_SOURCE_DIR}/recompcontrollerdb.txt@/recompcontrollerdb.txt")
