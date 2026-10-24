# Plutonium Black Ops 1 on Apple Silicon (work in progress)

Patches and scripts to run Call of Duty: Black Ops (Steam, app 42700) through
[Plutonium](https://plutonium.pw) T5 on an Apple Silicon Mac with CrossOver
26.3. Tested on one M1 Pro.

**Status: work in progress.** It is playable on the machine it was made on,
but the setup from scratch (`setup.sh`, `run.sh install`) has not been tested
on a clean machine, and several problems are still open (see Open items).

BO1 is a 32-bit Direct3D 9 game (its executables import `d3d9.dll`, nothing
from Direct3D 10/11). CrossOver's DXMT and D3DMetal do not support Direct3D 9.
Two renderers work:

- **DXVK** (default): CrossOver's own DXVK 1.10.3, rebuilt from its source with
  three patches (`patches/dxvk/`), on MoltenVK 1.4.2. Smoother than wined3d
  and with fewer glitches.
- **wined3d on Vulkan**: Wine's renderer with this project's patches 0005-0019,
  which fill the parts of its Vulkan renderer that Direct3D 9 games need.

This builds on the BO2 work:
[crossover-rosetta-patches](https://github.com/LuidgiAlt/crossover-rosetta-patches.git)
(0001-0004) and [plutonium-mac](https://github.com/LuidgiAlt/plutonium-mac.git).
0001-0004 are included here so the series applies in one go; 0003 is a newer
version that saves the cache on a background thread and has an off switch.
[`report.md`](report.md) tells the whole investigation, from the first black
screen to the last patch, with the measurements.

## Status (2026-10-24)

| | Result |
|---|---|
| DXVK (default) | Online multiplayer: median 89 FPS, one second under 30 in almost 4 minutes. Zombies: median 108 FPS over 14 minutes, 7 seconds under 30. Campaign: median 74 FPS, 120 FPS in quiet scenes. Shadows must stay off |
| wined3d on Vulkan (`D3D9=vulkan`) | Plays. Matches on a 1080p external display averaged 55-63 FPS (4.6 FPS before 0010), up to 170 FPS looking at the sky. Freezes the first time an effect appears, while its pipeline is built |
| wined3d on OpenGL (`D3D9=gl`) | About 10 FPS in matches |
| Sound | Works, with the game's own XAudio2. Crackles in the campaign |

The remaining slowdowns (grenade explosions, heavy scenes) are not in the
renderer: with DXVK, no call that can block a frame took over 70 ms in a whole
session, while frames took 115-160 ms with 10 ms of GPU work. Most of what is
left is the game's own code running under Rosetta.

## What was fixed

| Problem | Cause | Fix | Patch | Test (`tools/`) |
|---|---|---|---|---|
| Hang at startup | Plutonium arms x86 hardware breakpoints, which Rosetta does not deliver | wineserver keeps debug registers; ntdll emulates execution breakpoints by single-stepping | 0001, 0002 | |
| Hitches on every launch | Vulkan pipelines rebuilt every run | Persistent pipeline cache | 0003 | |
| Multi-second stalls | The bootstrapper turns DEP off; Wine maps memory writable+executable, and every first write traps under Rosetta | Pages become executable only when code runs from them | 0004 | |
| Gunfire silent | Gunfire is xWMA; CrossOver's GStreamer has no WMA decoder | `run.sh` uses `XAudio2_7.dll` from the game's own DirectX redist | none | |
| "Not enough textures" on Vulkan | Vulkan fixed-function pipeline reported 0 texture stages | Report the 8 stages and 25 operations it emulates | 0005 | `d3d9-caps.c` |
| Missing draws, crawl | No SPIR-V for `pow`, `dp2add`, `nrm`, `lrp` | Lower them to other instructions | 0006 | `d3d9-shader-test.c`, `d3d9-shader-test2.c` |
| Crash at `0x0071A90B` | No Vulkan format for `L8`, `L8A8`, `L16` | Store them as `R8`, `R8G8`, `R16` with remapping | 0007 | `d3d9-format-test.c` |
| Black world | `vPos` not handled; `UBYTE4`/`SHORT2`/`SHORT4` vertex data rejected by MoltenVK | Map `vPos` to an input; declare integer inputs and convert in the shader | 0008, 0009 | `d3d9-vpos-test.c`, `d3d9-ubyte4-test.c` |
| 4.6 FPS, GPU 285 ms | Every constant update was a GPU copy that ended the render pass (about 2,500 per frame on a tile-based GPU) | Upload the whole constant buffer from a CPU copy | 0010 | `d3d9-constants-test.c` |
| Spikes | Failed shaders and pipelines rebuilt on every draw | Remember failures | 0011 | |
| One shader failed | Reads input components its declaration leaves out | Accept them for shader model 1-3 | 0012 | |
| 120-200 render passes per frame outdoors | About 90% were restarts on the same targets only to apply a clear (about 170 clears per frame) | Clear inside the running pass | 0013 | `d3d9-clear-test.c` |
| Dips, missing effects | After a pixel shader change the vertex shader kept writing to the previous pixel shader's inputs; Metal rejected those pipelines | Select the vertex shader variant again on pixel shader changes | 0014 | `d3d9-varying-test.c` |
| Freezes of about 650 ms in matches | 0003 saved the pipeline cache on the render thread; at 157 MB a save took about 650 ms | Save on a background thread 10 s after the last new pipeline | 0003 | |
| 16% of the game's thread in `PulseEvent` | Wine's msync `PulseEvent` always calls `sched_yield()`, which can cost the thread its time slice on macOS | Yield only when a waiting thread was woken | 0015 | |
| A quarter of the game's thread in `LockBox` | Managed textures were uploaded by a queued blit that kept their system memory copy in use; locking it waited for all queued work, about a frame | Copy the dirty boxes into an upload buffer when the draw is queued | 0016 | `d3d9-managed-volume-test.c` |
| Samplers rebuilt for every texture bind | About three texture binds per draw; each built a sampler description and searched the sampler tree | Reuse the slot's last sampler when its inputs are the same | 0017 | |
| Whole constant buffer copied on the game's thread | 0010 copied the whole 4 KiB buffer for every change, about 100,000 times per second | Send only the changed bytes; the command thread keeps a copy and uploads all of it | 0018 | `d3d9-constants-test.c` |
| Texture matrices rebuilt for shader draws | Every vertex declaration change (about 10,000 per second) rebuilt the eight fixed-function texture matrices, which vertex shaders never read | Upload them with the next fixed-function draw | 0019 | `d3d9-texmatrix-test.c` |
| Online: the game thread waiting on wineserver | Every socket receive asked wineserver twice, also with nothing to read | Answer an empty receive on a nonblocking socket in ntdll | 0021 | |
| DXVK: no device | CrossOver's DXVK requires geometry shaders and cull distance. CodeWeavers' MoltenVK 1.2.10 has no cull distance, Khronos' 1.4.2 no geometry shaders | Ask for them only when the device has them; run on 1.4.2 | dxvk/0001 | |
| DXVK: black screen, game running | Each texture has a depth-compare variant at the same binding; MoltenVK loses its sampler, and without argument buffers Metal rejects the shader (42 to 172 pixel shaders failed) | No depth-compare variant; depth textures are sampled like colour ones (shadows off) | dxvk/0002 | |
| DXVK: freezes on new effects | DXVK 1.10 builds each new pipeline on the render thread | Build them on two background threads and skip their draws meanwhile; the render thread never waits for a compile | dxvk/0003 | |

0005-0014 and 0016-0019 are not specific to BO1: they fill gaps in wined3d's
Vulkan renderer for Direct3D 9 and remove costs any Direct3D 9 game pays.
0015 and 0021 are in Wine's core and apply to any program (0021 is also in
`crossover-rosetta-patches` as 0006). The DXVK patches apply to any Direct3D 9
game on DXVK with MoltenVK. Each patch starts with a header: what it changes,
why, and how it was tested.

## How the problems were found

The work came in three stages; `report.md` has the details and numbers.

1. **Getting Vulkan to draw (0005-0009, 0012).** Each missing piece showed up
   as a wined3d or vkd3d-shader error with `WINE_LOG=1`. Each was reproduced
   with a small Direct3D 9 program in `tools/` and compared with the OpenGL
   renderer's output.
2. **The GPU (0010, 0011, 0013, 0014).** The Metal HUD showed 285 ms of GPU
   time per frame. A render pass counter
   (`patches/diagnostics/wined3d-vk-render-pass-stats.patch`) found thousands
   of render pass ends per frame, from constant updates and then from clears.
   On Apple's tile-based GPUs each one stores and reloads every render target.
   Afterwards the GPU needed under 10 ms per frame.
3. **The game's thread (0015-0019, 0003's background save).** A per-thread
   CPU log and macOS's `sample` showed one thread at about 94%: the game's
   main thread, while wined3d's render thread waited for work about two
   thirds of the time. A timer around the lock that every Direct3D 9 call
   takes (`patches/diagnostics/wined3d-d3d-time.patch`) split that thread's
   time by function, which found the `LockBox` wait, and then by section of
   `wined3d_device_apply_stateblock()`, which found the sampler, constant and
   texture matrix costs. Rosetta hides the game's own code from `sample`, but
   Wine's functions and thread names stay visible.

After these, about a third of the game's thread is Direct3D 9 calls with no
single large cost left, and most of the rest is the game's own code running
under Rosetta, which Wine patches cannot make faster.

4. **DXVK (2026-10-24).** CrossOver's DXVK failed to create its device on
   MoltenVK 1.4.2; MoltenVK's own error (`VK_ERROR_FEATURE_NOT_PRESENT`, with
   the feature numbers) named the two features. With the device working, the
   game ran with a black screen; `WINE_LOG=1` showed MoltenVK's Metal compile
   errors, and `DUMP=1` the converted shaders. A timer on every DXVK call that
   can block a frame (`STALL=1`) then showed that the remaining freezes are
   not in DXVK.

