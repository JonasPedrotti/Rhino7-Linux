#!/usr/bin/env bash
# ==============================================================================
# Rhinoceros 7 on Linux - installer and environment configurator
# ==============================================================================
# Primary targets: Fedora Workstation (incl. the COSMIC spin) and Pop!_OS COSMIC.
# Also handles Arch, Debian/Ubuntu and openSUSE package names.
#
# Usage:
#   ./install.sh [OPTIONS]
#
# Options:
#   -y, --yes               Non-interactive (accept defaults)
#   --deps                  Install the runtime packages (build packages come with --build-wine)
#   --check                 Run environment diagnostics only and exit
#   --prefix <PATH>         Wine prefix (default: ~/.wine-rhino7)
#   --wine <PATH>           Use this Wine binary
#   --build-wine            Build the patched Wine 11.18 from source
#   --wine-src <DIR>        Reuse an existing Wine source tree (implies --build-wine)
#   --wine-install <DIR>    Install the built Wine here (default: ~/.local/share/wine-rhino7)
#   --patches <SET>         all (default) or core; see docs/patches.md
#   --wayland               Also apply the experimental Wayland driver patch (16)
#   --skip-dotnet           Do not install .NET Framework 4.8 / fonts
#   --extras                Also install msxml6 and gdiplus
#   --dxvk                  Deploy DXVK (optional, Direct3D only)
#   --dxvk-dir <PATH>       Directory with 64-bit DXVK DLLs
#   --cosmic-rules          Write a COSMIC auto-tiling exception for Rhino
  --pin-dock              Pin Rhino to the COSMIC dock
  --no-integration        No dock pin, no window rules, menu entry only
#   --installer <PATH>      Run this Rhino 7 installer .exe inside the prefix
#   --run                   Launch Rhino when finished
#   -h, --help              Show this help
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
REPO_DIR="$SCRIPT_DIR"

BOLD='\033[1m'; RED='\033[0;31m'; GREEN='\033[0;32m'
YELLOW='\033[0;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

NON_INTERACTIVE=0
INSTALL_DEPS=0
CHECK_ONLY=0
BUILD_WINE=0
WINE_SRC_DIR=""
WINE_INSTALL_DIR="$HOME/.local/share/wine-rhino7"
CUSTOM_WINE=""
PATCH_SET="all"
ENABLE_WAYLAND=0
SKIP_DOTNET=0
INSTALL_EXTRAS=0
ENABLE_DXVK=0
CUSTOM_DXVK_DIR=""
COSMIC_RULES=0
PIN_DOCK=0
NO_INTEGRATION=0
RHINO_INSTALLER=""
RUN_RHINO=0
WINE_VERSION="wine-11.18"

# Rhino 7.38.24338.17001 (SR38, 2024-12-03), the final Rhino 7 service release,
# from McNeel's own file server. Size and checksum verified on 2026-10-05.
RHINO_INSTALLER_URL="${RHINO_INSTALLER_URL:-https://files.mcneel.com/dujour/exe/20241203/rhino_en-us_7.38.24338.17001.exe}"
RHINO_INSTALLER_SHA256="d400fa02ad908d781e5f9864d960aeef2d0f3b5f86d9f42c24ba003435de7516"
RHINO_INSTALLER_SIZE="307454376"
NO_DOWNLOAD=0

TARGET_PREFIX="${RHINO_PREFIX:-${WINEPREFIX:-}}"
[ -n "$TARGET_PREFIX" ] || TARGET_PREFIX="$HOME/.wine-rhino7"

# Patch groups, see docs/patches.md. Numbers match the upstream rhino-linux set,
# so gaps (06, 07, 17) are intentional: those patches only serve Rhino 8/9.
CORE_PATCHES="01 02 03 04 05 08 09 10 12 14 17 19 20"
LICENSING_PATCHES="13 15"
D3D_PATCHES="11 18"
WAYLAND_PATCHES="16"

