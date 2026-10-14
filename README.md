# Plutonium Black Ops 1 on Apple Silicon

**Coming soon.** Patches and scripts to play Call of Duty: Black Ops through
[Plutonium](https://plutonium.pw) T5 on an Apple Silicon Mac with CrossOver 26.3.

BO1 is a 32-bit Direct3D 9 game, and CrossOver's DXMT and D3DMetal don't
support Direct3D 9. This project makes Wine's wined3d run it on Vulkan
(MoltenVK) instead, with a series of fixes to wined3d's Vulkan renderer.

Where it stands on an M1 Pro:

| | |
|---|---|
| Frame rate | Up to 120 FPS (M1 Pro), comfortable in matches but some spikes can be annoying (was around avg 4 FPS before the fixes tho) |
| Graphics | World, effects and textures render; a few effects may still be missing and some weird light glitches |
| Sound | Works, gunfire and other sound from xWMA included |
| Zombies | Kino works but not fully tested...
| Multi | It works but currently playing training against bot, Online using Plutonium seems to work but not fully tested yet
| Compared to BO2 | DX11 is different to DX09, still learning how all of it works under the hood, BO2 is more stable right now compared to BO1 in this state.

It builds on the Black Ops II work but adapted for DirectX 9:
[crossover-rosetta-patches](https://github.com/LuidgiAlt/crossover-rosetta-patches) and
[plutonium-mac](https://github.com/LuidgiAlt/plutonium-mac).

The patches, setup scripts and full write-up will be published here once the
setup has been tested on a clean machine. World at War and MW3 may follow in the future if I have time...

Plutonium, Call of Duty and CrossOver belong to their owners. This project is
not affiliated with them.