## Requirements

- CrossOver 26.3.0 (build 26.3.0.39832), activated.
- Xcode command line tools and Homebrew `mingw-w64 bison flex`; for DXVK also
  `meson ninja glslang`.
- For DXVK: MoltenVK v1.4.2, `MoltenVK-macos.tar` from
  [Khronos' releases](https://github.com/KhronosGroup/MoltenVK/releases/tag/v1.4.2)
  (2026-07-24).
- Black Ops through Steam. Plutonium requires owning it.

## Building

```bash
curl -LO https://media.codeweavers.com/pub/crossover/source/crossover-sources-26.3.0.tar.gz
tar -xzf crossover-sources-26.3.0.tar.gz sources/wine
cd sources/wine && for p in ../../patches/00*.patch; do patch -p1 < "$p"; done
mkdir ../../build && cd ../../build
export SDKROOT=$(xcrun --sdk macosx --show-sdk-path) MACOSX_DEPLOYMENT_TARGET=15.0 \
  CC='clang -arch x86_64' CXX='clang++ -arch x86_64' ac_cv_func_pipe2=no \
  PATH="/opt/homebrew/opt/bison/bin:/opt/homebrew/opt/flex/bin:$PATH"
../sources/wine/configure --host=x86_64-apple-darwin24 --enable-archs=i386,x86_64 \
  --disable-tests --without-x --without-wayland --without-gstreamer --without-ffmpeg \
  --without-freetype --without-gnutls --without-vulkan --without-oss --without-alsa \
  --without-pulse --without-sane --without-usb --without-v4l2 --without-pcap \
  --without-capi --without-opencl --without-cups
make -j10 dlls/ntdll/ntdll.so server/wineserver dlls/wined3d/i386-windows/wined3d.dll
```

DXVK, from the same source archive (`sources/dxvk`, CodeWeavers' DXVK 1.10.3):

```bash
tar -xzf crossover-sources-26.3.0.tar.gz sources/dxvk
cd sources/dxvk && for p in ../../patches/dxvk/00*.patch; do patch -p1 < "$p"; done
meson setup --cross-file build-win32.txt --buildtype release -Denable_d3d10=false \
  -Denable_d3d11=false -Denable_dxgi=false -Dcpp_args='-include cstdint' build.w32
ninja -C build.w32
```

`-include cstdint` is needed with current MinGW GCC (16), which this DXVK
version predates. Only the 32-bit `d3d9.dll` is used.

When building with a diagnostic patch and then without it, delete the wined3d
objects in between (`rm build/dlls/wined3d/i386-windows/*.o`): a source file
restored in the same second as the last build looks up to date to `make`, and
its object keeps the diagnostic code.

The patches apply without offsets to `crossover-sources-26.3.0.tar.gz`
(SHA-256 `ac99c8ca4b3848f3e81784135f023df266b61c2345726ea55a50b3e030dd6872`).

## Setup

```bash
DXVK_BUILD=sources/dxvk/build.w32 MOLTENVK_ARCHIVE=~/Downloads/MoltenVK-macos.tar \
  ./setup.sh build        # runner/CrossOver (patched copy) and prefix/
./run.sh install ~/Downloads/plutonium.exe
```

`setup.sh` makes an APFS copy of CrossOver's runtime in `runner/CrossOver`
and installs `ntdll.so`, `wineserver` and the 32-bit `wined3d.dll` into it.
With `DXVK_BUILD` it adds DXVK's `d3d9.dll` (as `d3d9.dll.dxvk`, marked as a
Wine builtin with the Wine build's `winebuild`), and with `MOLTENVK_ARCHIVE`
the x86_64 part of MoltenVK 1.4.2 (as `lib64/libMoltenVK.dylib.142`; the
script checks it against the tested build's SHA-256). Without them, `run.sh`
uses wined3d. The originals are kept as `*.orig`. CrossOver.app is not
modified.

If Plutonium is already installed somewhere else, set `PLUTONIUM_DIR` to the
folder that contains `bin/plutonium-launcher-win32.exe`. Plutonium keeps its
settings and logs in the prefix's `AppData/Local/Plutonium` even when it runs
from another folder, so `run.sh` makes that a link to `PLUTONIUM_DIR`; if a
real folder is already there, it stops and asks you to move it. In the launcher,
point BO1 at its Steam folder,
`~/Library/Application Support/Steam/steamapps/common/Call of Duty Black Ops`.

## Playing

```bash
./run.sh                       # play (DXVK when installed)
HUD=1 ./run.sh                 # with Apple's Metal HUD (FPS, GPU time)
D3D9=vulkan ./run.sh           # wined3d on Vulkan instead
./run.sh kill                  # stop the game and everything in the prefix
```

Settings that work (Settings > Graphics):

| Setting | Value |
|---|---|
| Resolution | 1512x982 fullscreen on the built-in display, 1920x1080 on a 1080p external display, or 1280x720 windowed |
| Anti-aliasing | Off |
| Shadows | Off (required with DXVK: dxvk/0002 removes the depth-compare sampling shadows use) |
| Vsync | On (turning it off did not raise the median frame rate) |

`run.sh` also sets `r_blur_allowed 0`, `r_distortion 0` and `com_maxfps 0` on
every launch (`TWEAKS=0` skips them).

With DXVK, `run.sh` installs its `d3d9.dll` and MoltenVK 1.4.2 in the runner,
runs the Plutonium launcher's window on wined3d's OpenGL renderer (it fails on
MoltenVK 1.4.2 with wined3d's Vulkan renderer), and writes DXVK's log to
`dxvk-log/`. DXVK keeps the pipelines it has built in
`<game folder>/plutonium-bootstrapper-win32.dxvk-cache` and builds them again
while loading. A pipeline seen for the first time is built in the background
and its draws are skipped for a frame or two. With `D3D9=vulkan` or `gl`,
`run.sh` puts CrossOver's `d3d9.dll` and MoltenVK back.

wined3d keeps its Vulkan pipelines in
`prefix/drive_c/users/crossover/AppData/Local/wined3d-vk-cache/plutonium-bootstrapper-win32.exe.pipelines`
(0003). A map or effect seen for the first time builds its pipelines, and they
are saved for the next runs on a background thread, 10 seconds after the last
new one. MoltenVK compiles the whole cache before the first frame, so a large
cache makes startup slower; delete the file to start fresh. After the cache is
deleted, the first map load can sit on the loading screen for a minute or
more while Apple's Metal compiler builds the pipelines.

### Options

| Option | Effect |
|---|---|
| `D3D9=dxvk` | The patched DXVK on MoltenVK 1.4.2 (default when installed) |
| `D3D9=vulkan`, `D3D9=gl` | wined3d's Vulkan or OpenGL renderer |
| `DXVK_ASYNC=0` | DXVK builds new pipelines on the render thread (freezes on new effects) |
| `STALL=1` | DXVK logs every call over 5 ms that can block a frame (`stall:` lines in `dxvk-log/`) |
| `HUD=1` | Metal performance HUD |
| `FULLSCREEN=1` / `WINDOWED=1` | Set the game's display mode before starting |
| `PLUTONIUM_DIR=…` | Plutonium folder (default `%LOCALAPPDATA%\Plutonium` in the prefix) |
| `BO1_DIR=…` | BO1's folder, for its XAudio2 (default: Steam's) |
| `TWEAKS=0` | Leave blur, distortion and the frame cap as configured |
| `XAUDIO=builtin` | Wine's XAudio2 instead of the game's (gunfire is silent) |
| `CSMT=0` | No wined3d command thread |
| `LAZY_EXEC=0` | Turn the lazy-exec fix (0004) off |
| `PIPELINE_CACHE=0` | Run without the pipeline cache file |
| `WINE_LOG=1`, `2`, `3` | Log Direct3D, shader and audio errors to `wine.log`; 2 adds Direct3D warnings (about 2 MB/s), 3 every XAudio2 call |
| `STATS=1` | Log breakpoint-emulation step counts |
| `SYNCSTATS=1` | Log msync wait counts and times, and PulseEvent counts (needs the diagnostic ntdll) |
| `DUMP=1` | Save every shader MoltenVK converts to `shader-dump/` |

## Troubleshooting

- **Black screen with DXVK, sound and clicks working.** Shaders failed to
  compile. Run with `WINE_LOG=1` and look for `mvk-error` in `wine.log`;
  `DUMP=1` saves the converted shaders. Check that shadows are off.
- **"D3D11 Error: Unable to create device and swap chain"** from the
  launcher: MoltenVK 1.4.2 with wined3d's Vulkan renderer. `run.sh` avoids it
  by giving the launcher OpenGL; if it appears, report it.
- **Black screen at startup, game running (wined3d).** MoltenVK compiles every pipeline
  in the cache before the first frame, so a large or stale cache looks like a
  hang. Stop the game and delete
  `prefix/drive_c/users/crossover/AppData/Local/wined3d-vk-cache/plutonium-bootstrapper-win32.exe.pipelines`.
- **Black screen in fullscreen on the built-in display.** Use 1512x982 or
  windowed mode.
- **Loading screen for a minute.** Normal after a cache reset.
- **Crash with 8x anti-aliasing.** Apple GPUs support at most 4x; `run.sh`
  clamps the config.

## Other patches

- `patches/experimental/wined3d-vk-dynamic-constant-buffers-and-ring.patch`
  (after 0012): dynamic uniform buffers and a constant buffer ring, so constant
  changes do not rebuild the descriptor set. Correct in tests, slower in BO1
  (likely MoltenVK re-binding every descriptor of a set on each bind).
- `patches/diagnostics/`: instrumentation used to find the causes, not for
  play:
  - `wined3d-vk-render-pass-stats.patch` (on top of the experimental patch):
    render passes, draws, constant uploads, waits on the command thread,
    pipeline compile times, slow frames, descriptor set rebuilds;
  - `msync-wait-stats.patch`: msync waits in the kernel vs through
    wineserver, and PulseEvent calls. Build it into a separate `ntdll.so`,
    install it in the runner in place of the normal one, and run with
    `SYNCSTATS=1`;
  - `wined3d-d3d-time.patch`: where the game's thread spends its time in
    Direct3D (by function, by section of `apply_stateblock`, by
    fixed-function branch), with `WINE_LOG=1`. The header says how to install
    it.

## Test tools

Each `tools/d3d9-*.c` draws a few pixels and prints the values. The build
command is at the top of each file; run it with the runner's `wine` and
`WINE_D3D_CONFIG=renderer=vulkan` or `renderer=gl`. The expected values are the
OpenGL ones.

| Tool | Checks |
|---|---|
| `d3d9-caps.c` | Texture stages and operations reported |
| `d3d9-shader-test.c`, `d3d9-shader-test2.c` | `pow`, `dp2add`, `nrm`, `lrp` |
| `d3d9-format-test.c` | `A8L8` and `L8` textures |
| `d3d9-vpos-test.c` | `vPos` |
| `d3d9-ubyte4-test.c` | `UBYTE4` and `SHORT2` vertex data |
| `d3d9-constants-test.c` | 4,096 draws with per-draw vertex and pixel shader constants |
| `d3d9-clear-test.c` | Colour and depth/stencil clears between draws |
| `d3d9-varying-test.c` | Switching only the pixel shader between draws |
| `d3d9-managed-volume-test.c` | A managed volume texture rewritten every frame: `LockBox` time and the last colour |
| `d3d9-texmatrix-test.c` | A texture matrix set while a vertex shader is bound applies to the next fixed-function draw |

## Open items

- The game's main thread is the limit in matches; most of what is left is
  the game's own code under Rosetta.
- Spikes when new effects first appear: with wined3d, pipeline compiles
  (usually 4-8 ms, sometimes 50-200 ms); with DXVK they are built in the
  background.
- Short freezes on grenade explosions and while loading: not in the renderer.
- Audio crackles in the campaign, with both renderers.
- DXVK: shadows need the depth-compare variant that MoltenVK 1.4.2 cannot
  translate; in `tools/d3d9-clear-test` draws after a mid-frame clear are
  missing (nothing noticed in the game).
- `setup.sh` with `MOLTENVK_ARCHIVE`: extracting from Khronos' archive has not
  been tested (the tested MoltenVK was extracted by hand).
- Pipeline cache size: startup gets slower as the cache grows.
- Texture changes still rebuild the descriptor set for the next draw.
- World at War (T4) and MW3 (IW5): also 32-bit Direct3D 9 on the same
  Plutonium client, so the patches likely help, but they are untested and
  `run.sh` only handles BO1's paths and config.
- `setup.sh` and `run.sh install` on a clean machine: untested.

## License

- The patches (`patches/`) are under LGPL-2.1-or-later (`patches/LICENSE`),
  the license of the Wine files they modify. 0001 and 0002 derive from
  [wine-rosetta-fix](https://github.com/masonmcbride/wine-rosetta-fix)
  (LGPL-2.1). If you distribute builds, the LGPL requires you to provide the
  complete source with them: the patches plus the CrossOver sources above.
- The DXVK patches (`patches/dxvk/`) are under DXVK's zlib license
  (`patches/dxvk/LICENSE`).
- The scripts and test tools are under the MIT license (`LICENSE`).

Only patches and scripts are distributed here: no game files, no builds, no
MoltenVK, no Microsoft DLLs (XAudio2 is taken from your own copy of the game) and nothing from
CodeWeavers' proprietary code. Running a CrossOver runtime requires a valid
CrossOver license. The patches change Wine, not the game; they do not bypass
DRM or anti-cheat.

Plutonium, Call of Duty and CrossOver belong to their owners. This project is
not affiliated with them.
