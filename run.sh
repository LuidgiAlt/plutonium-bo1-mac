#!/bin/bash
# Run Plutonium Black Ops 1 (T5) with the runner and prefix made by setup.sh.
# BO1 is Direct3D 9: the patched DXVK renders it on MoltenVK 1.4.2 when
# setup.sh installed them (DXVK_BUILD, MOLTENVK_ARCHIVE), wined3d otherwise.
# See README.md.
#   ./run.sh                         play
#   ./run.sh install plutonium.exe   run Plutonium's installer in the prefix
#   ./run.sh kill                    stop everything in the prefix
# Options (environment variables, all optional):
#   PLUTONIUM_DIR=...  Plutonium folder (default: %LOCALAPPDATA%\Plutonium in the prefix)
#   BO1_DIR=...        BO1's Steam folder, for the game's XAudio2 (default: Steam's)
#   D3D9=dxvk          the patched DXVK on MoltenVK 1.4.2 (default when installed)
#   D3D9=vulkan        wined3d's Vulkan renderer (default without DXVK)
#   D3D9=gl            wined3d's OpenGL renderer
#   DXVK_ASYNC=0       DXVK builds new pipelines on the render thread
#   STALL=1            DXVK logs every call over 5 ms that can block a frame
#   HUD=1              Metal performance HUD
#   FULLSCREEN=1       set the game's fullscreen mode
#   WINDOWED=1         set the game's windowed mode
#   TWEAKS=0           keep blur, distortion and the frame cap as configured
#   XAUDIO=builtin     Wine's XAudio2 instead of the game's (gunfire is silent)
#   CSMT=0             no wined3d command thread
#   LAZY_EXEC=0        turn the lazy-exec fix (0004) off
#   PIPELINE_CACHE=0   run without wined3d's Vulkan pipeline cache file (0003)
#   WINE_LOG=1         log Direct3D, shader and audio errors to wine.log
#                      (2: also Direct3D warnings, 3: every XAudio2 call)
#   STATS=1            log breakpoint-emulation step counts
#   SYNCSTATS=1        log msync waits (needs the diagnostic ntdll, see README)
#   DUMP=1             save every shader MoltenVK converts to shader-dump/
set -euo pipefail
here=$(cd -- "$(dirname -- "$0")" && pwd)
runner="$here/runner/CrossOver"
[ -d "$runner" ] && [ -d "$here/prefix" ] || { echo "run ./setup.sh first" >&2; exit 1; }

export CX_ROOT="$runner" WINEPREFIX="$here/prefix" WINESERVER="$runner/bin/wineserver"
export CX_HOME="$HOME/Library/Application Support/CrossOver"
export WINEDLLPATH="$runner/lib/wine/x86_64-windows:$runner/lib/wine/x86_64-unix"
export PATH="$runner/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export WINEMSYNC=1 WINEDEBUG=-all
if [ "${HUD:-0}" = 1 ]; then export MTL_HUD_ENABLED=1; else unset MTL_HUD_ENABLED; fi
wine="$runner/lib/wine/x86_64-unix/wine"
lib="$runner/lib"
dxvk_dll="$lib/wine/i386-windows/d3d9.dll.dxvk"
mvk142="$runner/lib64/libMoltenVK.dylib.142"
if [ -z "${D3D9:-}" ]; then
  if [ -f "$dxvk_dll" ] && [ -f "$mvk142" ]; then D3D9=dxvk
  else D3D9=vulkan; echo "DXVK or MoltenVK 1.4.2 not installed (setup.sh): using wined3d on Vulkan" >&2; fi
fi
case "$D3D9" in
dxvk) [ -f "$dxvk_dll" ] && [ -f "$mvk142" ] || { echo "D3D9=dxvk needs setup.sh with DXVK_BUILD and MOLTENVK_ARCHIVE" >&2; exit 1; } ;;
vulkan|gl) ;;
*) echo "D3D9 must be dxvk, vulkan or gl" >&2; exit 1 ;;
esac
appdata_plutonium="$WINEPREFIX/drive_c/users/crossover/AppData/Local/Plutonium"
plutonium=${PLUTONIUM_DIR:-$appdata_plutonium}
game=${BO1_DIR:-$HOME/Library/Application Support/Steam/steamapps/common/Call of Duty Black Ops}

case "${1:-}" in
kill) "$WINESERVER" -k; exit 0 ;;
install) exec "$wine" "${2:?path to plutonium.exe}" ;;
esac

"$WINESERVER" -k 2>/dev/null || true
"$WINESERVER" -w 2>/dev/null || true

# Install a file only if it differs, by rename so nothing maps a half-written file.
put() { cmp -s "$1" "$2" || { cp "$1" "$2.swap" && mv -f "$2.swap" "$2"; }; }
reg() { "$wine" reg "$@" > /dev/null 2>&1 || true; }
overrides='HKCU\Software\Wine\AppDefaults\plutonium-bootstrapper-win32.exe\DllOverrides'