print_help() {
    cat << 'EOF'
Rhinoceros 7 on Linux - installer and environment configurator

Primary targets: Fedora Workstation (incl. the COSMIC spin) and Pop!_OS COSMIC.
Also handles Arch, Debian/Ubuntu and openSUSE package names.

Usage:
  ./install.sh [OPTIONS]

Options:
  -y, --yes               Non-interactive (accept defaults)
  --deps                  Install the runtime packages (build packages come with --build-wine)
  --check                 Run environment diagnostics only and exit
  --prefix <PATH>         Wine prefix (default: ~/.wine-rhino7)
  --wine <PATH>           Use this Wine binary
  --build-wine            Build the patched Wine 11.18 from source
  --wine-src <DIR>        Reuse an existing Wine source tree (implies --build-wine)
  --wine-install <DIR>    Install the built Wine here (default: ~/.local/share/wine-rhino7)
  --patches <SET>         all (default) or core; see docs/patches.md
  --wayland               Also apply the experimental Wayland driver patch (16)
  --skip-dotnet           Do not install .NET Framework 4.8 / fonts
  --extras                Also install msxml6 and gdiplus
  --dxvk                  Deploy DXVK (optional, Direct3D only)
  --dxvk-dir <PATH>       Directory with 64-bit DXVK DLLs
  --cosmic-rules          Write a COSMIC auto-tiling exception for Rhino
  --pin-dock              Pin Rhino to the COSMIC dock
  --no-integration        No dock pin, no window rules, menu entry only
  --installer <PATH>      Use this local Rhino 7 installer .exe
  --installer-url <URL>   Download the installer from here instead of the default
  --no-download           Never download the installer; only use --installer
  --run                   Launch Rhino when finished
  -h, --help              Show this help

With no --installer, the Rhino 7.38 installer is downloaded from McNeel's file
server (293 MiB, cached in ~/.cache/rhino7-linux) and verified by checksum, so a
plain "./install.sh -y" goes from nothing to a working Rhino. You still need your
own Rhino 7 license; this only automates the download of the public installer.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -y|--yes|--non-interactive) NON_INTERACTIVE=1; shift ;;
        --deps) INSTALL_DEPS=1; shift ;;
        --check) CHECK_ONLY=1; shift ;;
        --prefix) TARGET_PREFIX="$2"; shift 2 ;;
        --wine) CUSTOM_WINE="$2"; shift 2 ;;
        --build-wine) BUILD_WINE=1; shift ;;
        --wine-src) WINE_SRC_DIR="$2"; BUILD_WINE=1; shift 2 ;;
        --wine-install) WINE_INSTALL_DIR="$2"; shift 2 ;;
        --patches) PATCH_SET="$2"; shift 2 ;;
        --wayland) ENABLE_WAYLAND=1; shift ;;
        --skip-dotnet) SKIP_DOTNET=1; shift ;;
        --extras) INSTALL_EXTRAS=1; shift ;;
        --dxvk) ENABLE_DXVK=1; shift ;;
        --dxvk-dir) CUSTOM_DXVK_DIR="$2"; ENABLE_DXVK=1; shift 2 ;;
        --cosmic-rules) COSMIC_RULES=1; shift ;;
        --pin-dock) PIN_DOCK=1; shift ;;
        --no-integration) NO_INTEGRATION=1; COSMIC_RULES=0; PIN_DOCK=0; shift ;;
        --installer) RHINO_INSTALLER="$2"; shift 2 ;;
        --installer-url) RHINO_INSTALLER_URL="$2"; shift 2 ;;
        --no-download) NO_DOWNLOAD=1; shift ;;
        --run) RUN_RHINO=1; shift ;;
        -h|--help) print_help; exit 0 ;;
        *) echo -e "${RED}Unknown option: $1${NC}" >&2; echo "Try ./install.sh --help"; exit 1 ;;
    esac
done

# Everything from here is mirrored into a log, so a failed run leaves something
# to read or paste into a report without having to reproduce it.
LOG_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/rhino7-linux/logs/install-$(date +%Y%m%d-%H%M%S).log"
if [ "$CHECK_ONLY" -eq 0 ]; then
    mkdir -p "$(dirname "$LOG_FILE")"
    exec > >(tee -a "$LOG_FILE") 2>&1
fi

RUN_START="$(date +%s)"
STEP_START="$RUN_START"

step() {
    STEP_START="$(date +%s)"
    echo ""
    if [ -n "${2:-}" ]; then
        echo -e "${BOLD}${BLUE}==> $1${NC} ${CYAN}($2)${NC}"
    else
        echo -e "${BOLD}${BLUE}==> $1${NC}"
    fi
}

find_rhino_exe() {
    for d in "$TARGET_PREFIX/drive_c/Program Files/Rhino 7/System/Rhino.exe" \
             "$TARGET_PREFIX/drive_c/Program Files/Rhino 7 WIP/System/Rhino.exe"; do
        [ -f "$d" ] && { echo "$d"; return 0; }
    done
    return 1
}

step_done() {
    local d=$(( $(date +%s) - STEP_START ))
    printf "    %bdone%b in %dm %02ds\n" "$GREEN" "$NC" "$((d / 60))" "$((d % 60))"
}

detect_distro() {
    DISTRO_ID="unknown"; DISTRO_NAME="Unknown Linux"; DISTRO_FAMILY="unknown"
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        DISTRO_ID="${ID:-unknown}"
        DISTRO_NAME="${PRETTY_NAME:-${NAME:-unknown}}"
        case "$DISTRO_ID" in
            fedora|rhel|centos|rocky|almalinux|nobara) DISTRO_FAMILY="fedora" ;;
            arch|manjaro|endeavouros|garuda|artix|arcolinux) DISTRO_FAMILY="arch" ;;
            ubuntu|debian|pop|linuxmint|elementary|zorin|neon) DISTRO_FAMILY="debian" ;;
            opensuse*|suse|sles) DISTRO_FAMILY="suse" ;;
            *)
                case "${ID_LIKE:-}" in
                    *fedora*|*rhel*) DISTRO_FAMILY="fedora" ;;
                    *arch*) DISTRO_FAMILY="arch" ;;
                    *debian*|*ubuntu*) DISTRO_FAMILY="debian" ;;
                    *suse*) DISTRO_FAMILY="suse" ;;
                esac
                ;;
        esac
    fi
}

detect_session() {
    SESSION_TYPE="${XDG_SESSION_TYPE:-unknown}"
    DESKTOP="${XDG_CURRENT_DESKTOP:-unknown}"
    IS_COSMIC=0
    case "${DESKTOP,,}" in
        *cosmic*) IS_COSMIC=1 ;;
    esac

    # On COSMIC the desktop integration is the point of the exercise: a pinned,
    # clickable icon and windows that are allowed to float. Both are listed in
    # the plan and can be declined with --no-integration.
    if [ "$IS_COSMIC" -eq 1 ] && [ "$NO_INTEGRATION" -eq 0 ]; then
        COSMIC_RULES=1
        PIN_DOCK=1
    fi
}

detect_distro
detect_session

