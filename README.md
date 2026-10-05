# Rhino 7 on Linux

Run McNeel Rhinoceros 7 under Wine, with Fedora and the COSMIC desktop as the
main targets. A Rhino 7 focused rework of
[Jabern/rhino-linux](https://github.com/Jabern/rhino-linux), which targets
Rhino 8 and 9.

## Install

```bash
git clone https://github.com/JonasPedrotti/Rhino7-Linux.git && cd Rhino7-Linux && ./install.sh --deps -y
```

This installs the distro packages, creates `~/.wine-rhino7` with .NET
Framework 4.8 and fonts, downloads the public Rhino 7.38 installer (293 MiB,
checksum verified) and installs it. Takes a while on the first run.

You need your own Rhino 7 license. Only the installer download is automated.

Variants:

```bash
./install.sh                          # ask before the download
./install.sh --installer rhino.exe    # use an installer you already have
./install.sh --no-download            # just configure the prefix
./install.sh --check                  # diagnostics
./install.sh --help
```

## Use

```bash
rhino-7              # start
rhino-7 model.3dm    # open a file
rhino-7 --fresh      # restart the prefix first, fixes stuck licensing
rhino-7 --stop
rhino-7 --log        # launch with a Wine log
```

## Patched Wine

Stock Wine runs Rhino 7, but with black borders around toolbars and menus,
panels that fail to draw, and viewports that vanish when maximized on a second
monitor. 17 Wine patches fix that:

```bash
./install.sh --build-wine
```

Installs to `~/.local/share/wine-rhino7` and leaves your system Wine alone.
Takes 20 to 60 minutes.

## Docs

- [Fedora](docs/fedora.md) - packages, GPU, ntsync, fonts
- [COSMIC](docs/cosmic.md) - tiling exception, XWayland, HiDPI
- [Patches](docs/patches.md) - what each one fixes, what was dropped
- [Troubleshooting](docs/troubleshooting.md)

## Status

The patches are verified to apply cleanly to `wine-11.18`. Building them and
running Rhino 7 against them has not been tested yet - reports welcome.

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
