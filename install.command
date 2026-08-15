#!/bin/zsh
WD="/Applications/Wine Staging.app/Contents/Resources/wine/lib/wine/i386-windows"
D="$HOME/sims-wine-patches/dlls"
[ -f "$WD/ddraw.dll.orig" ] || cp "$WD/ddraw.dll" "$WD/ddraw.dll.orig"
[ -f "$WD/wined3d.dll.orig" ] || cp "$WD/wined3d.dll" "$WD/wined3d.dll.orig"
cp "$D/ddraw-patched.dll" "$WD/ddraw.dll" && cp "$D/wined3d-patched.dll" "$WD/wined3d.dll" && echo "патчи установлены"
