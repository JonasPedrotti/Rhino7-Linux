# Wine patches for Rhino 7

The patch files in [`patches/`](../patches/) come unmodified from
[Jabern/rhino-linux](https://github.com/Jabern/rhino-linux), where they were
written for Rhino 8 and the Rhino 9 WIP. This repository keeps the subset that
is useful for **Rhino 7** and drops the rest. The original numbering is kept, so
the gaps (06, 07, 17) are intentional and make the provenance easy to check.

Rhino 7 differs from Rhino 8/9 in three ways that decide which patches matter:

| | Rhino 7 | Rhino 8 / 9 WIP |
|---|---|---|
| Managed runtime | .NET Framework 4.8 | .NET 7 / 8 / 10 (CoreCLR) |
| Viewport renderer | OpenGL 4.1 | Direct3D 11 / Vulkan through DXVK |
| Embedded browser | none | Edge WebView2 (Cloud Zoo, Package Manager, panels) |

So the WebView2 and DirectComposition work is irrelevant here, Vulkan
presentation is a side issue rather than the main path, and the UI, window and
OpenMP fixes are what actually change the Rhino 7 experience.

## Verification status

What has been checked for this repository:

- All 19 patches apply to a clean `wine-11.18` tree, individually and as a
  series in numeric order, with no rejects (`patch -p1 --dry-run` and a real
  run).
- None of the kept patches references a symbol introduced by the three dropped
  ones. Patch 04 names a `dcomp` window property as a string; without patches
  06 and 07 nothing sets that property, so the check is simply never true.

What has **not** been checked here: compiling the patched tree, and running
Rhino 7 against it. Do that on your own machine with `./install.sh --build-wine`
and report back what breaks.

## Patch sets

`install.sh --patches <set>` selects the group:

- **`core`** (14 patches): 01 02 03 04 05 08 09 10 12 14 17 19 20 21
- **`all`** (default, 18 patches): core plus licensing (13, 15) and
  Direct3D (11, 18)
- **`--wayland`** additionally applies 16, the experimental `winewayland.drv`
  patch. Do not expect Rhino 7 to be usable on the native Wayland driver; the
  supported path is XWayland.

## Core set

These address problems that show up in a plain Rhino 7 session.

| # | Subsystem | Why it matters for Rhino 7 |
|---|---|---|
| 01 | `vcomp` / `vcomp140` | Implements the 64-bit dynamic OpenMP loop functions (`_vcomp_for_dynamic_init_i8`, `_vcomp_for_dynamic_next_i8`). OpenNURBS meshing, boolean and intersection code parallelises through `vcomp140`; against the stubs in stock Wine those loops stall or hang the worker threads. |
| 02 | `ntdll` | Caps thread pool workers (64 per pool, 256 global) and enforces a 5 s idle timeout. Long modelling sessions otherwise accumulate hundreds of worker threads and run out of handles. |
| 03 | `kernelbase` | Implements `SetThreadIdealProcessorEx`, which the CLR calls when pinning threads. Stock Wine returns `ERROR_CALL_NOT_IMPLEMENTED` and floods the log. |
| 04 | `winex11.drv` | Matches 32bpp against 24bpp drawables before blitting. This is the fix for the solid black rectangles around floating toolbars, the command bar popup and translucent overlays. |
| 05 | `win32u` | Alpha blends 32bpp menu bitmaps instead of blitting them opaquely, so toolbar and context menu icons stop getting black squares around them. |
| 08 | `win32u` | Allows a backing surface for `WS_EX_LAYERED` child windows, which Rhino's dockable panels use. Without it panels fail to draw or hide behind their container. |
| 09 | `msvcp*` | Implements `?_Throw_Cpp_error@std@@YAXH@Z`. C++ plugins and Rhino's own libraries crash on the stub when they raise `std::system_error` or `std::future_error`. |
| 10 | `user32` | Adds the Per-Monitor DPI v2 dialog APIs. Rhino's Options and Document Properties dialogs call them; on mixed DPI setups the dialogs otherwise misplace their controls. |
| 12 | `wbemprox` | Aggregates a free-threaded marshaler into `IWbemServices`. Rhino's licensing and diagnostics run WMI queries from multiple COM apartments and get `E_NOINTERFACE` without it. |
| 14 | `comctl32` | Adds `TaskDialog` / `TaskDialogIndirect`. Rhino uses task dialogs for license and crash prompts, which silently vanish on the stub. |
| 17 | `user32` / `win32u` / `winex11.drv` / `server` | Compositing and restacking for owned `WS_EX_LAYERED` windows, plus unsuffixed 64-bit `GetWindowLongPtr` / `SetWindowLongPtr` exports. Upstream wrote it for the Rhino 9 splash, and this repository dropped it for that reason - wrongly: Rhino 7's tooltips and floating popups are layered windows too, and they render black without it. |
| 19 | `win32u` | Excludes child windows from monitor offset maths in `get_maximized_rect` / `get_min_max_info`. This is the fix for an MDI viewport disappearing when you double-click its tab on a secondary monitor. |
| 20 | `winex11.drv` | Anchors the XRandR primary rect at root (0,0). Wayland compositors reassign the primary output as focus moves, which otherwise shifts Wine's origin by a full monitor width and freezes the pointer. Directly relevant on COSMIC. |
| 21 | `win32u` | Written for this repository, not from upstream. After a geometry change, invalidates the windows that own an OpenGL client surface so their owner repaints. Rhino only draws on demand, so a resized viewport otherwise keeps a stale, smaller drawable and the uncovered area stays black until you rotate the view or minimize the window. Patch 18 does the same thing, but only for `SW_MAXIMIZE` and for Vulkan swapchain recreation, neither of which Rhino 7 triggers. |

## Licensing set (13, 15)

| # | Subsystem | Notes for Rhino 7 |
|---|---|---|
| 13 | `server` / `services` | Puts `services.exe` in the Session 0 namespace so service RPC and named pipes line up with desktop clients. Relevant if you use a LAN Zoo license server or keep the McNeel update service. |
| 15 | `ncrypt` | ECDSA P-256 key import and signatures, used for Cloud Zoo JWT validation. Written for the Rhino 8/9 login flow; Rhino 7 signs in through your Linux browser, so treat this as untested insurance rather than a known fix. |

## Direct3D set (11, 18)

Rhino 7 does not render viewports through Direct3D, so these only help plugins
and, in patch 18's case, repainting after a swapchain resize.

| # | Subsystem | Notes for Rhino 7 |
|---|---|---|
| 11 | `dxgi` | Maps `DXGI_FORMAT_UNKNOWN` to `B8G8R8A8_UNORM` instead of failing swapchain creation. Only reached by D3D plugins. |
| 18 | `win32u` / `winex11.drv` | Invalidates the parent MDI frame when a Vulkan swapchain is recreated, and rebinds X11 client surface DC rects. The Vulkan half needs DXVK to fire; the client surface half can still help the known Rhino 7 symptom where a viewport does not repaint until you move the mouse. |

## Dropped patches

| # | Why it is not here |
|---|---|
| 06 | DirectComposition visual tree hosting for Edge WebView2. Rhino 7 ships no WebView2 and no `dcomp` consumer. |
| 07 | Guards for hidden DirectComposition targets, same reason as 06. |

If you want the full original stack, including the dropped two, use the
upstream repository directly and point `install.sh --wine` at the Wine it builds.

## Applying by hand

```bash
git clone --depth 1 --branch wine-11.18 https://gitlab.winehq.org/wine/wine.git ~/src/wine
cd ~/src/wine

# core + licensing + Direct3D (everything except the Wayland patch)
for n in 01 02 03 04 05 08 09 10 11 12 13 14 15 18 19 20; do
    patch -p1 < /path/to/Rhino7-Linux/patches/$n-*.patch
done

mkdir -p ~/src/build-wine && cd ~/src/build-wine
~/src/wine/configure --enable-win64 --prefix="$HOME/.local/share/wine-rhino7" --without-capi
make -j"$(nproc)" && make install
```

## License

The patches follow Wine's LGPL 2.1 or later, as in the upstream repository.
