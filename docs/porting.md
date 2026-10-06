# Porting this to other Rhino versions, distributions and desktops

Field notes for anyone adapting this repository. The setup is deliberately small
- two shell scripts and a patch directory - but the parts that matter are not
obvious, and most of them cost a debugging session to find.

## What is actually Rhino 7 specific

Three properties of Rhino 7 decide almost every design choice here:

| Property | Consequence |
|---|---|
| .NET Framework 4.8 (not .NET Core) | A real framework must be installed into the prefix and `mscoree` overridden to `native`. Wine Mono cannot run RhinoCommon, the Eto based UI or Grasshopper. |
| Viewports render with OpenGL 4.1 | Wine must be built with OpenGL. DXVK is irrelevant for the viewports and stays optional. |
| `RhinoCore.dll` imports `mfc140u.dll` | The Visual C++ runtime with MFC has to be installed separately; Rhino's own installer does not deliver it inside a prefix. |
| No embedded browser | The Edge WebView2 and DirectComposition patches from upstream are dead weight. |

Everything else - prefix layout, launcher, desktop integration, patch handling -
is generic.

## Other Rhino versions

### Rhino 6

Closest relative. Same .NET Framework story, same OpenGL pipeline. Expect it to
work by changing paths only:

- `tools/rhino-7`: the `RHINO_DIR` candidate list.
- `tools/deploy-rhino7.sh`: `RHINO_SYS_DIR` and the desktop entry.
- `install.sh`: `find_rhino_exe` and `RHINO_INSTALLER_URL`.

Rhino 6 targets .NET Framework 4.6/4.7; installing 4.8 covers it, since 4.x is
in-place upgradable.

### Rhino 8