echo -e "${BOLD}${CYAN}"
echo "  Rhinoceros 7 on Linux"
echo -e "${NC}  Distribution : ${BOLD}${DISTRO_NAME}${NC} (${DISTRO_FAMILY})"
echo -e "  Session      : ${BOLD}${DESKTOP}${NC} / ${SESSION_TYPE}"
echo "=========================================================================="

# ------------------------------------------------------------------------------
# Dependencies
# ------------------------------------------------------------------------------
runtime_deps() {
    case "$DISTRO_FAMILY" in
        fedora) echo "wine winetricks cabextract vulkan-loader mesa-dri-drivers mesa-vulkan-drivers libX11 freetype gnutls samba-winbind-clients icoutils curl" ;;
        arch)   echo "wine winetricks cabextract vulkan-icd-loader libx11 freetype2 gnutls samba icoutils curl" ;;
        debian) echo "wine64 winetricks cabextract libvulkan1 mesa-vulkan-drivers libx11-6 libfreetype6 libgnutls30 winbind icoutils curl" ;;
        suse)   echo "wine winetricks cabextract vulkan libX11-6 freetype2 libgnutls30 samba-winbind icoutils curl" ;;
        *)      echo "wine winetricks cabextract vulkan icoutils curl" ;;
    esac
}

install_runtime_deps() {
    local deps; deps="$(runtime_deps)"
    echo -e "\n${BOLD}${BLUE}[Deps] Installing runtime packages...${NC}"
    local sudo_cmd=""; command -v sudo >/dev/null 2>&1 && sudo_cmd="sudo"
    case "$DISTRO_FAMILY" in
        fedora) $sudo_cmd dnf install -y $deps ;;
        arch)   $sudo_cmd pacman -S --needed --noconfirm $deps ;;
        debian) $sudo_cmd apt update && $sudo_cmd apt install -y $deps ;;
        suse)   $sudo_cmd zypper install -y $deps ;;
        *) echo -e "${YELLOW}Unknown distribution. Install manually: $deps${NC}" ;;
    esac
    enable_ntsync
}

# ntsync is Wine's in-kernel implementation of NT synchronisation objects,
# present in Linux 6.14 and later. It is not loaded by default and its device
# node is root-only, so Wine falls back to futexes. Rhino's meshing and
# Grasshopper solves are thread heavy, which is where it pays off.
enable_ntsync() {
    local sudo_cmd=""
    [ -w /dev/ntsync ] && return 0
    command -v sudo >/dev/null 2>&1 && sudo_cmd="sudo"
    [ -n "$sudo_cmd" ] || [ "$(id -u)" = "0" ] || return 0

    echo -e "\n${BOLD}${BLUE}[Deps] Enabling /dev/ntsync...${NC}"
    if ! modinfo ntsync >/dev/null 2>&1 && [ ! -e /dev/ntsync ]; then
        echo -e " ${YELLOW}skipped${NC}  this kernel has no ntsync module (needs 6.14 or newer)"
        return 0
    fi

    $sudo_cmd modprobe ntsync 2>/dev/null || true
    echo ntsync | $sudo_cmd tee /etc/modules-load.d/ntsync.conf >/dev/null 2>&1 || true

    if [ -e /dev/ntsync ] && [ ! -w /dev/ntsync ]; then
        printf 'KERNEL=="ntsync", MODE="0666"\n' | \
            $sudo_cmd tee /etc/udev/rules.d/70-ntsync.rules >/dev/null 2>&1 || true
        $sudo_cmd udevadm control --reload >/dev/null 2>&1 || true
        $sudo_cmd udevadm trigger >/dev/null 2>&1 || true
    fi

    if [ -w /dev/ntsync ]; then
        echo -e " ${GREEN}ok${NC}       /dev/ntsync is available and writable"
    else
        echo -e " ${YELLOW}warn${NC}     /dev/ntsync still unavailable; Wine will use futexes"
    fi
}

install_build_deps() {
    echo -e "\n${BOLD}${BLUE}[Deps] Installing Wine build dependencies...${NC}"
    local sudo_cmd=""; command -v sudo >/dev/null 2>&1 && sudo_cmd="sudo"
    case "$DISTRO_FAMILY" in
        fedora)
            # The explicit list runs first and is what the build actually needs.
            # builddep is only a bonus on top, because it depends on the source
            # repositories being enabled and silently does nothing otherwise -
            # which is how a Wine without OpenGL gets built.
            $sudo_cmd dnf install -y \
                gcc gcc-c++ make bison flex \
                mingw64-gcc mingw64-gcc-c++ mingw32-gcc mingw32-gcc-c++ \
                mesa-libGL-devel mesa-libEGL-devel mesa-libGLU-devel libglvnd-devel \
                libX11-devel libXext-devel libXcomposite-devel libXdamage-devel \
                libXrandr-devel libXcursor-devel libXi-devel libXrender-devel \
                libXfixes-devel libXinerama-devel libXxf86vm-devel \
                freetype-devel fontconfig-devel gnutls-devel \
                alsa-lib-devel pulseaudio-libs-devel pipewire-devel \
                vulkan-loader-devel wayland-devel wayland-protocols-devel libxkbcommon-devel \
                gstreamer1-devel gstreamer1-plugins-base-devel \
                dbus-devel cups-devel libusb1-devel krb5-devel openldap-devel SDL2-devel
            $sudo_cmd dnf install -y dnf-plugins-core 2>/dev/null || true
            $sudo_cmd dnf builddep -y wine 2>/dev/null || true
            ;;
        arch)   $sudo_cmd pacman -S --needed --noconfirm base-devel bison flex mingw-w64-gcc libxext libxcomposite libxdamage libxrandr vulkan-headers ;;
        debian) $sudo_cmd apt build-dep -y wine || $sudo_cmd apt install -y build-essential bison flex gcc-mingw-w64 libx11-dev libfreetype-dev libgnutls28-dev libxext-dev libxcomposite-dev libxdamage-dev libxrandr-dev ;;
        suse)   $sudo_cmd zypper source-install -d wine || $sudo_cmd zypper install -y gcc gcc-c++ make bison flex libX11-devel freetype2-devel libgnutls-devel ;;
        *) echo -e "${YELLOW}Install bison, flex, a C compiler, mingw-w64 and X11 headers manually.${NC}" ;;
    esac
}

