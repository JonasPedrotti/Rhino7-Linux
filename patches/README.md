# Wine patches

17 patches for X11 / XWayland plus one optional patch for the native Wayland
driver, carried unmodified from
[Jabern/rhino-linux](https://github.com/Jabern/rhino-linux) and reduced to the
subset that matters for **Rhino 7**. Upstream numbering is preserved; 06, 07 and
17 are deliberately absent because they only serve Rhino 8/9 (Edge WebView2,
DirectComposition, the `RhinoGreet` splash).

Verified to apply cleanly to `wine-11.18`, individually and as a series. All but
patch 21 are carried unmodified from upstream; 21 was written here.

| # | File | Component | Group |
|---|---|---|---|
| 01 | `01-vcomp-dynamic-init-next-i8.patch` | `vcomp140` | core |
| 02 | `02-ntdll-threadpool-worker-leak.patch` | `ntdll` | core |
| 03 | `03-set-thread-ideal-processor-ex.patch` | `kernelbase` | core |
| 04 | `04-wine-x11-layered-and-depth-match.patch` | `winex11.drv` | core |
| 05 | `05-wine-menu-alpha-blend.patch` | `win32u` | core |
| 08 | `08-wine-layered-child-windows.patch` | `win32u` | core |
| 09 | `09-wine-msvcp-throw-cpp-error.patch` | `msvcp*` | core |
| 10 | `10-wine-user32-dialog-dpi-behavior.patch` | `user32` | core |
| 11 | `11-wine-dxgi-unknown-swapchain-format.patch` | `dxgi` | d3d |
| 12 | `12-wbemprox-iwbemservices-marshal.patch` | `wbemprox` | core |
| 13 | `13-wine-services-session0.patch` | `services` | licensing |
| 14 | `14-wine-comctl32-taskdialog.patch` | `comctl32` | core |
| 15 | `15-wine-ncrypt-ecdsa-p256.patch` | `ncrypt` | licensing |
| 16 | `16-winewayland-popups-and-overlays.patch` | `winewayland.drv` | wayland (opt-in) |
| 18 | `18-x11-client-surface-repaint.patch` | `win32u` / `winex11.drv` | d3d |
| 19 | `19-wine-multimonitor-child-maximize.patch` | `win32u` | core |
| 20 | `20-wine-xrandr-primary-anchor.patch` | `winex11.drv` | core |
| 21 | `21-win32u-invalidate-client-surface-on-resize.patch` | `win32u` | core (this repo) |

What each one fixes, and why it is in that group, is in
[../docs/patches.md](../docs/patches.md).

Patches are LGPL 2.1 or later, like Wine itself.