# Plutonium sets x86 hardware breakpoints, which Rosetta cannot deliver; the
# patched ntdll emulates them (0001, 0002). Lazy exec (0004) removes the stalls
# caused by the bootstrapper turning off DEP. The launcher starts the game with
# a fresh Windows environment built from HKCU\Environment, so the variables are
# set there as well as here.
vars=(WINE_ROSETTA_EXEC_BREAKPOINTS=1 WINE_ROSETTA_WOW64_BREAKPOINTS=1 WINE_ROSETTA_CALL_WORKAROUND=1
      "WINE_ROSETTA_LAZY_EXEC=${LAZY_EXEC:-1}")
[ -n "${STATS:-}" ] && vars+=("WINE_ROSETTA_STATS=$STATS") && WINE_LOG=${WINE_LOG:-1}
[ "${SYNCSTATS:-0}" = 1 ] && vars+=(WINE_MSYNC_STATS=1) && WINE_LOG=${WINE_LOG:-1}
[ "${PIPELINE_CACHE:-1}" = 0 ] && vars+=(WINED3D_VK_PIPELINE_CACHE=0)
for v in WINE_ROSETTA_STATS WINE_MSYNC_STATS WINED3D_VK_PIPELINE_CACHE; do reg delete 'HKCU\Environment' /v $v /f; done
for v in "${vars[@]}"; do
  export "$v"
  reg add 'HKCU\Environment' /v "${v%%=*}" /d "${v#*=}" /f
done

# DXVK: its d3d9.dll is a Wine builtin, so it replaces the runner's d3d9.dll
# (a copy in syswow64 would be ignored). It needs MoltenVK 1.4.2; with that
# MoltenVK the Plutonium launcher's Direct3D 11 window fails on wined3d's
# Vulkan renderer, so the launcher alone uses OpenGL. DXVK_ASYNC=1 builds new
# pipelines in the background instead of freezing on them.
launcher_d3d='HKCU\Software\Wine\AppDefaults\plutonium-launcher-win32.exe\Direct3D'
for v in DXVK_ASYNC DXVK_LOG_LEVEL DXVK_LOG_PATH DXVK_STALL_LOG; do reg delete 'HKCU\Environment' /v $v /f; done
if [ "$D3D9" = dxvk ]; then
  put "$dxvk_dll" "$lib/wine/i386-windows/d3d9.dll"
  put "$mvk142" "$runner/lib64/libMoltenVK.dylib"
  reg add "$launcher_d3d" /v renderer /d gl /f
  mkdir -p "$here/dxvk-log"
  for v in "DXVK_ASYNC=${DXVK_ASYNC:-1}" DXVK_LOG_LEVEL=info "DXVK_LOG_PATH=Z:${here//\//\\}\\dxvk-log" "DXVK_STALL_LOG=${STALL:-0}"; do
    export "$v"; reg add 'HKCU\Environment' /v "${v%%=*}" /d "${v#*=}" /f
  done
else
  put "$lib/wine/i386-windows/d3d9.dll.orig" "$lib/wine/i386-windows/d3d9.dll"
  [ -f "$runner/lib64/libMoltenVK.dylib.orig" ] && put "$runner/lib64/libMoltenVK.dylib.orig" "$runner/lib64/libMoltenVK.dylib"
  reg delete "$launcher_d3d" /v renderer /f
fi
# Direct3D 9 renderer: OpenGL (Wine's default) or Vulkan through MoltenVK.
if [ "$D3D9" = vulkan ]; then reg add 'HKCU\Software\Wine\Direct3D' /v renderer /d vulkan /f
else reg delete 'HKCU\Software\Wine\Direct3D' /v renderer /f; fi
# CSMT=0: wined3d makes its graphics calls on the game's render thread.
if [ "${CSMT:-1}" = 0 ]; then reg add 'HKCU\Software\Wine\Direct3D' /v csmt /t REG_DWORD /d 0 /f
else reg delete 'HKCU\Software\Wine\Direct3D' /v csmt /f; fi

# Apple's Metal compiler can spend minutes on one shader, and the game waits
# for that pipeline (looks frozen). Give up after 10 s instead: the pipeline
# fails and only that effect is missing. MoltenVK reads nanoseconds.
export MVK_CONFIG_METAL_COMPILE_TIMEOUT=${MVK_CONFIG_METAL_COMPILE_TIMEOUT:-10000000000}
# DUMP=1: MoltenVK writes every shader it converts to shader-dump/, newest
# last; when the game hangs on a shader compile, the newest file is the one.
if [ "${DUMP:-0}" = 1 ]; then mkdir -p "$here/shader-dump"; export MVK_CONFIG_SHADER_DUMP_DIR="$here/shader-dump"; fi

