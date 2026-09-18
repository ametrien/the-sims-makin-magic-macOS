#!/bin/zsh
# Assembles a self-contained .app: bundled Wine + patched libraries + its own prefix.
# The user drops in their own copy of the game; nothing game-related is bundled here.
set -e

APP_NAME="${APP_NAME:-Sims on Mac}"
WINE_APP="${WINE_APP:-/Applications/Wine Staging.app}"
HERE="${0:A:h}"
OUT="${OUT:-$HERE/dist}"
APP="$OUT/$APP_NAME.app"

info() { print -P "%F{green}==>%f $1"; }
fail() { print -P "%F{red}error:%f $1" >&2; exit 1; }

[[ -d "$WINE_APP" ]] || fail "Wine not found at $WINE_APP"
[[ -f "$HERE/dlls/ddraw-patched.dll" ]] || fail "patched libraries missing — run ./build.sh first"

info "Creating $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# --- bundled Wine ---------------------------------------------------------

info "Copying the Wine runtime (this takes a while and about 1.5 GB)"
cp -R "$WINE_APP/Contents/Resources/wine" "$APP/Contents/Resources/wine"

info "Installing patched libraries into the bundle"
LIBS="$APP/Contents/Resources/wine/lib/wine/i386-windows"
cp "$HERE/dlls/ddraw-patched.dll"   "$LIBS/ddraw.dll"
cp "$HERE/dlls/wined3d-patched.dll" "$LIBS/wined3d.dll"

# --- launcher -------------------------------------------------------------

cp "$HERE/launcher.sh" "$APP/Contents/MacOS/launcher"
chmod +x "$APP/Contents/MacOS/launcher"

# --- Info.plist -----------------------------------------------------------

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>launcher</string>
    <key>CFBundleIdentifier</key><string>org.winehq.sims-on-mac</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

info "Built $APP"
print
print "Not signed: on another Mac Gatekeeper will block it until you sign the bundle,"
print "or the user right-clicks it and chooses Open."
