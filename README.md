# The Sims 1 on Apple Silicon

Wine patches that make **The Sims (2000) and its expansions** run on Apple Silicon Macs.

You bring your own copy of the game. This repository only contains patches to Wine and
the tooling to apply them.


---

## Quick start

The easiest way to play is the self-contained app. It carries its own patched Wine, so
updating Wine Staging can never break it.

```bash
brew install mingw-w64 bison     # once
./build.sh                       # build the patched ddraw.dll and wined3d.dll
./make-bundle.sh                 # creates dist/Sims on Mac.app
open "dist/Sims on Mac.app"
```

On first launch the app sets up Wine and asks for a folder:

- **your installer discs** (the folder containing `setup.exe`), or
- **an existing installation** (the folder containing `Sims.exe`).

If the installer stops with *"Insert next disk"* (`setup-2.bin` not found), type the path
to the second disc folder in the dialog, using Wine's `Z:` drive, for example
`Z:\Users\you\Games\sims\disc2`, and press OK.

After that, just open **Sims on Mac.app** to play.

> **Pink splash screen, then the game quits?** You are running unpatched Wine. This
> happens when Wine Staging updates itself and replaces the patched libraries. Use the
> app above, or re-run `install.command` with Wine 11.13.

## Why the game does not run

The Sims 1 renders **only in 16-bit colour**. Its executable contains exactly three
rasteriser classes, and all of them are 16-bit:

```
cStandardBlitter16
cStandardZBlitter16
cLineRender16
```

There is no 24-bit or 32-bit renderer anywhere in the binary.

macOS has no 16-bit display modes at all — and never had. So the game asks Wine for a
list of display modes, finds nothing it can use, stays in 32-bit, fails to create its
terrain renderer, and crashes on a null pointer somewhere inside `cTerrain`.

Every symptom people report comes from this one cause:

| Symptom | What is actually happening |
|---|---|
| Splash screen is pink and half the width | 16-bit pixels written into a 32-bit buffer |
| Black screen, music plays | rendering never starts, the game dies during setup |
| Crash a few seconds after launch | null renderer, because no 16-bit mode was available |

This is not specific to any particular release or repack of the game. It affects the
whole generation of 16-bit-only titles on macOS.

## What the patches do

1. **Report 16-bit display modes.** macOS offers none, so Wine advertises the existing
   modes as 16-bit too.
2. **Add the classic resolutions.** macOS only reports its own panel-shaped resolutions
   (1024×640, 1280×800…). Old games ask for 640×480, 800×600, 1024×768 and give up if
   they are missing.
3. **Emulate the mode switch.** When the host refuses to change to 800×600×16, keep the
   host mode and hand the game a 16-bit primary surface instead. The contents are
   converted when presented.
4. **Fill in the surface description.** The game asks for the desktop pixel format with
   an uninitialised `dwSize`; Wine rejected the call and returned nothing, so the game
   never learned the screen format.

Two unrelated Wine bugs were found and fixed along the way:

- `ddraw_surface4/7_AddAttachedSurface` dereferenced a NULL attachment instead of
  returning `DDERR_INVALIDPARAMS`.
- The Vulkan backend marked the swapchain front buffer as living in
  `WINED3D_LOCATION_DRAWABLE` — a location that does not exist in that backend — and
  invalidated every other location, leaving the buffer with no valid content anywhere.

## Requirements

- Apple Silicon Mac (tested on M3 Pro, macOS 26)
- [Wine Staging 11.13](https://github.com/Gcenx/macOS_Wine_builds/releases) for macOS
- Your own copy of The Sims 1

The patches are built against Wine 11.13 specifically. `wined3d` and `ddraw` are internal
Wine modules with no stable interface between versions, so the built libraries will not
work with a different Wine build — rebuild them against whatever version you use.

## Install

### Build and install the patched libraries

```bash
./build.sh
```

Downloads the Wine 11.13 sources, applies the patch, builds the two modules and installs
them, keeping the originals as `*.orig`. Takes a few minutes: only `ddraw.dll` and
`wined3d.dll` are built, not the whole of Wine.

Needs Xcode Command Line Tools plus `mingw-w64` and `bison` from Homebrew:

```bash
brew install mingw-w64 bison
```

### Install the game

Run your own installer under Wine, then launch with:

```bash
cd "$HOME/.wine/drive_c/Program Files (x86)/SIMS_MAG"
WINE_D3D_CONFIG="renderer=gl" wine Sims.exe
```

`renderer=gl` is **required**. On the Vulkan backend MoltenVK cannot present a 16-bit
format and the game will not start.

## Known issues

- **The window cannot be moved or minimised.** The game believes it is fullscreen, so its
  window has no frame. `Cmd+H` and `Cmd+Tab` work; `Cmd+M` does not. Three approaches were
  tried and all of them break the game — see the notes below.
- Wine's `AllowImmovableWindows=N` (Mac driver) does make the window movable at the Cocoa
  level, but the game then crashes a few seconds after launch. Do not set it.
- Changing the window style from code kills the game — tried both during device reset and
  from a delayed thread. See `experiment/window-caption`.
- Wine's virtual desktop is incompatible with the mode emulation: inside it Wine handles
  the mode change itself and reports success, so the emulation never kicks in. See
  `experiment/virtual-desktop`.
- Updating Wine overwrites the patched libraries. Re-run `install.command`.

## Repository layout

```
src/          patched Wine sources
dlls/         prebuilt libraries (Wine 11.13 only)
build.sh      build and install from sources
make-bundle.sh   assemble the self-contained app
launcher.sh   the app's launcher script
install.command  reinstall prebuilt libraries
sims-wine-11.13.patch   the patch itself
```

Branches `experiment/*` hold approaches that did not work, each with notes on why —
useful if you plan to pick this up.

## Upstream

Two of the fixes are genuine Wine bugs, unrelated to any game, and are suitable for
WineHQ as they are. The 16-bit mode emulation is not: it currently triggers whenever a
mode change fails, and would need an explicit opt-in before it could be proposed.

See [DISTRIBUTION.md](DISTRIBUTION.md).

## Licence

The patches follow Wine's licence (LGPL 2.1+). No game content is included or
distributed here.

## Building the self-contained app

```bash
./build.sh          # patched libraries
./make-bundle.sh    # assembles dist/Sims on Mac.app
```

The bundle carries its own copy of Wine with the patches already applied, so it does not
depend on what the user has installed and does not break when Wine updates. On first
launch it creates its own prefix and asks for the folder containing your installer or an
existing installation.

Roughly 1.5 GB. Sign it before handing it to anyone, otherwise Gatekeeper blocks it.
