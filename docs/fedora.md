# Fedora setup notes

Written against Fedora Workstation 42 and 43 (including the COSMIC spin). The
commands are plain `dnf`, so they work the same on Fedora KDE, the COSMIC spin
and Nobara.

## 1. Packages

```bash
sudo dnf install -y \
    wine winetricks cabextract \
    vulkan-loader mesa-dri-drivers mesa-vulkan-drivers \
    libX11 freetype gnutls \
    samba-winbind-clients icoutils glx-utils curl
```

`./install.sh --deps` installs exactly this list.

What each unusual entry is for:

- **winetricks + cabextract** install the real .NET Framework 4.8. Without
  cabextract, winetricks cannot unpack the installer payloads.
- **samba-winbind-clients** provides `ntlm_auth`, which Wine uses for NTLM
  authentication. Needed if your license comes from a LAN Zoo server behind
  Windows authentication.
- **icoutils** lets `deploy-rhino7.sh` pull the application icon out of
  `Rhino.exe`, so no McNeel artwork has to be shipped in this repository.
- **glx-utils** provides `glxinfo`, which `./install.sh --check` uses to confirm
  that your driver offers an OpenGL 4.1 core profile. Rhino 7 requires 4.1.

### 32-bit Wine must be present

The `wine` metapackage pulls in both architectures on x86_64. Confirm it:

```bash
rpm -q wine-core
# expect two lines, e.g. wine-core-11.x.x86_64 and wine-core-11.x.i686
```

The .NET Framework 4.8 installer writes both the 32-bit and 64-bit framework
into the prefix. If `wine-core.i686` is missing, `winetricks dotnet48` fails
part way through and Rhino's own installer then aborts with
`rhino.msi:-2147023293`.

### Wine Mono is not a substitute

Fedora installs `wine-mono`, and `wineboot` registers it in every new prefix.
Rhino 7 cannot run on it: RhinoCommon, the Eto based UI and Grasshopper all
need the real framework. `deploy-rhino7.sh` therefore sets `mscoree` to
`native` in the prefix after installing .NET 4.8. Leave `wine-mono` installed
on the system; the override is per prefix and does not disturb anything else.

## 2. GPU driver

Rhino 7 needs an OpenGL 4.1 core profile. Mesa reports 4.6 on Intel, AMD and
Nouveau/NVK, so the stock Fedora drivers are fine.

- **AMD / Intel**: nothing to do, `mesa-dri-drivers` is enough.
- **NVIDIA proprietary**: install from RPM Fusion
  (`akmod-nvidia` plus `xorg-x11-drv-nvidia-cuda`). Check afterwards with
  `glxinfo -B`; if `Max core profile version` is below 4.1, Rhino falls back to
  a software display pipeline and feels unusable.

Check it at any time:

```bash
./install.sh --check
```

## 3. ntsync (optional, worth doing)

Fedora kernels from 6.14 on include the `ntsync` driver, Wine's in-kernel
implementation of NT synchronisation objects. It measurably reduces overhead in
thread heavy workloads, which is exactly what Rhino's meshing and Grasshopper
solves are.

```bash
sudo modprobe ntsync
echo ntsync | sudo tee /etc/modules-load.d/ntsync.conf

# make the device usable without root
printf 'KERNEL=="ntsync", MODE="0666"\n' | \
    sudo tee /etc/udev/rules.d/70-ntsync.rules
sudo udevadm control --reload && sudo udevadm trigger
```

`./install.sh --deps` does all of this for you. The `rhino-7` launcher sets
`WINENTSYNC=1` by itself once `/dev/ntsync` exists,
so there is nothing else to configure.

## 4. DXVK on Fedora (optional)

Rhino 7 renders its viewports with OpenGL, so DXVK changes nothing about
viewport performance. Only install it if a plugin brings its own Direct3D
renderer.

```bash
sudo dnf install -y wine-dxvk
./install.sh --dxvk
```

Fedora's `wine-dxvk` installs its DLLs under
`/usr/lib64/wine/x86_64-windows/` with a `dxvk-` prefix
(`dxvk-d3d11.dll`, `dxvk-dxgi.dll` and so on). `deploy-rhino7.sh` knows that
layout and copies them into the prefix under their real names. If the package is
missing or laid out differently, the script falls back to the pinned DXVK 2.4
release from GitHub, with a checksum check.

## 5. Building the patched Wine

```bash
sudo dnf install -y dnf-plugins-core
./install.sh --build-wine
```

`--build-wine` runs `dnf builddep wine` for you, which pulls the same build
dependencies Fedora uses for its own package, then clones `wine-11.18`, applies
the patch set and installs into `~/.local/share/wine-rhino7`. No `sudo` is
needed for the install step, and your system Wine stays untouched.

Expect 20 to 60 minutes of compiling, and roughly 10 GB free in the repository
directory for the source and build trees.

## 6. Fonts

Fedora ships metric compatible replacements for the common Windows UI fonts, and
`tools/font-substitutes.reg` maps the names Rhino asks for onto them:

| Rhino asks for | Fedora font | Package |
|---|---|---|
| Segoe UI and friends | Liberation Sans | `liberation-sans-fonts` |
| Calibri | Carlito | `google-carlito-fonts` |
| Cambria | Caladea | `google-caladea-fonts` |
| Consolas | Liberation Mono | `liberation-mono-fonts` |

Arial is the exception: Rhino 7 uses it as the default annotation font and reads
the actual file, so `deploy-rhino7.sh` installs a real `arial.ttf`. It looks for
one on the system and on mounted Windows volumes first, and only then downloads
the Microsoft core fonts package. If you have a Windows partition mounted under
`/run/media`, it will be found automatically.

Missing fonts are the single most common cause of Rhino 7 dying on Wine, so if
something crashes early, check this first.
