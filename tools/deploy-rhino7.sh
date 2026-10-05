#!/usr/bin/env bash
# deploy-rhino7.sh - Prepare and configure a Wine prefix for Rhinoceros 7.
#
# What it does:
#   1. Creates a 64-bit Wine prefix and reports Windows 10.
#   2. Installs the real .NET Framework 4.8 (Rhino 7 refuses to run on Wine Mono).
#   3. Installs core fonts and registers font names and substitutes.
#   4. Applies DLL overrides and the X11 graphics driver setting.
#   5. Optionally deploys DXVK (Direct3D only; Rhino's viewports use OpenGL).
#   6. Installs the rhino-7 launcher, a desktop entry and an extracted icon.
#   7. Saves the resolved paths to ~/.config/rhino7-linux/config.
#   8. Optionally writes a COSMIC auto-tiling exception for Rhino windows.
#
# Usage:
#   ./deploy-rhino7.sh [OPTIONS]
#
# Options:
#   --prefix <PATH>     Target Wine prefix (default: $RHINO_PREFIX or ~/.wine-rhino7)
#   --wine <PATH>       Wine binary (default: $WINE or system wine)
#   --skip-dotnet       Do not touch .NET Framework / fonts via winetricks
#   --extras            Also install vcrun2019, msxml6 and gdiplus via winetricks
#   --dxvk              Deploy DXVK DLLs into the prefix (optional, off by default)
#   --dxvk-dir <PATH>   Directory holding 64-bit DXVK DLLs
#   --cosmic-rules      Write a COSMIC auto-tiling exception for Rhino
#   --skip-desktop      Skip the desktop entry and icon
#   -h, --help          Show this help
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

TARGET_PREFIX="${RHINO_PREFIX:-${WINEPREFIX:-}}"
[ -n "$TARGET_PREFIX" ] || TARGET_PREFIX="$HOME/.wine-rhino7"

WINE_BIN="${WINE:-}"
SKIP_DOTNET=0
INSTALL_EXTRAS=0
ENABLE_DXVK=0
CUSTOM_DXVK_DIR=""
COSMIC_RULES=0
PIN_DOCK=0
SKIP_DESKTOP=0

# Upper bound for the dotnet48 step. It normally needs 15 to 40 minutes; the
# limit only exists so a genuinely stuck installer cannot block the run forever.
DOTNET_TIMEOUT_MIN="${RHINO_DOTNET_TIMEOUT_MIN:-45}"

# Core fonts are small; a long run here means a stalled download mirror.
FONTS_TIMEOUT_MIN="${RHINO_FONTS_TIMEOUT_MIN:-10}"

print_help() {
    cat << 'EOF'
deploy-rhino7.sh - Prepare and configure a Wine prefix for Rhinoceros 7.

Usage:
  ./deploy-rhino7.sh [OPTIONS]

Options:
  --prefix <PATH>     Target Wine prefix (default: $RHINO_PREFIX or ~/.wine-rhino7)
  --wine <PATH>       Wine binary (default: $WINE or system wine)
  --skip-dotnet       Do not touch .NET Framework / fonts via winetricks
  --extras            Also install vcrun2019, msxml6 and gdiplus via winetricks
  --dxvk              Deploy DXVK DLLs into the prefix (optional, off by default)
  --dxvk-dir <PATH>   Directory holding 64-bit DXVK DLLs
  --cosmic-rules      Write a COSMIC auto-tiling exception for Rhino
  --pin-dock          Pin Rhino to the COSMIC dock
  --skip-desktop      Skip the desktop entry and icon
  -h, --help          Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix) TARGET_PREFIX="$2"; shift 2 ;;
        --wine) WINE_BIN="$2"; shift 2 ;;
        --skip-dotnet) SKIP_DOTNET=1; shift ;;
        --extras) INSTALL_EXTRAS=1; shift ;;
        --dxvk) ENABLE_DXVK=1; shift ;;
        --dxvk-dir) CUSTOM_DXVK_DIR="$2"; ENABLE_DXVK=1; shift 2 ;;
        --cosmic-rules) COSMIC_RULES=1; shift ;;
        --pin-dock) PIN_DOCK=1; shift ;;
        --skip-desktop) SKIP_DESKTOP=1; shift ;;
        -h|--help) print_help; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [ -z "$WINE_BIN" ]; then
    for candidate in \
        "$HOME/.local/share/wine-rhino7/bin/wine" \
        "/opt/wine-rhino7/bin/wine" \
        "$REPO_DIR/build-wine/wine"; do
        if [ -x "$candidate" ]; then
            WINE_BIN="$candidate"
            break
        fi
    done