# ------------------------------------------------------------------------------
# Diagnostics
# ------------------------------------------------------------------------------
run_checks() {
    local pass="${GREEN}[PASS]${NC}" warn="${YELLOW}[WARN]${NC}" fail="${RED}[FAIL]${NC}"
    echo -e "\n${BOLD}${BLUE}[Check] Environment${NC}"

    # Report the Wine that will actually be used, not whatever is first in PATH.
    local checked_wine="${WINE_BIN:-}"
    if [ -z "$checked_wine" ]; then
        local cfg="${XDG_CONFIG_HOME:-$HOME/.config}/rhino7-linux/config"
        [ -f "$cfg" ] && checked_wine="$(sed -n 's/^RHINO_WINE="\(.*\)"$/\1/p' "$cfg")"
    fi
    [ -x "${checked_wine:-}" ] || checked_wine="$(command -v wine 2>/dev/null || true)"
    if [ -n "$checked_wine" ]; then
        echo -e " $pass wine: $("$checked_wine" --version 2>/dev/null) at $checked_wine"
    else
        echo -e " $fail wine not found. Run ./install.sh --deps"
    fi

    if command -v winetricks >/dev/null 2>&1; then
        echo -e " $pass winetricks: $(winetricks --version 2>/dev/null | head -n1)"
    else
        echo -e " $fail winetricks not found; .NET Framework 4.8 cannot be installed."
    fi

    if [ "$SESSION_TYPE" = "wayland" ]; then
        if [ -n "${DISPLAY:-}" ]; then
            echo -e " $pass Wayland session with XWayland on $DISPLAY"
        else
            echo -e " $fail Wayland session without XWayland (DISPLAY empty). Rhino needs it."
        fi
    elif [ "$SESSION_TYPE" = "x11" ]; then
        echo -e " $pass X11 session on ${DISPLAY:-unset}"
    else
        echo -e " $warn Unrecognised session type: $SESSION_TYPE"
    fi

    if command -v glxinfo >/dev/null 2>&1; then
        local glver
        glver="$(glxinfo -B 2>/dev/null | grep -m1 'Max core profile version' | sed 's/.*: *//')"
        if [ -n "$glver" ]; then
            if awk -v v="$glver" 'BEGIN{exit !(v+0 >= 4.1)}'; then
                echo -e " $pass OpenGL core profile $glver (Rhino 7 needs 4.1)"
            else
                echo -e " $fail OpenGL core profile $glver is below the required 4.1"
            fi
        else
            echo -e " $warn Could not read the OpenGL version from glxinfo"
        fi
    else
        echo -e " $warn glxinfo not installed (Fedora: sudo dnf install glx-utils) - OpenGL unverified"
    fi

    if [ -e /dev/ntsync ]; then
        echo -e " $pass /dev/ntsync present (fast in-kernel synchronisation)"
    else
        echo -e " $warn /dev/ntsync missing; Wine falls back to futex synchronisation"
    fi

    local clr="$TARGET_PREFIX/drive_c/windows/Microsoft.NET/Framework64/v4.0.30319/clr.dll"
    if [ -f "$clr" ]; then
        echo -e " $pass .NET Framework 4.x present in $TARGET_PREFIX"
    elif [ -d "$TARGET_PREFIX" ]; then
        echo -e " $fail .NET Framework 4.8 missing in $TARGET_PREFIX"
    else
        echo -e " $warn Prefix $TARGET_PREFIX does not exist yet"
    fi

    if [ -f "$TARGET_PREFIX/drive_c/windows/system32/mfc140u.dll" ]; then
        echo -e " $pass Visual C++ runtime with MFC (mfc140u.dll) present"
    elif [ -d "$TARGET_PREFIX" ]; then
        echo -e " $fail mfc140u.dll missing; RhinoCore.dll cannot load without it"
    fi

    local rhino_found=0
    for d in "$TARGET_PREFIX/drive_c/Program Files/Rhino 7/System/Rhino.exe" \
             "$TARGET_PREFIX/drive_c/Program Files/Rhino 7 WIP/System/Rhino.exe"; do
        [ -f "$d" ] && { echo -e " $pass Rhino found: $d"; rhino_found=1; break; }
    done
    [ "$rhino_found" -eq 0 ] && echo -e " $warn Rhino 7 is not installed in this prefix yet"

    if [ "$IS_COSMIC" -eq 1 ]; then
        local rules="$HOME/.config/cosmic/com.system76.CosmicSettings.WindowRules/v1/tiling_exception_custom"
        if [ -f "$rules" ] && grep -q 'rhino\.exe' "$rules" 2>/dev/null; then
            echo -e " $pass COSMIC auto-tiling exception for rhino.exe is in place"
        else
            echo -e " $warn COSMIC detected without a tiling exception for rhino.exe (see docs/cosmic.md)"
        fi
    fi
}

if [ "$CHECK_ONLY" -eq 1 ]; then
    run_checks
    exit 0
fi

