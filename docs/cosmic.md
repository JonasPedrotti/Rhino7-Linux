# Rhino 7 on the COSMIC desktop

COSMIC (`cosmic-comp`, System76's Wayland compositor) runs Rhino 7 through
XWayland. Two of its traits need attention: it can auto-tile windows, and it
reassigns the primary output as focus moves between monitors. Both have concrete
fixes.

## 1. Run through XWayland, not winewayland

The prefix is configured with `HKCU\Software\Wine\Drivers` `Graphics = x11`, and
`rhino-7` refuses to start if `DISPLAY` is empty. That is deliberate: Rhino 7 is
an MFC application with MDI viewport children, floating toolbars and owner drawn
popup toolbars, and `winewayland.drv` does not implement enough of that yet. The
optional patch 16 improves Wayland popups, but it does not make the native driver
a sensible choice for Rhino.

If you want to experiment anyway:

```bash
RHINO_GRAPHICS_DRIVER=wayland WINEDLLOVERRIDES="winex11.drv=d" rhino-7
```

Expect misplaced popups. Report findings rather than relying on it.

## 2. Keep Rhino windows floating

CAD software assumes floating windows. Under auto-tiling, Rhino's middle-click
popup toolbar opens as a tiled column, dialogs grab half the screen, and a
viewport squeezed into a narrow column keeps reallocating its drawing surface.

COSMIC's tiling mode is per workspace, so the simplest approach is to give Rhino
its own floating workspace. For a permanent rule, add an auto-tiling exception:

```bash
./install.sh --cosmic-rules
```

or write the file yourself:

`~/.config/cosmic/com.system76.CosmicSettings.WindowRules/v1/tiling_exception_custom`

```ron
[
  (
    enabled: true,
    appid: "rhino.exe",
    title: "",
  ),
]
```

COSMIC applies the file as soon as it is saved; no logout is needed. If the file
already exists, add the entry to the existing list by hand - `install.sh` will
not rewrite a list you already maintain, it only prints the line to insert.

Two details that are easy to get wrong, both read out of the `cosmic-comp`
source (`src/shell/layout/mod.rs`):

- `appid` and `title` are **regular expressions**, matched unanchored, and a
  window floats only when both patterns match it. An empty `title` therefore
  means "any title", which is what you want for Rhino; leaving it out or
  guessing a title would restrict the rule to one window.
- `appid` for an XWayland window is its X11 `WM_CLASS`. Wine sets both
  `res_name` and `res_class` to the **lowercased** executable name, so Rhino's
  windows are `rhino.exe`, not `Rhino.exe`. Since the match is a case sensitive
  regex, the case matters.

Check it on your own machine with:

```bash
xprop WM_CLASS      # then click a Rhino window
```

Per window, you can also toggle floating with **Super + G**, or through
"Float window" in the window's title bar menu.

## 3. Multi-monitor: the primary output problem

COSMIC changes which output XWayland reports as the XRandR primary as focus
moves. Stock Wine takes the primary output's position as the origin of its
virtual desktop, so when the primary switches, every existing window and the
pointer mapping shift by a full monitor width. The symptom is a Rhino window that
stops responding to the mouse, or clicks landing a screen away from the cursor.

Patch 20 pins the primary rect to root (0,0) and makes the mapping stable. It is
in the `core` set, so it is applied by any `./install.sh --build-wine` run. On an
unpatched system Wine, the workaround is to keep Rhino on one monitor and avoid
moving focus across outputs while it is open.

Patch 19 is the related fix for maximizing a viewport (double-clicking its tab)
while the Rhino window sits on a secondary display.

## 4. HiDPI and fractional scaling

XWayland applications are rendered at integer scale and then resampled, so at
125% or 150% display scaling Rhino looks soft. Crisper approach:

1. Set the COSMIC display scale to 100% (or 200% on a true HiDPI panel).
2. Scale Rhino itself inside Wine instead:

```bash
rhino-7 --winecfg     # Graphics tab, "Screen resolution" DPI, e.g. 120 or 144
```

Wine then renders the UI at that DPI natively and nothing is resampled. Rhino 7
honours the Wine DPI setting for its toolbars, panels and dialogs.

COSMIC also exposes an XWayland scaling preference in its display settings; if
you prefer to leave Wine at 96 DPI, use that instead - but do not scale in both
places at once.

## 5. Focus behaviour

If you have enabled focus-follows-cursor in COSMIC, Rhino's floating palettes and
its command line can steal focus while you are moving the pointer across them,
which drops keystrokes mid-command. Click-to-focus is the safer setting for CAD
work.

## 6. What to expect

This repository's COSMIC specifics (the tiling exception path, the XWayland
requirement, the DPI advice) follow from how `cosmic-comp` works and from the two
patches above. The patch set itself has not been validated on a COSMIC session as
part of this repository - that verification is still open. If you run it, the
things worth reporting are: middle-click popup placement, viewport maximizing
across monitors, and whether the pointer stays aligned after moving focus between
outputs.