fi
if [ -z "$WINE_BIN" ]; then
    if command -v wine >/dev/null 2>&1; then
        WINE_BIN="$(command -v wine)"
    else
        echo "Error: no Wine binary found. Pass --wine /path/to/wine." >&2
        exit 1
    fi
fi

WINESERVER_BIN=""
for candidate in \
    "$(dirname "$WINE_BIN")/wineserver" \
    "$(dirname "$WINE_BIN")/server/wineserver" \
    "$(dirname "$WINE_BIN")/../server/wineserver"; do
    if [ -x "$candidate" ]; then
        WINESERVER_BIN="$candidate"
        break
    fi
done
[ -n "$WINESERVER_BIN" ] || WINESERVER_BIN="$(command -v wineserver 2>/dev/null || echo wineserver)"

echo "=========================================================="
echo " Rhino 7 prefix setup"
echo "=========================================================="
echo "Prefix: $TARGET_PREFIX"
echo "Wine  : $WINE_BIN ($("$WINE_BIN" --version 2>/dev/null || echo 'version unknown'))"
echo "=========================================================="

export WINEPREFIX="$TARGET_PREFIX"
export WINEARCH="win64"
export WINEDEBUG="${WINEDEBUG:--all}"

wait_wineserver() {
    timeout 30 "$WINESERVER_BIN" -w 2>/dev/null || true
}

verify_sha256() {
    local expected="$1" file="$2"
    if command -v sha256sum >/dev/null 2>&1; then
        echo "$expected  $file" | sha256sum -c --status 2>/dev/null
    elif command -v shasum >/dev/null 2>&1; then
        echo "$expected  $file" | shasum -a 256 -c --status 2>/dev/null
    else
        return 0
    fi
}

# ------------------------------------------------------------------------------
# 1. Prefix initialisation
# ------------------------------------------------------------------------------
if [ ! -d "$TARGET_PREFIX/drive_c" ]; then
    echo "[1/8] Creating a fresh 64-bit Wine prefix..."
    "$WINE_BIN" wineboot -u
    wait_wineserver
else
    echo "[1/8] Existing prefix detected."
fi

# ------------------------------------------------------------------------------
# 2. .NET Framework 4.8
# ------------------------------------------------------------------------------
# Rhino 7 targets .NET Framework 4.8. Wine Mono cannot run RhinoCommon, the
# Rhino UI (Eto/WPF) or Grasshopper, and the Rhino installer aborts with
# rhino.msi:-2147023293 when mscoree does not resolve to a real framework.
CLR_PATH="$TARGET_PREFIX/drive_c/windows/Microsoft.NET/Framework64/v4.0.30319/clr.dll"
if [ "$SKIP_DOTNET" -eq 1 ]; then
    echo "[2/8] Skipping .NET Framework handling (--skip-dotnet)."
elif [ -f "$CLR_PATH" ]; then
    echo "[2/8] .NET Framework 4.x already present in the prefix."
elif ! command -v winetricks >/dev/null 2>&1; then
    echo "[2/8] WARNING: winetricks not found; cannot install .NET Framework 4.8."
    echo "      Install it (Fedora: sudo dnf install winetricks cabextract) and rerun,"
    echo "      otherwise Rhino 7 will not start."
