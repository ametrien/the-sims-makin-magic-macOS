#!/bin/zsh
# Builds the patched ddraw.dll and wined3d.dll from Wine sources and installs them.
# Only these two PE modules are built, not the whole of Wine — takes a few minutes.
set -e

WINE_VERSION="11.13"
WINE_APP="${WINE_APP:-/Applications/Wine Staging.app}"
WINE_LIBS="$WINE_APP/Contents/Resources/wine/lib/wine/i386-windows"
HERE="${0:A:h}"
WORK="${WORK:-$HERE/build}"

info() { print -P "%F{green}==>%f $1"; }
fail() { print -P "%F{red}error:%f $1" >&2; exit 1; }

# --- checks ---------------------------------------------------------------

[[ -d "$WINE_APP" ]] || fail "Wine not found at $WINE_APP
Install Wine Staging $WINE_VERSION, or set WINE_APP to its location."

installed=$("$WINE_APP/Contents/Resources/wine/bin/wine" --version 2>/dev/null || echo unknown)
case "$installed" in
    *"$WINE_VERSION"*) ;;
    *) print -P "%F{yellow}warning:%f installed Wine is '$installed', patches target $WINE_VERSION.
   wined3d and ddraw have no stable interface between versions — this may not work." ;;
esac

command -v i686-w64-mingw32-gcc >/dev/null || fail "mingw-w64 missing. Run: brew install mingw-w64"

# macOS ships bison 2.3; Wine needs 3.0+
for candidate in /opt/homebrew/opt/bison/bin /usr/local/opt/bison/bin; do
    [[ -x "$candidate/bison" ]] && export PATH="$candidate:$PATH" && break
done
bison_version=$(bison --version 2>/dev/null | head -1 | grep -oE '[0-9]+' | head -1)
[[ "${bison_version:-0}" -ge 3 ]] || fail "bison 3.0+ missing. Run: brew install bison"

# --- sources --------------------------------------------------------------

mkdir -p "$WORK"
cd "$WORK"

if [[ ! -d "wine-$WINE_VERSION" ]]; then
    if [[ ! -f "wine-$WINE_VERSION.tar.xz" ]]; then
        info "Downloading Wine $WINE_VERSION sources"
        curl -# -L -o "wine-$WINE_VERSION.tar.xz" \
            "https://dl.winehq.org/wine/source/11.x/wine-$WINE_VERSION.tar.xz"
    fi
    info "Unpacking"
    tar -xf "wine-$WINE_VERSION.tar.xz"

    info "Applying patch"
    patch -p1 -d "wine-$WINE_VERSION" < "$HERE/sims-wine-$WINE_VERSION.patch"
fi

# --- build ----------------------------------------------------------------

if [[ ! -f "obj/Makefile" ]]; then
    info "Configuring (32-bit modules only)"
    mkdir -p obj && cd obj
    "../wine-$WINE_VERSION/configure" --enable-archs=i386 \
        --without-x --without-freetype --disable-tests >configure.log 2>&1 \
        || fail "configure failed, see $WORK/obj/configure.log"
    cd "$WORK"
fi

info "Building ddraw.dll and wined3d.dll"
cd obj
make -j"$(sysctl -n hw.ncpu)" \
    dlls/ddraw/i386-windows/ddraw.dll \
    dlls/wined3d/i386-windows/wined3d.dll >build.log 2>&1 \
    || fail "build failed, see $WORK/obj/build.log"

# --- install --------------------------------------------------------------

info "Installing into $WINE_LIBS"
for module in ddraw wined3d; do
    [[ -f "$WINE_LIBS/$module.dll.orig" ]] || cp "$WINE_LIBS/$module.dll" "$WINE_LIBS/$module.dll.orig"
    cp "dlls/$module/i386-windows/$module.dll" "$WINE_LIBS/$module.dll"
    i686-w64-mingw32-strip "$WINE_LIBS/$module.dll" 2>/dev/null || true
done

print
info "Done. Originals kept as ddraw.dll.orig and wined3d.dll.orig"
print
print "Launch the game with the OpenGL renderer — this is required:"
print '    WINE_D3D_CONFIG="renderer=gl" wine Sims.exe'