# ------------------------------------------------------------------------------
# Preflight: fail before the long steps, not after them
# ------------------------------------------------------------------------------
preflight() {
    local problems=0 missing="" t

    step "Checking prerequisites"

    if [ "$INSTALL_DEPS" -eq 0 ]; then
        for t in wine winetricks cabextract; do
            command -v "$t" >/dev/null 2>&1 || missing="$missing $t"
        done
        if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
            missing="$missing curl"
        fi
        if [ -n "$missing" ]; then
            echo -e " ${RED}missing${NC}  tools:$missing"
            echo -e "          fix: ${CYAN}./install.sh --deps${NC}  (or install them yourself)"
            problems=$((problems + 1))
        else
            echo -e " ${GREEN}ok${NC}       wine, winetricks, cabextract and a downloader are present"
        fi
    fi

    # The prefix ends up around 4 GB with .NET and Rhino, plus the cached installer.
    local avail_mb
    avail_mb="$(df -Pk "$HOME" 2>/dev/null | awk 'NR==2{print int($4/1024)}')"
    if [ -n "$avail_mb" ] && [ "$avail_mb" -lt 6000 ]; then
        echo -e " ${RED}low disk${NC} ${avail_mb} MB free in $HOME, about 6000 MB are needed"
        problems=$((problems + 1))
    else
        echo -e " ${GREEN}ok${NC}       disk: ${avail_mb:-?} MB free in $HOME"
    fi

    if [ "$BUILD_WINE" -eq 1 ]; then
        local repo_mb
        repo_mb="$(df -Pk "$REPO_DIR" 2>/dev/null | awk 'NR==2{print int($4/1024)}')"
        if [ -n "$repo_mb" ] && [ "$repo_mb" -lt 10000 ]; then
            echo -e " ${YELLOW}warn${NC}     building Wine needs about 10 GB; ${repo_mb} MB free here"
        fi
    fi

    if command -v glxinfo >/dev/null 2>&1; then
        local glver renderer
        glver="$(glxinfo -B 2>/dev/null | grep -m1 'Max core profile version' | sed 's/.*: *//')"
        renderer="$(glxinfo -B 2>/dev/null | grep -m1 -i 'OpenGL renderer' | sed 's/.*: *//')"
        if [ -n "$glver" ] && ! awk -v v="$glver" 'BEGIN{exit !(v+0 >= 4.1)}'; then
            echo -e " ${RED}opengl${NC}   core profile $glver, Rhino 7 needs 4.1"
            problems=$((problems + 1))
        elif echo "$renderer" | grep -qiE 'llvmpipe|softpipe|swrast'; then
            echo -e " ${YELLOW}warn${NC}     software OpenGL ($renderer)"
            echo -e "          Rhino will start but the viewports will be slow. In a VM,"
            echo -e "          enable 3D acceleration on the guest for usable performance."
        else
            echo -e " ${GREEN}ok${NC}       OpenGL $glver on ${renderer:-unknown}"
        fi
    fi

    if [ "$problems" -gt 0 ]; then
        echo ""
        echo -e "${RED}Stopping here: $problems problem(s) above would only surface later.${NC}" >&2
        exit 1
    fi
}

# ------------------------------------------------------------------------------
# Plan: say what will happen, ask once, then run without further questions
# ------------------------------------------------------------------------------
PLAN_CONFIRMED=0

show_plan() {
    local will_install_rhino=1
    find_rhino_exe >/dev/null 2>&1 && will_install_rhino=0
    [ "$NO_DOWNLOAD" -eq 1 ] && [ -z "$RHINO_INSTALLER" ] && will_install_rhino=0

    echo ""
    echo -e "${BOLD}Plan${NC}"
    echo    "  Prefix        : $TARGET_PREFIX"
    [ "$INSTALL_DEPS" -eq 1 ] && echo "  Packages      : install via $DISTRO_FAMILY package manager"
    if [ "$BUILD_WINE" -eq 1 ]; then
        echo "  Wine          : build patched $WINE_VERSION into $WINE_INSTALL_DIR   (20-60 min)"
    else
        echo "  Wine          : ${WINE_BIN:-system wine}"
    fi
    if [ "$SKIP_DOTNET" -eq 0 ]; then
        echo -e "  Runtimes      : .NET 4.8, Visual C++ with MFC, core fonts   ${CYAN}(15-40 min, mostly silent)${NC}"
    fi
    if [ "$will_install_rhino" -eq 1 ]; then
        if [ -n "$RHINO_INSTALLER" ]; then
            echo "  Rhino 7       : install from $RHINO_INSTALLER   (5-10 min)"
        else
            echo -e "  Rhino 7       : download 293 MiB and install   ${CYAN}(5-15 min)${NC}"
        fi
    fi
    local integration="menu entry, .3dm association"
    [ "$PIN_DOCK" -eq 1 ] && integration="$integration, pinned to the dock"
    [ "$COSMIC_RULES" -eq 1 ] && integration="$integration, COSMIC floating rule"
    echo    "  Desktop       : $integration"
    echo    "  Log           : $LOG_FILE"
    echo ""
    echo -e "  Re-running is safe: finished steps are detected and skipped."

    if [ "$NON_INTERACTIVE" -eq 0 ]; then
        echo ""
        read -rp "Start? [Y/n] " plan_answer
        if [[ ! "${plan_answer:-y}" =~ ^[Yy] ]]; then
            echo "Nothing was changed."
            exit 0
        fi
    fi
    PLAN_CONFIRMED=1
}

preflight

if [ "$INSTALL_DEPS" -eq 1 ]; then
    step "Installing packages"
    install_runtime_deps
    step_done
fi