else
    echo "[2/8] Installing .NET Framework 4.8 via winetricks."
    echo "      This is the slow step: 15 to 40 minutes, and the longest stretch"
    echo "      (ndp48-x86-x64-allos-enu.exe) prints nothing at all while it works."
    echo "      Progress is reported here every minute. Hard limit: ${DOTNET_TIMEOUT_MIN} minutes."

    # winetricks drives its own windows version and DLL overrides during the
    # dotnet48 verb, so the ambient overrides are cleared for this call.
    env -u WINEDLLOVERRIDES WINE="$WINE_BIN" WINEPREFIX="$TARGET_PREFIX" \
        timeout "${DOTNET_TIMEOUT_MIN}m" winetricks -q -f dotnet48 &
    dotnet_pid=$!

    # Heartbeat, so a silent installer is not mistaken for a hung one.
    elapsed=0
    while kill -0 "$dotnet_pid" 2>/dev/null; do
        sleep 60
        elapsed=$((elapsed + 1))
        if [ -f "$CLR_PATH" ]; then
            echo "      ... ${elapsed} min, clr.dll is in place, finishing up"
        else
            echo "      ... ${elapsed} min, still installing"
        fi
    done
    wait "$dotnet_pid" && dotnet_rc=0 || dotnet_rc=$?

    if [ "$dotnet_rc" -eq 124 ]; then
        echo "      [WARN] winetricks hit the ${DOTNET_TIMEOUT_MIN} minute limit and was stopped." >&2
    elif [ "$dotnet_rc" -ne 0 ]; then
        echo "      [WARN] winetricks exited with code $dotnet_rc." >&2
    fi

    # The .NET setup leaves the NGen service running, and it regularly never
    # exits under Wine. That is what makes the install look stuck at the end,
    # so these are cleaned up unconditionally.
    pkill -u "$(id -u)" -f 'mscorsvw' 2>/dev/null || true
    pkill -u "$(id -u)" -f 'ngen\.exe' 2>/dev/null || true
    "$WINESERVER_BIN" -k 2>/dev/null || true
    wait_wineserver

    if [ -f "$CLR_PATH" ]; then
        echo "      [PASS] .NET Framework 4.8 installed."
    else
        echo "      [FAIL] clr.dll is missing, so Rhino 7 will not start." >&2
        echo "      Start over with a clean prefix:" >&2
        echo "        rm -rf '$TARGET_PREFIX' && ./install.sh" >&2
        echo "      See docs/troubleshooting.md, section '.NET Framework 4.8'." >&2
    fi
fi

if [ "$SKIP_DOTNET" -eq 0 ] && command -v winetricks >/dev/null 2>&1; then
    # A dozen small archives from SourceForge, normally well under a minute.
    # Output is kept visible because a dead mirror is the only thing that makes
    # this slow, and then you want to see which file it is stuck on.
    echo "      Installing core fonts, roughly 15 MB (missing fonts are the most"
    echo "      common reason Rhino 7 dies on Wine)..."
    env -u WINEDLLOVERRIDES WINE="$WINE_BIN" WINEPREFIX="$TARGET_PREFIX" \
        timeout "${FONTS_TIMEOUT_MIN}m" winetricks -q corefonts || {
            rc=$?
            if [ "$rc" -eq 124 ]; then
                echo "      [WARN] corefonts hit the ${FONTS_TIMEOUT_MIN} minute limit, probably a stalled mirror." >&2
            else
                echo "      [WARN] corefonts exited with code $rc." >&2
            fi
            echo "      Continuing; the Arial fallback below covers the font Rhino needs most." >&2
        }
fi

if [ "$INSTALL_EXTRAS" -eq 1 ] && command -v winetricks >/dev/null 2>&1; then
    echo "      Installing extras: vcrun2019 msxml6 gdiplus..."
    env -u WINEDLLOVERRIDES WINE="$WINE_BIN" WINEPREFIX="$TARGET_PREFIX" \
        winetricks -q vcrun2019 msxml6 gdiplus || true
    "$WINESERVER_BIN" -k 2>/dev/null || true
    wait_wineserver
