#!/bin/zsh
# Self-contained launcher: own Wine, own prefix, user's own game.
BUNDLE="${0:A:h:h}"
WINE="$BUNDLE/Resources/wine/bin/wine"
export WINEPREFIX="$HOME/Library/Application Support/SimsOnMac/prefix"
# Localised releases store their text in the local codepage; without a matching
# locale every dialog comes out as mojibake.
export LANG="${SIMS_LANG:-ru_RU.UTF-8}"
export LC_ALL="$LANG"
export WINEDEBUG=-all
export MVK_CONFIG_LOG_LEVEL=0
export WINE_D3D_CONFIG="renderer=gl"   # required: MoltenVK cannot present 16-bit

ask() { osascript -e "display dialog \"$1\" buttons {\"OK\"} default button 1" >/dev/null 2>&1; }
pick_folder() {
    osascript -e "POSIX path of (choose folder with prompt \"$1\")" 2>/dev/null
}

# First run: create the prefix.
if [[ ! -d "$WINEPREFIX" ]]; then
    ask "Setting up Wine. This happens once and takes a minute."
    mkdir -p "$WINEPREFIX"
    "$BUNDLE/Resources/wine/bin/wineboot" -u >/dev/null 2>&1
    # Windows XP suits a game from 2003.
    "$WINE" reg add 'HKCU\Software\Wine\AppDefaults\Sims.exe' \
        /v Version /t REG_SZ /d winxp /f >/dev/null 2>&1
fi

# Locate the game inside the prefix.
GAME=$(find "$WINEPREFIX/drive_c" -maxdepth 3 -iname 'Sims.exe' 2>/dev/null | head -1)

if [[ -z "$GAME" ]]; then
    ask "The game is not installed yet.

Choose the folder with your Sims installer (the one containing setup.exe), or a folder with an already installed copy of the game."
    SRC=$(pick_folder "Folder with the game or its installer")
    [[ -z "$SRC" ]] && exit 0
    SRC="${SRC%/}"

    SETUP=$(find "$SRC" -maxdepth 2 -iname 'setup.exe' 2>/dev/null | head -1)
    EXISTING=$(find "$SRC" -maxdepth 2 -iname 'Sims.exe' 2>/dev/null | head -1)

    if [[ -n "$SETUP" ]]; then
        # Localised releases need a matching locale for the installer text.
        "$WINE" "$SETUP"
    elif [[ -n "$EXISTING" ]]; then
        ask "Copying the game. This may take a few minutes."
        GAME_DIR="${EXISTING:h}"
        mkdir -p "$WINEPREFIX/drive_c/Program Files (x86)"
        cp -R "$GAME_DIR" "$WINEPREFIX/drive_c/Program Files (x86)/"

        # Copying the files is not enough: the game reads its install path,
        # expansion flags and serial numbers from the registry. The game keeps
        # the same folder name here, so the stored paths stay valid and the
        # registry blocks can be carried over verbatim — no escaping games.
        SRC_PREFIX="${GAME_DIR%%/drive_c/*}"
        if [[ -f "$SRC_PREFIX/system.reg" ]]; then
            "$BUNDLE/Resources/wine/bin/wineserver" -k 2>/dev/null
            sleep 1
            awk '/^\[/ { keep = ($0 ~ /Maxis/) } keep' "$SRC_PREFIX/system.reg" \
                >> "$WINEPREFIX/system.reg"
        fi
    else
        ask "No setup.exe or Sims.exe was found in that folder."
        exit 1
    fi

    GAME=$(find "$WINEPREFIX/drive_c" -maxdepth 3 -iname 'Sims.exe' 2>/dev/null | head -1)
    [[ -z "$GAME" ]] && { ask "Installation did not complete."; exit 1; }
fi

cd "${GAME:h}"
exec "$WINE" "$GAME"
