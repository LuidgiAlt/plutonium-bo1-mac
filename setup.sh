#!/bin/bash
# Create the runner and prefix used by run.sh:
#   runner/CrossOver  APFS copy of CrossOver's runtime with the patched binaries
#   prefix/           Wine prefix
#   [DXVK_BUILD=<dxvk build.w32 folder>] [MOLTENVK_ARCHIVE=<MoltenVK-macos.tar>] \
#     ./setup.sh [path to the Wine build folder from README.md]
# DXVK_BUILD and MOLTENVK_ARCHIVE add the DXVK renderer (run.sh's default):
# the patched DXVK d3d9.dll and MoltenVK 1.4.2 (Khronos' v1.4.2 release).
set -euo pipefail
here=$(cd -- "$(dirname -- "$0")" && pwd)
build=${1:-$here/build}
crossover=${CROSSOVER_APP:-/Applications/CrossOver.app}
want=26.3.0.39832

version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$crossover/Contents/Info.plist" 2>/dev/null || true)
[ "$version" = "$want" ] || { echo "need CrossOver $want, found '${version:-none}' at $crossover" >&2; exit 1; }

# BO1 is 32-bit, so only the i386 wined3d is needed.
files=(
  "dlls/ntdll/ntdll.so|lib/wine/x86_64-unix/ntdll.so"
  "server/wineserver|bin/wineserver"
  "dlls/wined3d/i386-windows/wined3d.dll|lib/wine/i386-windows/wined3d.dll"
)
for entry in "${files[@]}"; do
  [ -f "$build/${entry%%|*}" ] || { echo "missing $build/${entry%%|*}: build the patches first (README.md)" >&2; exit 1; }
done

runner="$here/runner/CrossOver"
if [ ! -d "$runner" ]; then
  mkdir -p "$here/runner"
  cp -c -R "$crossover/Contents/SharedSupport/CrossOver" "$runner" 2>/dev/null ||
    cp -R "$crossover/Contents/SharedSupport/CrossOver" "$runner"
fi
# Originals kept as .orig; run.sh switches d3d9.dll (DXVK) and restores
# xaudio2_7.dll from them.
for f in lib/wine/i386-windows/d3d9.dll lib/wine/i386-windows/xaudio2_7.dll; do
  [ -f "$runner/$f.orig" ] || cp -p "$runner/$f" "$runner/$f.orig"
done
for entry in "${files[@]}"; do
  src=$build/${entry%%|*} dst=$runner/${entry#*|}
  [ -f "$dst.orig" ] || cp -p "$dst" "$dst.orig"
  case "$src" in
  *.dll) i686-w64-mingw32-strip --strip-debug -o "$dst.new" "$src" ;;
  *) cp "$src" "$dst.new" && codesign -fs - "$dst.new" 2>/dev/null ;;
  esac
  mv -f "$dst.new" "$dst"
done

# DXVK: d3d9.dll from the DXVK build (README.md), stripped and marked as a
# Wine builtin, which the runner's i386-windows folder requires.
if [ -n "${DXVK_BUILD:-}" ]; then
  dll=$DXVK_BUILD/src/d3d9/d3d9.dll
  [ -f "$dll" ] || { echo "missing $dll: build DXVK first (README.md)" >&2; exit 1; }
  dst=$runner/lib/wine/i386-windows/d3d9.dll.dxvk
  i686-w64-mingw32-strip -o "$dst.new" "$dll"
  "$build/tools/winebuild/winebuild" --builtin "$dst.new"
  mv -f "$dst.new" "$dst"
  echo "DXVK: $dst"
fi
# MoltenVK 1.4.2: the x86_64 part of Khronos' MoltenVK-macos.tar (v1.4.2).
# CrossOver's own MoltenVK (1.2.10) is kept as libMoltenVK.dylib.orig.
mvk_sha=1876a14a99ea4cd578d82f0ca223d44c2ba2b8c47901043dd251729e8c8e239b
if [ -n "${MOLTENVK_ARCHIVE:-}" ]; then
  tmp=$(mktemp -d)
  member=$(tar -tf "$MOLTENVK_ARCHIVE" | grep -m1 'dynamic/dylib/macOS/libMoltenVK.dylib$')
  [ -n "$member" ] || { echo "no macOS libMoltenVK.dylib in $MOLTENVK_ARCHIVE" >&2; rm -rf "$tmp"; exit 1; }
  tar -xf "$MOLTENVK_ARCHIVE" -C "$tmp" "$member"
  lipo -thin x86_64 "$tmp/$member" -output "$tmp/libMoltenVK.dylib"
  sha=$(shasum -a 256 "$tmp/libMoltenVK.dylib" | cut -d' ' -f1)
  [ "$sha" = "$mvk_sha" ] || echo "note: this MoltenVK is not the tested v1.4.2 build (SHA-256 $sha)" >&2
  [ -f "$runner/lib64/libMoltenVK.dylib.orig" ] || cp -p "$runner/lib64/libMoltenVK.dylib" "$runner/lib64/libMoltenVK.dylib.orig"
  mv -f "$tmp/libMoltenVK.dylib" "$runner/lib64/libMoltenVK.dylib.142"
  rm -rf "$tmp"
  echo "MoltenVK 1.4.2: $runner/lib64/libMoltenVK.dylib.142"
fi
echo "runner: $runner"

export CX_ROOT="$runner" WINEPREFIX="$here/prefix" WINESERVER="$runner/bin/wineserver"
export WINEDLLPATH="$runner/lib/wine/x86_64-windows:$runner/lib/wine/x86_64-unix" WINEDEBUG=-all
wine="$runner/lib/wine/x86_64-unix/wine"
[ -f "$WINEPREFIX/system.reg" ] || "$wine" wineboot -i > /dev/null 2>&1
# PlayStation controllers through SDL as XInput gamepads (the game reads XInput
# only; Wine otherwise exposes Sony pads as raw HID, which XInput ignores).
"$wine" reg add 'HKLM\System\CurrentControlSet\Services\WineBus\Devices\054c' /v Hidraw /t REG_DWORD /d 0 /f > /dev/null 2>&1
"$WINESERVER" -w
echo "prefix: $WINEPREFIX"
