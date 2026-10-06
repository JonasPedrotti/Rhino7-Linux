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

## "An error occurred trying to initialize the graphics system"

Rhino cannot create an OpenGL context. Look for the cause in the log:

```bash
rhino-7 --log
grep -iE 'err:wgl|err:opengl' ~/.cache/rhino7-linux/logs/rhino-*.log
```

**`err:wgl:internal_context_create Failed to create internal global context`**
with a self-built Wine means that Wine was compiled without OpenGL. It builds
and installs happily that way, and only fails when an application asks for a
context. Confirm it:

```bash
grep -E 'SONAME_LIBGL|SONAME_LIBEGL' ~/Rhino7-Linux/build-wine/include/config.h
```

`/* #undef ... */` on both lines is the proof. Install the development files and
rebuild from scratch:

```bash
sudo dnf install -y mesa-libGL-devel mesa-libEGL-devel libglvnd-devel
cd ~/Rhino7-Linux && rm -rf build-wine && ./install.sh --build-wine
```

`install.sh` now checks this right after `configure` and stops there instead of
compiling for an hour first. The usual root cause on Fedora is that
`dnf builddep wine` does nothing because the source repositories are disabled.

## After switching the Wine build

**`wine: failed to load ...syswow64\ntdll.dll error c0000135`.** The Wine in use
has no 32-bit support, but the prefix contains 32-bit code - the .NET Framework
installs x86 and x64 side by side. A Wine built with only `--enable-win64`
cannot start it. The build here uses `--enable-archs=i386,x86_64`; if you built
it yourself with older instructions, rebuild:

```bash
rm -rf ~/Rhino7-Linux/build-wine
./install.sh --build-wine
```

On Fedora this needs `mingw32-gcc` next to `mingw64-gcc`; `--deps` and
`dnf builddep wine` pull both.

**"An error occurred trying to initialize the graphics system" after using a
different Wine.** A prefix updated by one Wine version and then run with another
holds mismatched builtin DLLs. Refresh it with the Wine you intend to keep:

```bash
WINEPREFIX=~/.wine-rhino7 /path/to/wine wineboot -u
```

The setup does this by itself when it notices the Wine binary changed.

## Black areas after maximizing a viewport

Known and unsolved. Maximizing a viewport leaves the area the other viewports
occupied black. Anything that makes Rhino draw clears it:

- rotate or pan the view (right-drag)
- zoom
- minimize the window and restore it

An expose event does not: dragging another window across the black area leaves
it black. Rhino only paints on demand, and Wine does not deliver a paint for the
resized OpenGL child window.

Ruled out by testing, so you do not have to repeat it:

| Suspicion | Test | Result |
|---|---|---|
| GPU driver | `LIBGL_ALWAYS_SOFTWARE=1 rhino-7` | identical under llvmpipe |
| Compositor, XWayland | `Xephyr -screen 1600x900 :5 &` then `DISPLAY=:5 rhino-7` | identical in a plain X server |
| Wine too old or unpatched | patched `wine-11.18` with the full set | identical |

Patch 21 in this repository fixes the related case of a black bar on the right
when the main window is maximized, but not this one.

## Tooltips in the wrong place

Under COSMIC through XWayland, Rhino's tooltips can appear far from the cursor,
often stacked at the same position. Under a plain X server they are placed
correctly, so this is an XWayland or compositor issue rather than a Wine one.
There is no fix here yet; the tooltips are readable, just misplaced.

## The icon is wrong

`Rhino.exe` carries several icon groups - the application icon, the `.3dm`
document icon and Grasshopper. The setup takes the group with the lowest
resource id, which is the one Windows itself shows. If that still picks the
wrong one, choose by hand:

```bash
mkdir -p /tmp/ico
wrestool -x -t 14 -o /tmp/ico ~/.wine-rhino7/drive_c/Program\ Files/Rhino\ 7/System/Rhino.exe
icotool -x -o /tmp/ico /tmp/ico/*.ico
ls /tmp/ico/*.png          # look at them, pick one
RHINO_ICON=/tmp/ico/<the right one>.png ./install.sh --no-download
```

The icon file ends up at
`~/.local/share/icons/hicolor/256x256/apps/rhino7.png`. Desktop panels cache
icons, so if the dock keeps showing the old one after the file changed, unpin
and repin the entry, or log out and back in.

## Rhino starts and nothing happens

The launcher runs with `WINEDEBUG=-all`, so a silent exit looks the same as
nothing happening. Make the errors visible:

```bash
WINEDEBUG=err+all,fixme-all rhino-7
```

**`err:module:import_dll Library mfc140u.dll (which is needed by ...
RhinoCore.dll) not found`.** The Visual C++ runtime with MFC is missing. Wine
does not ship it, and Rhino's installer does not reliably deliver it inside a
prefix:

```bash
WINEPREFIX=~/.wine-rhino7 winetricks -q vcrun2019
```

The setup installs this by itself now; an older prefix needs the command above
once. Follow-up noise such as `err:ole:start_rpcss`,
`err:sync:RtlpWaitForCriticalSection ... wait timed out` and the McNeel Update
Service message are consequences of the failed load, not separate problems.

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

**The login hangs and the log shows `WebSocketSharp.WebSocketException: The
header of a frame cannot be read from the stream`.** You signed in fine in the
browser, but the socket Rhino waits on for the confirmation broke. Stale HTTP
state inside the prefix is the usual cause:

```bash
rhino-7 --stop
rhino-7 --fresh
ss -ltnp | grep 1717     # make sure nothing else holds the license port
```

Then start the sign-in again. If it keeps failing, use "Enter a license key" in
the license dialog instead: that path needs no WebSocket and is much more robust
under Wine.

**The browser does not open, or crashes.** Rhino's dialog has a
"My Browser Didn't Open..." button that shows the URL, which you can paste into
any browser by hand. A browser that crashes with a GTK or pixbuf assertion is a
host problem, not a Wine one - test it with `firefox https://www.rhino3d.com`
from a normal terminal.

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