fi

# Rhino 7 requires Windows 10 as the reported version.
"$WINE_BIN" winecfg -v win10 >/dev/null 2>&1 || true

# ------------------------------------------------------------------------------
# 3. Registry: DLL overrides, graphics driver, Windows build
# ------------------------------------------------------------------------------
echo "[3/8] Applying DLL overrides and driver settings..."
REG_FILE="$(mktemp "${TMPDIR:-/tmp}/rhino7-deploy-XXXXXX.reg")"
cat > "$REG_FILE" << 'REG_EOF'
Windows Registry Editor Version 5.00

; Global overrides
[HKEY_CURRENT_USER\Software\Wine\DllOverrides]
; Wine's OpenMP, with the 64-bit dynamic loop scheduling patch, is what Rhino's
; geometry kernel needs; the redistributable vcomp140 misbehaves under Wine.
"vcomp140"="builtin"
; The real .NET Framework 4.8 installed above, not Wine Mono.
"mscoree"="native"
GDIPLUS_GLOBAL

[HKEY_CURRENT_USER\Software\Wine\AppDefaults\Rhino.exe\DllOverrides]
"vcomp140"="builtin"
"mscoree"="native"
GDIPLUS_APP
"d3dcompiler_47"="native,builtin"

; Force the X11 driver. Rhino's floating toolbars, MDI viewports and owner drawn
; popups rely on behaviour winewayland.drv does not implement yet, so run the
; application through XWayland on COSMIC and other Wayland sessions.
[HKEY_CURRENT_USER\Software\Wine\Drivers]
"Graphics"="x11"

; Rhino 7 checks for Windows 10.
[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion]
"CurrentBuild"="19045"
"CurrentBuildNumber"="19045"
"ProductName"="Windows 10 Pro"
REG_EOF
# gdiplus is only safe as "native" when a native DLL actually exists in the
# prefix. Forcing native without one makes Wine refuse the builtin fallback, and
# the Rhino installer dies with "gdiplus.dll not found" (exit code 126). The
# "=-" form also removes a bad override left by an earlier run.
if [ -f "$TARGET_PREFIX/drive_c/windows/system32/gdiplus.dll" ]; then
    gdiplus_line='"gdiplus"="native,builtin"'
else
    gdiplus_line='"gdiplus"=-'
fi
sed -i "s|^GDIPLUS_GLOBAL$|$gdiplus_line|; s|^GDIPLUS_APP$|$gdiplus_line|" "$REG_FILE"

"$WINE_BIN" regedit /S "$REG_FILE"
rm -f "$REG_FILE"

for reg in windows-fonts.reg font-substitutes.reg; do
    if [ -f "$SCRIPT_DIR/$reg" ]; then
        echo "      Importing $reg..."
        "$WINE_BIN" regedit /S "$SCRIPT_DIR/$reg"
    fi
done
wait_wineserver

# ------------------------------------------------------------------------------
# 4. Fonts
# ------------------------------------------------------------------------------
echo "[4/8] Resolving fonts..."
FONTS_DIR="$TARGET_PREFIX/drive_c/windows/Fonts"
mkdir -p "$FONTS_DIR"