# ------------------------------------------------------------------------------
# Wine resolution
# ------------------------------------------------------------------------------
WINE_BIN=""

resolve_wine() {
    if [ -n "$CUSTOM_WINE" ]; then
        [ -x "$CUSTOM_WINE" ] || { echo -e "${RED}Error: $CUSTOM_WINE is not executable${NC}" >&2; exit 1; }
        WINE_BIN="$CUSTOM_WINE"; return
    fi
    for candidate in \
        "${WINE:-}" \
        "$WINE_INSTALL_DIR/bin/wine" \
        "/opt/wine-rhino7/bin/wine"; do
        if [ -n "$candidate" ] && [ -x "$candidate" ]; then
            WINE_BIN="$candidate"; return
        fi
    done
    command -v wine >/dev/null 2>&1 && WINE_BIN="$(command -v wine)"
}

selected_patches() {
    local list=""
    case "$PATCH_SET" in
        core) list="$CORE_PATCHES" ;;
        all)  list="$CORE_PATCHES $LICENSING_PATCHES $D3D_PATCHES" ;;
        *) echo -e "${RED}Error: --patches must be 'all' or 'core'${NC}" >&2; exit 1 ;;
    esac
    [ "$ENABLE_WAYLAND" -eq 1 ] && list="$list $WAYLAND_PATCHES"
    # shellcheck disable=SC2086
    printf '%s\n' $list | sort -u
}

build_patched_wine() {
    echo -e "\n${BOLD}${BLUE}[Wine] Building patched Wine ${WINE_VERSION}...${NC}"
    local src_dir="${WINE_SRC_DIR:-$REPO_DIR/wine-src}"
    local build_dir="$REPO_DIR/build-wine"

    install_build_deps

    if [ ! -d "$src_dir" ]; then
        echo "Cloning $WINE_VERSION into $src_dir (shallow)..."
        git clone --depth 1 --branch "$WINE_VERSION" \
            https://gitlab.winehq.org/wine/wine.git "$src_dir"
    fi

    # Reset to pristine sources before patching. Without this, an edited patch
    # cannot be applied over the previous version of itself and the only way out
    # is deleting the tree and rebuilding everything. git only rewrites the
    # files the patches touched, so make still rebuilds just those.
    if [ -d "$src_dir/.git" ]; then
        echo "Resetting the source tree..."
        git -C "$src_dir" checkout -- . 2>/dev/null || true
        # checkout only restores modified files. Patches that add new ones, such
        # as comctl32/taskdialog.c, would otherwise stay behind and make the
        # patch fail on the next run.
        git -C "$src_dir" clean -fdq 2>/dev/null || true
    fi

    local num
    cd "$src_dir"
    while read -r num; do
        local patch_file
        patch_file="$(ls "$REPO_DIR"/patches/"$num"-*.patch 2>/dev/null | head -n1)"
        if [ -z "$patch_file" ]; then
            echo -e " ${RED}[MISSING]${NC} no patch file for number $num" >&2
            return 1
        fi
        local name; name="$(basename "$patch_file")"
        if patch -p1 --dry-run -R -N --silent < "$patch_file" >/dev/null 2>&1; then
            echo -e " ${GREEN}[ALREADY]${NC} $name"
        elif patch -p1 --dry-run -N --silent < "$patch_file" >/dev/null 2>&1; then
            patch -p1 -N --silent < "$patch_file" >/dev/null
            echo -e " ${GREEN}[APPLIED]${NC} $name"
        else
            echo -e " ${RED}[FAILED]${NC} $name does not apply to $WINE_VERSION" >&2
            return 1
        fi
    done < <(selected_patches)

    # Both architectures, not just --enable-win64. The prefix holds 32-bit code
    # (the .NET Framework installs x86 and x64 side by side), so a 64-bit only
    # Wine cannot start it: "failed to load ...syswow64\ntdll.dll error
    # c0000135". --enable-archs gives Wine's new WoW64 without needing 32-bit
    # Unix libraries.
    local configure_args=(--enable-archs=i386,x86_64 --prefix="$WINE_INSTALL_DIR" --without-capi)

    # A build tree configured with different architectures cannot be reused.
    if [ -f "$build_dir/config.log" ] && ! grep -q 'enable-archs=i386,x86_64' "$build_dir/config.log"; then
        echo "Build tree was configured differently; starting it over..."
        rm -rf "$build_dir"
    fi

    mkdir -p "$build_dir"
    cd "$build_dir"
    # Re-running configure rewrites config.h, and everything that includes it is
    # then rebuilt - an hour instead of the minutes a changed patch needs. Reuse
    # an existing configuration when it was made with the same arguments.
    if [ -f config.status ] && [ -f include/config.h ] && \
       grep -q "prefix=$WINE_INSTALL_DIR" config.log 2>/dev/null && \
       grep -q 'enable-archs=i386,x86_64' config.log 2>/dev/null; then
        echo "Reusing the existing build configuration."
    else
        echo "Configuring (prefix: $WINE_INSTALL_DIR)..."
        "$src_dir/configure" "${configure_args[@]}"
    fi

    # Wine configures and builds happily without OpenGL and then cannot create a
    # GL context at runtime: Rhino shows "An error occurred trying to initialize
    # the graphics system" and the log says
    # "err:wgl:internal_context_create Failed to create internal global context".
    # Catch it here rather than after an hour of compiling.
    if ! grep -qE '^#define SONAME_LIB(GL|EGL)' include/config.h; then
        echo "" >&2
        echo -e "${RED}Stopping: configure found no OpenGL library, so this build could not${NC}" >&2
        echo -e "${RED}render Rhino's viewports.${NC}" >&2
        echo "" >&2
        echo "Install the development files and start the build over:" >&2
        case "$DISTRO_FAMILY" in
            fedora) echo -e "  ${CYAN}sudo dnf install -y mesa-libGL-devel mesa-libEGL-devel libglvnd-devel${NC}" >&2 ;;
            debian) echo -e "  ${CYAN}sudo apt install -y libgl-dev libegl-dev${NC}" >&2 ;;
            arch)   echo -e "  ${CYAN}sudo pacman -S --needed mesa libglvnd${NC}" >&2 ;;
            *)      echo "  the OpenGL and EGL development packages of your distribution" >&2 ;;
        esac
        echo -e "  ${CYAN}rm -rf '$build_dir' && ./install.sh --build-wine${NC}" >&2
        return 1
    fi
    echo " OpenGL support: present"
    grep -qE '^#define SONAME_LIBVULKAN' include/config.h || \
        echo " Note: no Vulkan at build time; only matters if you use DXVK."

    echo "Compiling with $(nproc) jobs. This takes a while..."
    make -j"$(nproc)"
    make install
    cd "$REPO_DIR"

    WINE_BIN="$WINE_INSTALL_DIR/bin/wine"
    [ -x "$WINE_BIN" ] || { echo -e "${RED}Error: build finished but $WINE_BIN is missing${NC}" >&2; exit 1; }
    echo -e "${GREEN}Built: $("$WINE_BIN" --version)${NC}"
}

