# Making this available to others

Starting assumption: people have **their own** copy of the game. We only distribute the
Wine changes and a way to apply them, never any game content.

## The constraint that shapes everything else

`wined3d.dll` and `ddraw.dll` are internal Wine modules. The interface between them is
**not stable across versions**: the pair we built works only with Wine 11.13, and only
with that exact build. So "just publish the two libraries" does not work. It breaks for
the first person with a different Wine version.

## Option A. Send the fixes to WineHQ

The longest-lasting route: once the fixes are in Wine, the game works for everyone with
no extra steps.

Ready to send **as is** (these are real bugs, not tied to The Sims):

1. `ddraw_surface4/7_AddAttachedSurface` dereferences NULL when the application passes a
   null pointer. It should return `DDERR_INVALIDPARAMS`.
2. The Vulkan backend of `wined3d` marks the primary buffer with the
   `WINED3D_LOCATION_DRAWABLE` location, which that backend does not have, and
   invalidates all the others, leaving the buffer with no valid location at all.

Needs more work before sending:

3. `GetSurfaceDesc` with an invalid `dwSize`. Needs tests on real Windows: how the v2/v3
   interfaces behave, and whether they really tolerate a wrong size.
4. 16-bit mode emulation. It currently switches on **whenever** the system fails to set
   a mode, which is not acceptable upstream. It needs an explicit opt-in: a registry key
   under `AppDefaults\<game>.exe` or an environment variable. Worth discussing with the
   Wine developers: macOS has no 16-bit modes at all, and that affects a whole generation
   of games, not just this one.

Pro: works for everyone, permanently. Con: takes months, and point 4 may be rejected.

## Option B. Self-contained app (done: `make-bundle.sh`)

Built along the lines of Wineskin/Kegworks: an `.app` with its own Wine 11.13, our
patched libraries and a ready prefix. The user points it at their game files and
launches it with a double click. The version mismatch problem disappears, because the
Wine inside never updates itself.

What it involves:
- a bundle with Wine 11.13 and the patched modules;
- a first-run wizard that asks for the game disc or folder and installs it;
- setting `WINE_D3D_CONFIG=renderer=gl` (do **not** set `AllowImmovableWindows=N`, it
  crashes the game, see the README);
- signing the bundle, otherwise Gatekeeper blocks it on other machines.

Pro: works for anyone, no Terminal needed. Con: about 1.5 GB to download, and the Wine
inside has to be updated by hand.

## Option C. Build script (done: `build.sh`)

The repository plus `build.sh`: downloads the Wine 11.13 sources, applies
`sims-wine-11.13.patch`, builds the two modules and installs them.

Needs: Xcode Command Line Tools, plus mingw-w64 and bison from Homebrew. The build takes
minutes, not hours, because only two PE modules are built, not the whole of Wine.

Pro: honest, transparent, easy to update for new Wine versions. Con: the user needs to be
comfortable with Terminal, and the patches have to be ported to each new Wine version.

## Worth doing either way

- **Test on someone else's machine.** Everything found so far rests on one setup:
  M3 Pro, macOS 26, Wine Staging 11.13. How it behaves on an Intel Mac or another macOS
  version is unknown.
- **Test with a non-Russian edition of the game.** Our copy is a Russian repack. There is
  most likely no difference (the problem is colour depth, not the translation), but that
  is an assumption.
- **Explain the cause in plain words:** why the game did not start at all. That is the
  most valuable part for anyone searching for a fix, since the cause is not obvious and
  is not documented anywhere online.
- **Limit the mode emulation to specific applications** instead of switching it on
  globally whenever the system refuses a mode. This is needed both for upstream and to
  keep other people's prefixes safe.