if [ ! -f "$FONTS_DIR/arial.ttf" ]; then
    echo "      Looking for Arial on the system and on mounted Windows volumes..."
    for candidate_dir in \
        "/usr/share/fonts/truetype/msttcorefonts" \
        "/usr/share/fonts/msttcorefonts" \
        "/usr/share/fonts/TTF" \
        "/usr/share/fonts/truetype" \
        "/usr/share/fonts" \
        "/usr/local/share/fonts" \
        "$HOME/.local/share/fonts" \
        "$HOME/.fonts" \
        /run/media/*/*/Windows/Fonts \
        /run/media/*/*/windows/fonts \
        /mnt/*/Windows/Fonts \
        /media/*/*/Windows/Fonts; do
        [ -d "$candidate_dir" ] || continue
        found=()
        while IFS= read -r -d '' match; do
            found+=("$match")
        done < <(find "$candidate_dir" -maxdepth 2 -iname "arial*.ttf" -print0 2>/dev/null)
        if [ "${#found[@]}" -gt 0 ]; then
            for font in "${found[@]}"; do
                cp -f "$font" "$FONTS_DIR/$(basename "$font" | tr '[:upper:]' '[:lower:]')"
            done
            [ -f "$FONTS_DIR/arial.ttf" ] && { echo "      Copied Arial from $candidate_dir"; break; }
        fi
    done
fi