# Audio: BO1's gunfire and many effects are xWMA. Wine decodes xWMA through
# GStreamer, and CrossOver's GStreamer has no WMA decoder, so those sounds
# come out silent. Microsoft's XAudio2 2.7 decodes xWMA itself; it ships in
# the game's own DirectX redist, so it is taken from there.
xaudio_cab="$game/Redist/DirectX/Jun2010_XAudio_x86.cab"
native_xaudio="$WINEPREFIX/xaudio2_7.native.dll"
syswow64="$WINEPREFIX/drive_c/windows/syswow64"
if [ "${XAUDIO:-native}" = native ] && [ ! -f "$native_xaudio" ] && [ -f "$xaudio_cab" ]; then
  tmp=$(mktemp -d)
  bsdtar -xf "$xaudio_cab" -C "$tmp" XAudio2_7.dll && mv "$tmp/XAudio2_7.dll" "$native_xaudio"
  rm -rf "$tmp"
fi
if [ "${XAUDIO:-native}" = native ] && [ -f "$native_xaudio" ]; then
  put "$native_xaudio" "$syswow64/xaudio2_7.dll"
  reg add "$overrides" /v xaudio2_7 /d native /f
else
  [ "${XAUDIO:-native}" = native ] && echo "no $xaudio_cab (set BO1_DIR): using Wine's XAudio2, xWMA sounds will be silent" >&2
  put "$lib/wine/i386-windows/xaudio2_7.dll.orig" "$syswow64/xaudio2_7.dll"
  reg delete "$overrides" /v xaudio2_7 /f
fi
"$WINESERVER" -w 2>/dev/null || true

for cfg in "$plutonium"/storage/t5/players/*.cfg; do
  [ -f "$cfg" ] || continue
  # Apple GPUs support at most 4x MSAA; a config asking for 8x crashes the game.
  sed -i '' -E 's/^seta r_aaSamples "(8|16|32)"/seta r_aaSamples "4"/' "$cfg"
  if [ "${WINDOWED:-0}" = 1 ]; then sed -i '' 's/^seta r_fullscreen "[0-9]*"/seta r_fullscreen "0"/' "$cfg"; fi
  if [ "${FULLSCREEN:-0}" = 1 ]; then sed -i '' 's/^seta r_fullscreen "[0-9]*"/seta r_fullscreen "1"/' "$cfg"; fi
  # BO1 lag-spike tweaks: no motion blur, no distortion effects, no frame cap.
  if [ "${TWEAKS:-1}" = 1 ]; then
    sed -i '' -E 's/^seta r_blur_allowed "[0-9]*"/seta r_blur_allowed "0"/; s/^seta r_distortion "[0-9]*"/seta r_distortion "0"/; s/^seta com_maxfps "[0-9]*"/seta com_maxfps "0"/' "$cfg"
  fi
done

# Plutonium keeps its settings and logs in %LOCALAPPDATA%\Plutonium even when
# it runs from another folder, so the config fixes below would miss them. With
# PLUTONIUM_DIR set, that folder becomes a link to it.
if [ "$plutonium" != "$appdata_plutonium" ] && [ ! -L "$appdata_plutonium" ]; then
  if [ -e "$appdata_plutonium" ]; then
    echo "PLUTONIUM_DIR is set, but the prefix also has $appdata_plutonium." >&2
    echo "Move or delete that folder so Plutonium uses $plutonium, then start again." >&2
    exit 1
  fi
  mkdir -p "$(dirname "$appdata_plutonium")" && ln -s "$plutonium" "$appdata_plutonium"
fi

launcher="$plutonium/bin/plutonium-launcher-win32.exe"
[ -f "$launcher" ] || { echo "no Plutonium launcher at $launcher (set PLUTONIUM_DIR or ./run.sh install)" >&2; exit 1; }
cd "$plutonium/bin"
if [ "${WINE_LOG:-0}" != 0 ]; then
  export WINEDEBUG="-all,err+d3d,err+d3d9,err+d3d_shader,fixme+d3d_shader,err+vkd3d,fixme+d3d9,err+xaudio2,fixme+xaudio2,err+dsound,err+mmdevapi"
  # 2: Direct3D warnings, which name failed resource creations (about 2 MB/s).
  [ "$WINE_LOG" = 2 ] && WINEDEBUG="$WINEDEBUG,warn+d3d9,warn+d3d,warn+d3d_texture"
  # 3: every XAudio2 call (voice formats).
  [ "$WINE_LOG" = 3 ] && WINEDEBUG="$WINEDEBUG,+xaudio2,warn+dsound"
  echo "=== $(date) D3D9=$D3D9 DXVK_ASYNC=${DXVK_ASYNC:-1} WINE_LOG=$WINE_LOG CSMT=${CSMT:-1} LAZY_EXEC=${LAZY_EXEC:-1}" >> "$here/wine.log"
  exec "$wine" "$launcher" >> "$here/wine.log" 2>&1
fi
exec "$wine" "$launcher" > /dev/null 2>&1
