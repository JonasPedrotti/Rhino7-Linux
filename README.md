# Rhino 7 on Linux

Run McNeel Rhinoceros 7 under Wine, with Fedora and the COSMIC desktop as the
main targets. A Rhino 7 focused rework of
[Jabern/rhino-linux](https://github.com/Jabern/rhino-linux), which targets
Rhino 8 and 9.

## Step 1: install

```bash
git clone https://github.com/JonasPedrotti/Rhino7-Linux.git && cd Rhino7-Linux && ./install.sh --deps -y
```

This will take 30 to 60 minutes on the first run.

You need your own Rhino 7 license.

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
broken application.

17 Wine patches fix that. They are built into a private Wine installation:

```bash
./install.sh --build-wine
```

Expect 20 to 60 minutes of compiling and about 10 GB of free space.

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

Tested on Fedora 44 with COSMIC 1.8, in a VMware guest: the setup installs,
Rhino 7.38 starts, Cloud Zoo licensing completes, and modelling works.

**The repaint problem is not solved.** When a viewport is maximized, the area of
the other viewports stays black until something makes Rhino draw again - rotating
the view, or minimizing and restoring the window. The patched build fixes the
black bar on the right when the main window is maximized, but not this.

What was ruled out by testing, so nobody repeats it:

- Not the GPU driver: identical with `LIBGL_ALWAYS_SOFTWARE=1` (llvmpipe).
- Not the compositor: identical in a nested X server (`Xephyr`), without
  XWayland or COSMIC involved.
- Not a missing expose: dragging another window across the black area does not
  repaint it, while anything that makes Rhino itself draw does.

What is left is Wine's handling of OpenGL child windows, which it renders into an
offscreen drawable and blits back. The community recipe this repository builds on
records the same symptom as unsolved. Tooltip mispositioning, by contrast, is
XWayland/COSMIC specific: tooltips sit correctly under a plain X server.

The patches are verified to apply cleanly to `wine-11.18`. Every failure
encountered so far, with its fix where one exists, is in
[docs/troubleshooting.md](docs/troubleshooting.md). Reports welcome, especially
from real hardware and from other desktops.

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
