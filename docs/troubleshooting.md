# Troubleshooting Rhino 7 under Wine

Start with diagnostics:

```bash
./install.sh --check
rhino-7 --log            # writes ~/.cache/rhino7-linux/logs/rhino-<timestamp>.log
```

## Downloading the installer

`install.sh` fetches Rhino 7.38 from
`https://files.mcneel.com/dujour/exe/20241203/rhino_en-us_7.38.24338.17001.exe`
into `~/.cache/rhino7-linux` and verifies its SHA-256
(`d400fa02ad908d781e5f9864d960aeef2d0f3b5f86d9f42c24ba003435de7516`,
307454376 bytes).

**Checksum mismatch.** Either the download was truncated, or McNeel replaced the
file. Delete the cached copy and retry; the download resumes rather than
restarting. If the file was legitimately replaced by a newer service release,
download it yourself and use `--installer`, or pass the new URL with
`--installer-url`. The script refuses to run an installer whose checksum does not
match, which is the point.

**404 or a dead link.** McNeel rotates the `dujour` paths. Get the current
Rhino 7 download from your McNeel account and pass it with `--installer`.

## The Rhino installer

**`Installer exited with code 126` and `err:module:import_dll Library
gdiplus.dll ... not found`.** A DLL override forces `gdiplus` to `native` while
no native `gdiplus.dll` exists in the prefix. Wine then refuses to fall back to
its builtin, and the installer's own UI (`BundleUI.dll`) cannot load. Repair the
prefix by rerunning the setup, which now removes a bad override:

```bash
git pull && ./install.sh -y
```

Or do it by hand:

```bash
WINEPREFIX=~/.wine-rhino7 wine reg delete 'HKCU\Software\Wine\DllOverrides' /v gdiplus /f
WINEPREFIX=~/.wine-rhino7 wine reg delete 'HKCU\Software\Wine\AppDefaults\Rhino.exe\DllOverrides' /v gdiplus /f
```

The same applies to any other library set to plain `native`: use
`native,builtin` unless you are certain the native DLL is really there.

## .NET Framework 4.8

**It sits at `ndp48-x86-x64-allos-enu.exe /sfxlang:1027 /q /norestart` and nothing
happens.** That is the real .NET 4.8 installer, and under Wine it runs 15 to 40
minutes without printing a single line. It is almost certainly working. Check
from a second terminal:

```bash
ps -eo pid,etime,pcpu,args | grep -iE 'ndp48|mscorsvw|ngen\.exe' | grep -v grep
```

CPU above zero means it is still working - wait. Only if it stays at 0.0 for
several minutes is it genuinely stuck.

**It is stuck at the end.** The .NET setup starts the NGen service
(`mscorsvw.exe`) to precompile assemblies, and that service regularly never
exits under Wine, so the install never returns even though the framework is
already in place. Check and recover:

```bash
ls ~/.wine-rhino7/drive_c/windows/Microsoft.NET/Framework64/v4.0.30319/clr.dll
```

If `clr.dll` is there, .NET is installed and only the service is hanging:

```bash
pkill -f mscorsvw; pkill -f 'ngen\.exe'
WINEPREFIX=~/.wine-rhino7 wineserver -k
./install.sh --skip-dotnet
```

`deploy-rhino7.sh` does this cleanup by itself, prints a progress line every
minute, and stops winetricks after 45 minutes
(`RHINO_DOTNET_TIMEOUT_MIN` changes that limit).

**The Rhino installer aborts with `rhino.msi:-2147023293`.**
The .NET Framework was not really installed. Check it:

```bash
ls ~/.wine-rhino7/drive_c/windows/Microsoft.NET/Framework64/v4.0.30319/clr.dll
```

If that file is missing:

1. Make sure 32-bit Wine is present (`rpm -q wine-core` must list an `i686`
   build on Fedora). The 4.8 installer writes both architectures and fails
   silently part way through without it.
2. Make sure `cabextract` is installed.
3. Reinstall into a clean prefix. A prefix where `dotnet48` failed once is
   usually not worth repairing:

```bash
rm -rf ~/.wine-rhino7
./install.sh
```

4. If it keeps failing, run it by hand to see the real error:

```bash
WINEPREFIX=~/.wine-rhino7 winetricks -f dotnet48
```