if [ ! -f "$FONTS_DIR/arial.ttf" ]; then
    echo "      Fetching the Microsoft core fonts package (arial32.exe)..."
    FONT_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/rhino7-linux/fonts"
    mkdir -p "$FONT_CACHE_DIR"
    ARIAL_EXE="$FONT_CACHE_DIR/arial32.exe"
    ARIAL_SHA256="85297a4d146e9c87ac6f74822734bdee5f4b2a722d7eaa584b7f2cbf76f478f6"

    for cached in \
        "$ARIAL_EXE" \
        "${XDG_CACHE_HOME:-$HOME/.cache}/winetricks/corefonts/arial32.exe"; do
        if [ -f "$cached" ] && verify_sha256 "$ARIAL_SHA256" "$cached"; then
            cp -f "$cached" "$ARIAL_EXE"
            break
        fi
    done

    if [ ! -f "$ARIAL_EXE" ] || ! verify_sha256 "$ARIAL_SHA256" "$ARIAL_EXE"; then
        temp_dl="$ARIAL_EXE.part.$$"
        for url in \
            "https://github.com/pushcx/corefonts/raw/master/arial32.exe" \
            "https://downloads.sourceforge.net/corefonts/arial32.exe"; do
            if command -v curl >/dev/null 2>&1; then
                curl -fLs -o "$temp_dl" "$url" || true
            elif command -v wget >/dev/null 2>&1; then
                wget -q -O "$temp_dl" "$url" || true
            fi
            if [ -f "$temp_dl" ] && verify_sha256 "$ARIAL_SHA256" "$temp_dl"; then
                mv -f "$temp_dl" "$ARIAL_EXE"
                break
            fi
            rm -f "$temp_dl"
        done
    fi

    if [ -f "$ARIAL_EXE" ] && verify_sha256 "$ARIAL_SHA256" "$ARIAL_EXE"; then
        temp_extract="$(mktemp -d)"
        if command -v cabextract >/dev/null 2>&1; then
            cabextract -q -d "$temp_extract" "$ARIAL_EXE" 2>/dev/null || true
        elif command -v bsdtar >/dev/null 2>&1; then
            bsdtar -xf "$ARIAL_EXE" -C "$temp_extract" 2>/dev/null || true
        elif command -v 7z >/dev/null 2>&1; then
            7z x -y -o"$temp_extract" "$ARIAL_EXE" >/dev/null 2>&1 || true
        fi
        for font in "$temp_extract"/*.[tT][tT][fF]; do
            [ -f "$font" ] && cp -f "$font" "$FONTS_DIR/$(basename "$font" | tr '[:upper:]' '[:lower:]')"
        done
        rm -rf "$temp_extract"
    fi
fi

if [ -f "$FONTS_DIR/arial.ttf" ]; then
    echo "      [PASS] Arial present."
else
    echo "      [WARN] Arial missing. Rhino 7 and Grasshopper may fail to draw text."
fi

# Rhino ships annotation fonts next to its binaries; make them visible to GDI.
RHINO_SYS_DIR=""
for candidate in \
    "$TARGET_PREFIX/drive_c/Program Files/Rhino 7/System" \
    "$TARGET_PREFIX/drive_c/Program Files/Rhino 7 WIP/System"; do
    [ -d "$candidate" ] && { RHINO_SYS_DIR="$candidate"; break; }
done
if [ -n "$RHINO_SYS_DIR" ]; then
    for font in "$RHINO_SYS_DIR"/*.ttf; do
        [ -f "$font" ] && cp -u "$font" "$FONTS_DIR/" 2>/dev/null || true
    done
fi

# ------------------------------------------------------------------------------
# 5. Optional DXVK
# ------------------------------------------------------------------------------
SYSTEM32_DIR="$TARGET_PREFIX/drive_c/windows/system32"
if [ "$ENABLE_DXVK" -eq 0 ]; then
    echo "[5/8] Skipping DXVK. Rhino 7 renders its viewports with OpenGL; pass --dxvk"
    echo "      only if a plugin or dialog needs Direct3D acceleration."
else
    echo "[5/8] Deploying DXVK 64-bit libraries..."
    mkdir -p "$SYSTEM32_DIR"
    DXVK_DEPLOYED=0

    deploy_dxvk_from_dir() {
        local src_dir="$1" dll
        [ -d "$src_dir" ] || return 1
        # Fedora's wine-dxvk ships dxvk prefixed names in the wine library dir.
        if [ -f "$src_dir/dxvk-d3d11.dll" ]; then
            for dll in d3d11 dxgi d3d9 d3d10core; do
                [ -f "$src_dir/dxvk-$dll.dll" ] && cp -f "$src_dir/dxvk-$dll.dll" "$SYSTEM32_DIR/$dll.dll"
            done
            echo "      Copied DXVK (Fedora layout) from $src_dir"
            return 0
        fi
        if [ -f "$src_dir/d3d11.dll" ]; then
            for dll in d3d11.dll dxgi.dll d3d9.dll d3d10core.dll; do
                [ -f "$src_dir/$dll" ] && cp -f "$src_dir/$dll" "$SYSTEM32_DIR/$dll"
            done
            echo "      Copied DXVK from $src_dir"
            return 0
        fi
        return 1
    }

    if [ -n "$CUSTOM_DXVK_DIR" ] && deploy_dxvk_from_dir "$CUSTOM_DXVK_DIR"; then
        DXVK_DEPLOYED=1
    fi
    if [ "$DXVK_DEPLOYED" -eq 0 ]; then
        for candidate in \
            "/usr/lib64/wine/x86_64-windows" \
            "/usr/lib/wine/x86_64-windows" \
            "/usr/lib64/wine/dxvk/x86_64-windows" \
            "/usr/lib/dxvk/x64" \
            "/usr/share/dxvk/x64" \
            "/usr/lib64/dxvk"; do
            if deploy_dxvk_from_dir "$candidate"; then
                DXVK_DEPLOYED=1
                break
            fi
        done
    fi
    if [ "$DXVK_DEPLOYED" -eq 0 ]; then
        echo "      Fetching the pinned DXVK 2.4 release..."
        DXVK_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/rhino7-linux"
        DXVK_TARBALL="$DXVK_CACHE_DIR/dxvk-2.4.tar.gz"
        DXVK_URL="https://github.com/doitsujin/dxvk/releases/download/v2.4/dxvk-2.4.tar.gz"
        DXVK_SHA256="784eb023fb8da8868aa562c30ef5562989211fc9fda6bc5155d95e28049fccc7"
        mkdir -p "$DXVK_CACHE_DIR"
        if [ ! -f "$DXVK_TARBALL" ] || ! verify_sha256 "$DXVK_SHA256" "$DXVK_TARBALL"; then
            temp_dl="$DXVK_TARBALL.part.$$"
            if command -v curl >/dev/null 2>&1; then
                curl -fL -o "$temp_dl" "$DXVK_URL" || true
            elif command -v wget >/dev/null 2>&1; then
                wget -O "$temp_dl" "$DXVK_URL" || true
            fi
            if [ -f "$temp_dl" ] && verify_sha256 "$DXVK_SHA256" "$temp_dl"; then
                mv -f "$temp_dl" "$DXVK_TARBALL"
            else
                echo "      WARNING: DXVK download or checksum failed." >&2
                rm -f "$temp_dl"
            fi
        fi
        if [ -f "$DXVK_TARBALL" ]; then
            temp_extract="$(mktemp -d)"
            tar -xzf "$DXVK_TARBALL" -C "$temp_extract"
            deploy_dxvk_from_dir "$temp_extract/dxvk-2.4/x64" && DXVK_DEPLOYED=1
            rm -rf "$temp_extract"
        fi
    fi

    if [ "$DXVK_DEPLOYED" -eq 1 ]; then
        REG_FILE="$(mktemp "${TMPDIR:-/tmp}/rhino7-dxvk-XXXXXX.reg")"
        cat > "$REG_FILE" << 'REG_EOF'
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\Software\Wine\AppDefaults\Rhino.exe\DllOverrides]
"d3d11"="native"
"dxgi"="native"
"d3d10core"="native"
"d3d9"="native"
REG_EOF
        "$WINE_BIN" regedit /S "$REG_FILE"
        rm -f "$REG_FILE"
        echo "      [PASS] DXVK deployed and registered for Rhino.exe."
    else
        echo "      [WARN] DXVK could not be deployed; Direct3D falls back to WineD3D."
    fi
fi

# ------------------------------------------------------------------------------
# 6. Companion assets and saved configuration
# ------------------------------------------------------------------------------
echo "[6/8] Installing companion assets and saving configuration..."
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/rhino7-linux"
mkdir -p "$DATA_DIR"
for asset in dxvk-rhino7.conf windows-fonts.reg font-substitutes.reg; do
    [ -f "$SCRIPT_DIR/$asset" ] && cp -f "$SCRIPT_DIR/$asset" "$DATA_DIR/$asset"
done

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/rhino7-linux"
mkdir -p "$CONFIG_DIR"
cat > "$CONFIG_DIR/config" << EOF
# Rhino 7 on Linux - generated by deploy-rhino7.sh on $(date -Iseconds)
RHINO_PREFIX="$TARGET_PREFIX"
RHINO_WINE="$WINE_BIN"
RHINO_WINESERVER="$WINESERVER_BIN"
EOF

# ------------------------------------------------------------------------------
# 7. Launcher and desktop integration
# ------------------------------------------------------------------------------
echo "[7/8] Installing the launcher..."
BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"
install -m 0755 "$SCRIPT_DIR/rhino-7" "$BIN_DIR/rhino-7"
case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) echo "      NOTE: $BIN_DIR is not in your PATH." ;;
esac

if [ "$SKIP_DESKTOP" -eq 0 ]; then
    ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"
    APPS_DIR="$HOME/.local/share/applications"
    mkdir -p "$ICON_DIR" "$APPS_DIR"

    # Use Rhino's own icon when icoutils is available, otherwise fall back to a
    # generic theme icon. No McNeel artwork is shipped in this repository.
    ICON_NAME="applications-graphics"
    if [ -n "$RHINO_SYS_DIR" ] && command -v wrestool >/dev/null 2>&1 && command -v icotool >/dev/null 2>&1; then
        tmp_icon="$(mktemp -d)"
        if wrestool -x -t 14 -o "$tmp_icon" "$RHINO_SYS_DIR/Rhino.exe" >/dev/null 2>&1; then
            icotool -x -w 256 -o "$tmp_icon" "$tmp_icon"/*.ico >/dev/null 2>&1 || \
                icotool -x -o "$tmp_icon" "$tmp_icon"/*.ico >/dev/null 2>&1 || true
            extracted="$(find "$tmp_icon" -name '*.png' | sort | tail -n1)"
            if [ -n "$extracted" ]; then
                cp -f "$extracted" "$ICON_DIR/rhino7.png"
                ICON_NAME="rhino7"
                echo "      Extracted the application icon from Rhino.exe."
            fi
        fi
        rm -rf "$tmp_icon"
    fi

    cat > "$APPS_DIR/rhino-7.desktop" << EOF
[Desktop Entry]
Name=Rhinoceros 7
GenericName=3D CAD Modeler
Comment=Model and document with Rhinoceros 7 under Wine
Exec=$BIN_DIR/rhino-7 %F
Icon=$ICON_NAME
Terminal=false
Type=Application
Categories=Graphics;3DGraphics;Engineering;
MimeType=application/x-3dm;
StartupWMClass=rhino.exe
StartupNotify=true
EOF
    command -v update-desktop-database >/dev/null 2>&1 && \
        update-desktop-database "$APPS_DIR" 2>/dev/null || true
    echo "      Desktop entry installed."

    # COSMIC dock: favourites are a plain RON list of desktop entry ids under
    # com.system76.CosmicAppList, and the panel picks changes up on save.
    if [ "$PIN_DOCK" -eq 1 ]; then
        dock_file="$HOME/.config/cosmic/com.system76.CosmicAppList/v1/favorites"
        if [ ! -f "$dock_file" ]; then
            mkdir -p "$(dirname "$dock_file")"
            printf '[\n    "rhino-7",\n]\n' > "$dock_file"
            echo "      Pinned to the COSMIC dock."
        elif grep -q '"rhino-7"' "$dock_file"; then
            echo "      Already pinned to the COSMIC dock."
        else
            cp -f "$dock_file" "$dock_file.bak"
            # Insert before the closing bracket of the list.
            sed -i '0,/^\s*\]\s*$/s//    "rhino-7",\n]/' "$dock_file"
            if grep -q '"rhino-7"' "$dock_file"; then
                echo "      Pinned to the COSMIC dock (previous list saved as favorites.bak)."
            else
                mv -f "$dock_file.bak" "$dock_file"
                echo "      [WARN] Could not edit $dock_file; pin it by hand instead."
            fi
        fi
    fi
else
    echo "      Desktop integration skipped."
fi

# ------------------------------------------------------------------------------
# 8. COSMIC auto-tiling exception
# ------------------------------------------------------------------------------
COSMIC_RULES_FILE="$HOME/.config/cosmic/com.system76.CosmicSettings.WindowRules/v1/tiling_exception_custom"
COSMIC_SNIPPET='[
  (
    enabled: true,
    appid: "rhino.exe",
    title: "",
  ),
]'
if [ "$COSMIC_RULES" -eq 1 ]; then
    echo "[8/8] Writing the COSMIC auto-tiling exception..."
    if [ -f "$COSMIC_RULES_FILE" ]; then
        if grep -q 'rhino\.exe' "$COSMIC_RULES_FILE"; then
            echo "      Rule for rhino.exe already present; left untouched."
        else
            echo "      $COSMIC_RULES_FILE already exists and is not modified automatically."
            echo "      Add this entry to the existing list yourself:"
            echo "        (enabled: true, appid: \"rhino.exe\", title: \"\"),"
        fi
    else
        mkdir -p "$(dirname "$COSMIC_RULES_FILE")"
        printf '%s\n' "$COSMIC_SNIPPET" > "$COSMIC_RULES_FILE"
        echo "      Written. COSMIC picks the file up on save, no logout needed."
    fi
elif [ "${XDG_CURRENT_DESKTOP:-}" = "COSMIC" ] || [ "${XDG_CURRENT_DESKTOP:-}" = "cosmic" ]; then
    echo "[8/8] COSMIC session detected. If a workspace uses auto-tiling, run this"
    echo "      script again with --cosmic-rules, or see docs/cosmic.md."
else
    echo "[8/8] No window manager rules applied."
fi

echo "=========================================================="
echo " Done. Launch Rhino with: rhino-7"
echo "=========================================================="
