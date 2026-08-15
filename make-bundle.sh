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

cat > "$APP/Contents/MacOS/launcher" <<'LAUNCHER'
#!/bin/zsh
# Self-contained launcher: own Wine, own prefix, user's own game.
BUNDLE="${0:A:h:h}"
WINE="$BUNDLE/Resources/wine/bin/wine"
export WINEPREFIX="$HOME/Library/Application Support/SimsOnMac/prefix"
export WINEDEBUG=-all
export MVK_CONFIG_LOG_LEVEL=0
export WINE_D3D_CONFIG="renderer=gl"   # required: MoltenVK cannot present 16-bit

ask() { osascript -e "display dialog \"$1\" buttons {\"OK\"} default button 1" >/dev/null 2>&1; }
pick_folder() {
    osascript -e "POSIX path of (choose folder with prompt \"$1\")" 2>/dev/null
}

# First run: create the prefix and configure it.
if [[ ! -d "$WINEPREFIX" ]]; then
    ask "Setting up Wine. This happens once and takes a minute."
    mkdir -p "$WINEPREFIX"
    "$BUNDLE/Resources/wine/bin/wineboot" -u >/dev/null 2>&1
    # Windows XP suits a 2003 game; and let macOS move the game window.
    "$WINE" reg add 'HKCU\Software\Wine\AppDefaults\Sims.exe' /v Version /t REG_SZ /d winxp /f >/dev/null 2>&1
    "$WINE" reg add 'HKCU\Software\Wine\AppDefaults\Sims.exe\Mac Driver' \
        /v AllowImmovableWindows /t REG_SZ /d N /f >/dev/null 2>&1
fi

# Locate the game inside the prefix.
GAME=$(find "$WINEPREFIX/drive_c" -maxdepth 3 -iname 'Sims.exe' 2>/dev/null | head -1)

if [[ -z "$GAME" ]]; then
    ask "The game is not installed yet.

Choose the folder with your Sims installer (the one containing setup.exe), or a folder with an already installed copy of the game."
    SRC=$(pick_folder "Folder with the game or its installer")
    [[ -z "$SRC" ]] && exit 0

    SETUP=$(find "$SRC" -maxdepth 2 -iname 'setup.exe' 2>/dev/null | head -1)
    EXISTING=$(find "$SRC" -maxdepth 2 -iname 'Sims.exe' 2>/dev/null | head -1)

    if [[ -n "$SETUP" ]]; then
        # Russian and other localised releases need a matching locale to show text correctly.
        LANG=ru_RU.UTF-8 LC_ALL=ru_RU.UTF-8 "$WINE" "$SETUP"
    elif [[ -n "$EXISTING" ]]; then
        ask "Copying the game into the bundle's prefix."
        mkdir -p "$WINEPREFIX/drive_c/Program Files (x86)"
        cp -R "${EXISTING:h}" "$WINEPREFIX/drive_c/Program Files (x86)/"
    else
        ask "No setup.exe or Sims.exe found in that folder."
        exit 1
    fi
    GAME=$(find "$WINEPREFIX/drive_c" -maxdepth 3 -iname 'Sims.exe' 2>/dev/null | head -1)
    [[ -z "$GAME" ]] && { ask "Installation did not complete."; exit 1; }
fi

cd "${GAME:h}"
exec "$WINE" "$GAME"
LAUNCHER
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