**Rhino starts but every .NET dialog is broken.** Wine Mono is being used
instead of the framework. Confirm the override:

```bash
rhino-7 --winecfg     # Libraries tab: mscoree must be listed as "native"
```

## Startup

**Rhino exits immediately, with font related noise in the log.** Missing fonts
are the most frequent cause of Rhino 7 dying on Wine. Verify Arial:

```bash
ls ~/.wine-rhino7/drive_c/windows/Fonts/arial.ttf
```

Rerun `tools/deploy-rhino7.sh` if it is absent, and see the font section in
[fedora.md](fedora.md).

**`error: DISPLAY is empty`.** You are on a Wayland session without XWayland.
Enable it, or set `RHINO_GRAPHICS_DRIVER=wayland` to try the native driver (not
recommended, see [cosmic.md](cosmic.md)).

**The license dialog appears on every start.** Wine's `http.sys` state can go
stale between runs. Restart the prefix first:

```bash
rhino-7 --fresh
```

## Licensing

Rhino 7 signs in to Cloud Zoo by opening your Linux default browser. Two things
break that:

- A host `LD_PRELOAD` (jemalloc, gamemode, overlay injectors) kills the browser
  process Wine spawns. `rhino-7` clears `LD_PRELOAD` for this reason.
- `xdg-open` must resolve to a working browser. Test it with
  `xdg-open https://www.rhino3d.com` from the same shell you launch Rhino from.

The local license service listens on TCP port 1717. If something else on the
machine holds that port, validation fails.

For a LAN Zoo server, install `samba-winbind-clients` so Wine has `ntlm_auth`,
and consider the licensing patches (13, 15) described in
[patches.md](patches.md).

## Viewport and display

**A viewport stays black until you move the mouse.** Rhino only repaints on
demand, and Wine does not always dispatch `WM_PAINT` after the drawing surface is
resized. Patch 18 addresses the swapchain case. On an unpatched Wine, rotating or
zooming forces the redraw. This was a known Rhino 7 on Wine symptom before the
patch set existed.

**Black rectangles around toolbars, menus or the command bar popup.** This is the
32bpp vs 24bpp depth mismatch. Patches 04 and 05 fix it; they are in the `core`
set, so build the patched Wine:

```bash
./install.sh --build-wine
```

**A maximized viewport disappears on a secondary monitor.** Patch 19.

**Everything renders in software and the viewport crawls.** Check the OpenGL
core profile version:

```bash
glxinfo -B | grep 'Max core profile'
```

Below 4.1 means your driver is the problem, not Wine. On a driver that
underreports, you can try `RHINO_GL_OVERRIDE=4.1 rhino-7`, but if the hardware
genuinely cannot do 4.1 there is nothing to fix.

## Input and windows

**Clicks on toolbar buttons do nothing.** A long-standing Rhino 7 on Wine
annoyance; pressing Space instead of clicking the toolbar entry is the usual
workaround. Patches 04, 05 and 08 improve popup and panel handling, which helps,
but do not assume it is fully solved.

**Focus or click-through problems under a Wayland compositor.** Try disabling
Wine's take-focus protocol for this prefix:

```bash
WINEPREFIX=~/.wine-rhino7 wine reg add 'HKCU\Software\Wine\X11 Driver' \
    /v UseTakeFocus /d N /f
```

This is not applied by default because it can also prevent windows from taking
focus when they should. Remove the value to revert.

**Pointer offset by a monitor width after switching focus between displays.**
Patch 20, see [cosmic.md](cosmic.md).

## Performance

- `OMP_WAIT_POLICY=PASSIVE` is set by the launcher so idle OpenMP workers do not
  spin at 100% CPU. Set `OMP_WAIT_POLICY=ACTIVE` if you prefer throughput over a
  quiet machine during long solves.
- Enable `/dev/ntsync`, see [fedora.md](fedora.md).
- Patch 02 caps thread pool workers. Without it, a long session can exhaust
  handles; `ls /proc/$(pgrep -f Rhino.exe | head -1)/task | wc -l` tells you how
  many threads Rhino currently holds.

## Reporting something

Useful to include: Fedora version, `wine --version`, whether the Wine is patched
and with which set, desktop session (`echo $XDG_CURRENT_DESKTOP $XDG_SESSION_TYPE`),
`glxinfo -B` output, and the tail of `rhino-7 --log`.