A different animal. It ships .NET 7/8 (CoreCLR) with the application, so
`dotnet48` is not needed, but it embeds Edge WebView2 for Cloud Zoo, the package
manager and HTML panels. That needs the DirectComposition patches this repository
drops (upstream 06 and 07). Start from
[Jabern/rhino-linux](https://github.com/Jabern/rhino-linux) instead of here, and
take only the Fedora and COSMIC parts from this repo.

### Rhino 9 WIP

Use upstream directly. It renders through Direct3D 11 and DXVK, which inverts the
graphics assumptions made here.

### Checklist when changing versions

```bash
grep -rn "Rhino 7\|rhino-7\|rhino7" install.sh tools/ docs/
```

The install path (`C:\Program Files\Rhino <N>\System\Rhino.exe`) and the
executable name are the only things Rhino changes between releases; the window
class stays `rhino.exe` because Wine derives it from the executable name,
lowercased.

## Other distributions

The scripts detect `fedora`, `arch`, `debian` and `suse` families and only use
the package manager for dependency installation. Porting means editing
`runtime_deps()` and `install_build_deps()` in `install.sh`.

Pitfalls that are not about package names:

**32-bit support is mandatory.** The .NET Framework installer writes the x86 and
x64 frameworks side by side. Without 32-bit Wine, `winetricks dotnet48` fails
part way through and Rhino's installer then aborts with
`rhino.msi:-2147023293`. On Fedora the `wine` metapackage pulls both
architectures; on Arch you need `multilib`; on Debian `wine32` next to `wine64`.

**Distribution winetricks is often too old.** `dotnet48` is a moving target.
If the packaged winetricks fails, fetch the upstream script:

```bash
curl -L https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks \
    -o ~/.local/bin/winetricks && chmod +x ~/.local/bin/winetricks
```

**Source repositories for build dependencies.** `dnf builddep wine` needs the
Fedora source repositories enabled and does nothing when they are disabled -
without an error that stops a script. `apt build-dep wine` needs `deb-src` lines.
This repository therefore installs an explicit package list first and treats
`builddep` as a bonus. If you add a distribution, make sure your explicit list
contains the OpenGL and EGL development files, or you will build a Wine that
cannot create a GL context.

**Verify, do not trust, the configure result.** `install.sh` greps
`include/config.h` for `SONAME_LIBGL` / `SONAME_LIBEGL` right after `configure`
and aborts if neither is defined. Keep that check when you port the build path;
it is the difference between a five second failure and an hour of compiling
something unusable.

## Other desktops

Nothing in the prefix setup is desktop specific. Only two places are:

- `deploy-rhino7.sh`, the `--cosmic-rules` block: writes
  `~/.config/cosmic/com.system76.CosmicSettings.WindowRules/v1/tiling_exception_custom`.
- `deploy-rhino7.sh`, the `--pin-dock` block: appends to
  `~/.config/cosmic/com.system76.CosmicAppList/v1/favorites`.

Both are plain RON files that `cosmic-comp` and the panel reload on save. The
`appid` and `title` fields are regular expressions matched unanchored, and an
empty `title` matches everything - see [cosmic.md](cosmic.md).

**KDE Plasma and GNOME** need nothing. They handle floating palettes, MDI
children and multi-monitor layouts as they are. The generic `.desktop` entry the
setup installs is enough for pinning in either.

**Tiling compositors** need Rhino's sub-windows to float, or the middle-click
popup toolbar opens as a tiled column and the viewport grid is squeezed into
unusable widths. Equivalents of the COSMIC rule:

```kdl
// niri, ~/.config/niri/config.kdl
window-rule {
    match app-id=r#"rhino\.exe$"#
    open-floating true
}
```

```ini
# Hyprland, ~/.config/hypr/hyprland.conf
windowrulev2 = float, class:^(rhino\.exe)$
windowrulev2 = tile, class:^(rhino\.exe)$, title:(- Rhino)
```

```
# sway / i3
for_window [instance="rhino.exe"] floating enable
for_window [instance="rhino.exe" title="- Rhino"] floating disable
```

To add a desktop, follow the shape of the COSMIC blocks: write the file only
when it does not exist, back up and append when it does, and never rewrite a
list the user maintains.

**Wayland in general:** run Rhino through XWayland. The prefix forces
`HKCU\Software\Wine\Drivers` `Graphics=x11` and the launcher refuses to start
with an empty `DISPLAY`. `winewayland.drv` does not implement enough of the
owner-drawn popup and MDI behaviour Rhino relies on; the optional patch 16
improves Wayland popups but does not change that verdict.

## Wine build notes

```bash
configure --enable-archs=i386,x86_64 --prefix=... --without-capi
```

`--enable-win64` alone is wrong here. It produces a 64-bit only Wine that cannot
start a prefix containing 32-bit code, and fails with
`failed to load ...syswow64\ntdll.dll error c0000135`. `--enable-archs` gives
Wine's new WoW64 without needing 32-bit Unix libraries, and needs the 32-bit
mingw compiler as well.

**One Wine per prefix at a time.** Two Wine versions cannot share a running
wineserver; the second one dies with `version mismatch 962/931`. Stop the prefix
(`rhino-7 --stop`) before switching builds. When the binary changes between
deployments, the setup runs `wineboot -u` to bring the prefix in line.

**Revalidating the patches against a newer Wine** is one loop:

```bash
git clone --depth 1 --branch wine-<version> https://gitlab.winehq.org/wine/wine.git wine-src
cd wine-src
for p in ../patches/*.patch; do
    patch -p1 --dry-run -N --silent < "$p" >/dev/null 2>&1 \
        && echo "OK   $(basename "$p")" || echo "FAIL $(basename "$p")"
done
```

Apply them in numeric order; several touch the same files
(`win32u/window.c`, `winex11.drv/init.c`), so a patch that passes in isolation
can still conflict in sequence. Run the loop once with `--dry-run` and once for
real.

## The failures that cost the most time

Ordered by how long they took to find, as a hint for where to look first:

1. **Wine built without OpenGL.** Configures, compiles and installs without
   complaint; fails only when an application requests a context
   (`err:wgl:internal_context_create`). Rhino reports it as a graphics
   initialisation error, which points nowhere near the build.
2. **`gdiplus` overridden to `native` with no native DLL present.** Wine then
   refuses the builtin fallback and the Rhino installer dies with exit code 126.
   Use `native,builtin` unless you are certain the file is there.
3. **Missing `mfc140u.dll`.** Rhino exits silently, with nothing on screen. Only
   visible with `WINEDEBUG=err+all`.
4. **The `dotnet48` step looks hung.** It runs 15 to 40 minutes without output,
   and the NGen service it starts regularly never exits. Kill `mscorsvw` and
   `ngen.exe` afterwards, and check for `clr.dll` rather than trusting the exit
   code.
5. **Cloud Zoo sign-in over WebSockets** breaks on stale prefix HTTP state
   (`WebSocketSharp ... header of a frame cannot be read`). `wineserver -k`
   first, or use a license key, which needs no socket at all.

All of them are reproduced with their exact error text in
[troubleshooting.md](troubleshooting.md).
