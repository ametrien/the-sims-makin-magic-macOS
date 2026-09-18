# Next step: a scalable, movable game window

Status: planned, not started. Nothing below is in the current patches.

## The goal

1. **Scale to fit.** The game renders at 800x600. Stretch it to the full height of the
   window or screen, keep the 4:3 proportions, and fill the sides with black.
2. **A real Mac window.** Drag it, minimise it, maximise it, and use the green button
   for macOS full screen.

## Why this is not a setting

- The game only works in 16-bit colour, which macOS does not have. Our `ddraw` patch
  emulates the mode, and the game then believes it owns a fullscreen 800x600 display.
- Today the patch simply centres the 800x600 window on the screen (`src/dlls/ddraw/surface.c`,
  the `SetWindowPos` block after `wined3d_device_reset`). Nothing scales it.
- Every attempt to let Windows know the window can move has crashed the game:
  `AllowImmovableWindows=N`, adding `WS_CAPTION` from code, and Wine's virtual desktop
  (see the `experiment/*` branches and the Known issues in the README).

## The approach: change only the Mac side

Leave the Windows side exactly as it is. The game keeps its fixed, borderless 800x600
window and never sees it move or resize. All the changes live in the Mac driver,
`dlls/winemac.drv`, which turns Windows windows into Cocoa windows.

For the game's top-level window only (opt-in, for example a registry value
`HKCU\Software\Wine\AppDefaults\Sims.exe\Mac Driver\ScaleToWindow=Y`):

1. **Mac window chrome.** Give the `NSWindow` a titled, closable, miniaturizable,
   resizable style mask and allow native full screen. The Windows window style stays
   `WS_POPUP`.
2. **Do not report Mac-side moves or resizes to Windows.** Frame changes caused by the
   user dragging or resizing must not produce `WM_WINDOWPOSCHANGED` for the game. This is
   the key difference from the approaches that crashed.
3. **Letterboxed content.** Give the window a black background. Place the Wine content
   view in a centred 4:3 rectangle sized to the window height (or width, if the window is
   narrower than 4:3), and set its `bounds` to 800x600 so AppKit scales everything drawn
   inside it.
4. **OpenGL.** The game draws through wined3d's GL renderer (`renderer=gl` is required).
   Fix the GL surface backing size at 800x600 with `kCGLCPSurfaceBackingSize` so macOS
   scales the drawable to the view. The driver already does this in
   `cocoa_opengl.m` (`wine_updateBackingSize`) and `cocoa_window.m`
   (`wine_setBackingSize`), so the plumbing exists.
5. **Mouse.** Convert event locations through the content view (`convertPoint:fromView:nil`
   gives 0..800 x 0..600 in bounds coordinates), then add the window's fixed Windows
   origin. Also map `GetCursorPos` (the driver's cursor position query) and cursor warping
   (`SetCursorPos`) the same way, and ignore clicks in the black bars.

A useful model is the driver's Retina mode: every coordinate crossing between Windows and
macOS goes through the helpers in `macdrv_cocoa.h` (`cgrect_mac_from_win`,
`cgpoint_win_from_mac` and so on). Grep for `retina_on` to find every place scaling
already has to be handled (about 60 hits).

### Order of work

1. Scaling with black bars in a fixed window (steps 3 to 5). Most likely to work.
2. Mac window chrome and native full screen (steps 1 and 2). Riskier: test that the game
   survives a drag, a minimise and a full-screen toggle, and watch it for at least a
   minute each time.

If step 2 still crashes the game, ship step 1 on its own: scaled, letterboxed full screen
without a movable window.

## Building the Mac driver

`winemac.so` is a native macOS library, not a Windows DLL, so it needs a separate
64-bit configure. The Wine in the app bundle is x86_64 (it runs under Rosetta), so build
for x86_64 even on Apple Silicon:

```bash
cd build
mkdir -p obj64 && cd obj64
export PATH="/opt/homebrew/opt/bison/bin:$PATH"
../wine-11.13/configure --host=x86_64-apple-darwin \
    CC="clang -arch x86_64" OBJC="clang -arch x86_64" \
    --enable-archs=x86_64 --without-x --without-freetype --disable-tests
make -j10 dlls/winemac.drv/winemac.so
```

Verified on 2026-09-18: this builds a stock `winemac.so` in under a minute.

Install into a **copy** of the app for testing:

```
Sims on Mac.app/Contents/Resources/wine/lib/wine/x86_64-unix/winemac.so
```

Keep the original as `winemac.so.orig`. Then add the new changes to
`sims-wine-11.13.patch` and teach `build.sh` and `make-bundle.sh` to build and bundle
`winemac.so` too.

## Testing checklist

- Splash screen, main menu, loading a family and live mode all scaled, with no pink screen.
- Clicks land where the cursor is, at the centre and in all four corners of the picture.
- Clicks in the black bars do nothing.
- Build mode: dragging walls and moving objects works (drags must go to the game, not
  move the window).
- Window: drag, minimise and restore, maximise, green-button full screen and back.
- Before each test, stop leftover Wine processes:
  `"Sims on Mac.app/Contents/Resources/wine/bin/wineserver" -k`
