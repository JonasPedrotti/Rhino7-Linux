# Rhino 7 on Linux

Run McNeel Rhinoceros 7 under Wine, with Fedora and the COSMIC desktop as the
main targets. A Rhino 7 focused rework of
[Jabern/rhino-linux](https://github.com/Jabern/rhino-linux), which targets
Rhino 8 and 9.

## Step 1: install

```bash
git clone https://github.com/JonasPedrotti/Rhino7-Linux.git && cd Rhino7-Linux && ./install.sh --deps -y
```

One command, from nothing to a clickable icon: distro packages, a prefix at
`~/.wine-rhino7` with .NET Framework 4.8, the Visual C++ runtime and fonts, the
public Rhino 7.38 installer (293 MiB, checksum verified), then a menu entry,
`.3dm` file association and, on COSMIC, a pinned dock icon and a floating window
rule. 30 to 60 minutes on the first run; it tells you where it is the whole time.

You need your own Rhino 7 license. Only the installer download is automated.

Variants:

```bash
./install.sh                          # ask before the download
./install.sh --installer rhino.exe    # use an installer you already have
./install.sh --no-download            # just configure the prefix
./install.sh --check                  # diagnostics
./install.sh --help
```

## Step 2: the patched Wine

Do not skip this one. On stock Wine, Rhino 7 starts and then behaves like a
broken application:

- Maximizing a viewport leaves the area of the other viewports solid black until
  you move something, because Rhino only repaints on demand and Wine never asks
  it to.
- Toolbars, menus and the command bar popup get black boxes around them.
- Dockable panels fail to draw.
- A viewport maximized on a second monitor disappears off-screen.

17 Wine patches fix that. They are built into a private Wine installation:

```bash
./install.sh --build-wine
```

This installs the build dependencies, clones `wine-11.18`, applies the patches
and installs to `~/.local/share/wine-rhino7`. Your system Wine is untouched, and
the launcher switches over on its own. Expect 20 to 60 minutes of compiling and
about 10 GB of free space.

Watch for `OpenGL support: present` a few seconds in. Wine compiles happily
without OpenGL and then cannot create a context, which Rhino reports as "An
error occurred trying to initialize the graphics system" - the build stops right
there if the development files are missing instead of wasting an hour.

## Use

```bash
rhino-7              # start
rhino-7 model.3dm    # open a file
rhino-7 --fresh      # restart the prefix first, fixes stuck licensing
rhino-7 --stop
rhino-7 --log        # launch with a Wine log
```

## Docs

- [Fedora](docs/fedora.md) - packages, GPU, ntsync, fonts
- [COSMIC](docs/cosmic.md) - dock icon, tiling exception, XWayland, HiDPI
- [Patches](docs/patches.md) - what each one fixes, what was dropped
- [Troubleshooting](docs/troubleshooting.md) - every error seen so far and its fix
- [Porting](docs/porting.md) - other Rhino versions, distributions and desktops

## Status

Tested on Fedora 43 with COSMIC: the setup installs, Rhino 7.38 starts, Cloud
Zoo licensing completes and the viewports render. On stock Wine the repaint
problems described above are present, which is what the patch set is for.

Not yet confirmed: that the patched build removes them. The patches are verified
to apply cleanly to `wine-11.18`, and every failure encountered so far is in
[docs/troubleshooting.md](docs/troubleshooting.md). Reports welcome.

## Credits

[Jabern/rhino-linux](https://github.com/Jabern/rhino-linux) for the patch stack,
[ItHasLegs/rhino8-wine](https://github.com/ItHasLegs/rhino8-wine) for the
wineserver restart idea, and the community Rhino 7 on Wine notes behind the
.NET 4.8 and font requirements.

Rhinoceros is a product of Robert McNeel & Associates. This project is
unaffiliated, ships no McNeel software, and Wine is not a configuration McNeel
supports.

## License

Patches are LGPL 2.1+ like Wine. Scripts, configs and docs are MIT.