# Wine is resolved before the plan is shown, so the plan can name the binary.
if [ "$BUILD_WINE" -eq 0 ]; then
    resolve_wine
    if [ -z "$WINE_BIN" ]; then
        echo -e "${RED}Error: no Wine binary found.${NC}" >&2
        echo "Install it with ./install.sh --deps, or build the patched Wine with --build-wine." >&2
        exit 1
    fi
fi

show_plan

if [ "$BUILD_WINE" -eq 1 ]; then
    step "Building patched Wine" "20-60 min"
    build_patched_wine
    step_done
else
    echo ""
    echo -e "${BOLD}Wine${NC}: $WINE_BIN ($("$WINE_BIN" --version 2>/dev/null))"
    echo -e "      Unpatched. The patches fix black menu borders, missing panels and"
    echo -e "      viewports vanishing on a second monitor: ${CYAN}./install.sh --build-wine${NC}"
fi

# ------------------------------------------------------------------------------
# Prefix deployment
# ------------------------------------------------------------------------------
step "Setting up the Wine prefix" "15-40 min on a first run"
export WINE="$WINE_BIN"
export WINEPREFIX="$TARGET_PREFIX"
export RHINO_PREFIX="$TARGET_PREFIX"

deploy_cmd=("$REPO_DIR/tools/deploy-rhino7.sh" --prefix "$TARGET_PREFIX" --wine "$WINE_BIN")
[ "$SKIP_DOTNET" -eq 1 ] && deploy_cmd+=(--skip-dotnet)
[ "$INSTALL_EXTRAS" -eq 1 ] && deploy_cmd+=(--extras)
[ "$ENABLE_DXVK" -eq 1 ] && deploy_cmd+=(--dxvk)
[ -n "$CUSTOM_DXVK_DIR" ] && deploy_cmd+=(--dxvk-dir "$CUSTOM_DXVK_DIR")
[ "$COSMIC_RULES" -eq 1 ] && deploy_cmd+=(--cosmic-rules)
[ "$PIN_DOCK" -eq 1 ] && deploy_cmd+=(--pin-dock)
"${deploy_cmd[@]}"
step_done

# ------------------------------------------------------------------------------
# Rhino installation
# ------------------------------------------------------------------------------
WINESERVER_BIN="$(dirname "$WINE_BIN")/wineserver"
[ -x "$WINESERVER_BIN" ] || WINESERVER_BIN="$(command -v wineserver 2>/dev/null || echo wineserver)"

verify_sha256() {
    local expected="$1" file="$2"
    if command -v sha256sum >/dev/null 2>&1; then
        echo "$expected  $file" | sha256sum -c --status 2>/dev/null
    elif command -v shasum >/dev/null 2>&1; then
        echo "$expected  $file" | shasum -a 256 -c --status 2>/dev/null
    else
        echo -e "${YELLOW}      No sha256 tool available; skipping checksum check.${NC}" >&2
        return 0
    fi
}

# Fetch the public Rhino 7 installer unless the user supplied one. Resumable, so
# an interrupted download continues instead of starting over.
download_installer() {
    local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/rhino7-linux"
    local target="$cache_dir/$(basename "$RHINO_INSTALLER_URL")"
    mkdir -p "$cache_dir"

    if [ -f "$target" ] && verify_sha256 "$RHINO_INSTALLER_SHA256" "$target"; then
        echo -e " ${GREEN}[PASS]${NC} Using the verified cached installer: $target"
        RHINO_INSTALLER="$target"
        return 0
    fi

    echo -e "    source: ${CYAN}$RHINO_INSTALLER_URL${NC}"
    echo -e "    293 MiB, cached in $cache_dir, resumes if interrupted"
    # The plan was already confirmed, so this does not ask a second time.
    if [ "$NON_INTERACTIVE" -eq 0 ] && [ "$PLAN_CONFIRMED" -eq 0 ]; then
        read -rp "Download the Rhino 7 installer now? [Y/n] " dl_answer
        if [[ ! "${dl_answer:-y}" =~ ^[Yy] ]]; then
            echo "Skipping the download."
            return 1
        fi
    fi

    if command -v curl >/dev/null 2>&1; then
        curl -fL --progress-bar -C - -o "$target" "$RHINO_INSTALLER_URL" || true
    elif command -v wget >/dev/null 2>&1; then
        wget -c -O "$target" "$RHINO_INSTALLER_URL" || true
    else
        echo -e "${RED}Error: neither curl nor wget is available.${NC}" >&2
        return 1
    fi

    if [ ! -f "$target" ]; then
        echo -e "${RED}Error: the download produced no file.${NC}" >&2
        return 1
    fi
    local actual_size
    actual_size="$(stat -c%s "$target" 2>/dev/null || stat -f%z "$target" 2>/dev/null || echo 0)"
    if [ "$actual_size" != "$RHINO_INSTALLER_SIZE" ]; then
        echo -e "${YELLOW}      Size is $actual_size bytes, expected $RHINO_INSTALLER_SIZE.${NC}" >&2
    fi
    if ! verify_sha256 "$RHINO_INSTALLER_SHA256" "$target"; then
        echo -e "${RED}Error: checksum mismatch for $target${NC}" >&2
        echo "Expected sha256: $RHINO_INSTALLER_SHA256" >&2
        echo "McNeel may have replaced the file, or the download was truncated." >&2
        echo "Delete it and retry, or download the installer yourself and pass" >&2
        echo "  ./install.sh --installer /path/to/rhino_en-us_7.x.exe" >&2
        return 1
    fi

    echo -e " ${GREEN}[PASS]${NC} Downloaded and verified: $target"
    RHINO_INSTALLER="$target"
}

step "Installing Rhino 7" "5-15 min"

if [ -z "$RHINO_INSTALLER" ] && ! find_rhino_exe >/dev/null; then
    if [ "$NO_DOWNLOAD" -eq 1 ]; then
        echo -e " ${YELLOW}[INFO]${NC} --no-download given and no --installer; skipping installation."
    else
        download_installer || true
    fi
fi

if [ -n "$RHINO_INSTALLER" ]; then
    if [ -f "$RHINO_INSTALLER" ]; then
        echo -e "Running the Rhino 7 installer: ${CYAN}$RHINO_INSTALLER${NC}"
        # -passive shows a progress bar only; automatic updates stay off because
        # the McNeel update service is pointless inside a Wine prefix.
        installer_flags=(-package -norestart ENABLE_AUTOMATIC_UPDATES=0)
        if [ "$NON_INTERACTIVE" -eq 1 ]; then
            installer_flags=(-package -passive -norestart ENABLE_AUTOMATIC_UPDATES=0)
        fi
        # winemenubuilder would turn the installer's Windows shortcuts into a
        # second set of menu and desktop entries that bypass the launcher.
        # This setup installs its own entry, so it is disabled for this call.
        WINEDLLOVERRIDES="winemenubuilder.exe=d" \
        "$WINE_BIN" "$RHINO_INSTALLER" "${installer_flags[@]}" || {
            rc=$?
            [ "$rc" -eq 3010 ] || echo -e "${YELLOW}Installer exited with code $rc${NC}"
        }
        while pgrep -u "$(id -u)" -f 'msiexec' >/dev/null 2>&1; do sleep 2; done
        timeout 60 "$WINESERVER_BIN" -w 2>/dev/null || true
        # Rerun deployment so Rhino's bundled fonts and the icon are picked up.
        "${deploy_cmd[@]}"
    else
        echo -e "${RED}Error: installer not found at $RHINO_INSTALLER${NC}"
    fi
fi

step_done

ln -sf "tools/rhino-7" "$REPO_DIR/rhino-7" 2>/dev/null || true

run_checks

TOTAL=$(( $(date +%s) - RUN_START ))
echo ""
if rhino_exe="$(find_rhino_exe)"; then
    echo -e "${BOLD}${GREEN}Ready.${NC} Total time: $((TOTAL / 60))m $((TOTAL % 60))s"
    echo ""
    echo -e "  Start Rhino      ${BOLD}rhino-7${NC}            (also in your application menu)"
    echo -e "  Open a model     ${BOLD}rhino-7 model.3dm${NC}"
    echo -e "  If it misbehaves ${BOLD}rhino-7 --fresh${NC}    then ${BOLD}rhino-7 --log${NC}"
    echo ""
    echo -e "  On the first start Rhino asks for your license or starts the evaluation."
    echo -e "  Cloud Zoo sign-in opens your normal browser."
else
    echo -e "${BOLD}${YELLOW}Not finished:${NC} the prefix is ready, but Rhino 7 is not installed."
    echo ""
    echo -e "  Fetch the public installer   ${CYAN}./install.sh -y${NC}"
    echo -e "  or use your own              ${CYAN}./install.sh --installer /path/to/rhino_7.exe${NC}"
fi
echo ""
echo -e "  Prefix $TARGET_PREFIX   Wine $WINE_BIN"
echo -e "  Log    $LOG_FILE"
echo -e "  Stuck? docs/troubleshooting.md"

if [ "$RUN_RHINO" -eq 1 ]; then
    exec "$REPO_DIR/tools/rhino-7"
elif find_rhino_exe >/dev/null && [ "$NON_INTERACTIVE" -eq 0 ]; then
    echo ""
    read -rp "Launch Rhino now? [Y/n] " answer
    if [[ "${answer:-y}" =~ ^[Yy] ]]; then
        exec "$REPO_DIR/tools/rhino-7"
    fi
fi

find_rhino_exe >/dev/null || [ "$NO_DOWNLOAD" -eq 1 ] || exit 1
