# Bug report draft: OpenGL child window keeps stale contents after a resize

Ready to file at <https://bugs.winehq.org> (product Wine, component
`winex11.drv`). Everything below was measured on one machine; please reproduce
before filing so the report states facts rather than hearsay.

---

## Summary

When an application resizes an OpenGL child window, the frame it renders
immediately afterwards never reaches the screen. The area keeps its previous
contents - black, because Wine erases the parent region on a child resize - until
some later interaction produces another frame.

## Environment

- Wine 11.18, built from source with `--enable-archs=i386,x86_64`, plus the
  patch set of <https://github.com/Jabern/rhino-linux> minus patches 06, 07
  (unrelated to this; the same behaviour occurs on Fedora's stock Wine 11.0)
- Fedora 44, COSMIC 1.8, Wayland session with XWayland; also reproduced in a
  nested X server (`Xephyr`), so not compositor specific
- Mesa 26.2.3, `OpenGL renderer: SVGA3D` in a VMware guest; also reproduced with
  `LIBGL_ALWAYS_SOFTWARE=1` (llvmpipe), so not driver specific
- `GLX_OML_sync_control` present
- Application: Rhinoceros 7.38 (MFC + .NET Framework 4.8), viewports are
  OpenGL child windows

## Steps to reproduce

1. Start Rhino 7 with its default four-viewport layout.
2. Double-click a viewport tab to maximize that viewport.
3. The area the other three viewports occupied stays black.
4. Rotate the view (right-drag), or minimize and restore the window: the area
   is drawn correctly from then on.

Dragging another window across the black area does **not** repaint it.

## What the traces show

Window messages reach the application correctly (`WINEDEBUG=+message`):

```
L"Perspective" WM_ERASEBKGND  -> returned 1
L"Perspective" WM_SIZE  wp=2 (SIZE_MAXIMIZED)  lp=01df03ca  (970x479)
L"Perspective" WM_PAINT dispatched
L"Perspective" WM_PAINT returned
```

The application renders a complete frame at the new size
(`WINEDEBUG=+opengl`):

```
glViewport x 0, y 0, width 970, height 479
glClearColor 0.615686, 0.639216, 0.666667, 1.000000
glClear mask 16640
glBlitFramebuffer srcX0 0, srcY0 0, srcX1 970, srcY1 479, dstX0 0, dstY0 0, dstX1 970, dstY1 479
win32u_wglSwapBuffers context 0x7d7d26073aa0, hwnd 0x1406b8, hdc 0x5901025d, interval 1
```

Wine resizes the client window and presents with correct rectangles
(`WINEDEBUG=+win,+x11drv`):

```
client_surface_update_locked updating 0x1406b8/..., toplevel 0x1024a,
    virtual_rect (65,131)-(1035,610), monitor_rect (65,131)-(1035,610)
client_surface_update_geometry client window 0x1406b8/e01e84,
    requesting position 65,131 size 970,479 mask 0xc
win32u_wglSwapBuffers ... hwnd 0x1406b8 ... interval 1
client_surface_update_locked updating 0x1406b8/..., virtual_rect (65,131)-(1035,610)
X11DRV_client_surface_present hwnd 0x1406b8 (65,131)-(1035,610)
    to toplevel 0x1024a (65,131)-(1035,610) region 0x50040251
```

Every stage is correct - message, size, render, swap, present rectangles - and
the result is still not visible.

## Ruled out by testing

| Suspicion | Test | Result |
|---|---|---|
| GPU driver | `LIBGL_ALWAYS_SOFTWARE=1` | identical under llvmpipe |
| Compositor / XWayland | run inside `Xephyr` | identical in a plain X server |
| vsync / swap interval | `vblank_mode=0` (Mesa confirms the override) | no change |
| Covered sibling surfaces overdrawing | `DCX_CLIPSIBLINGS` on the present DC | no change; siblings present once at startup and never again |
| Stale surface rectangles | read the present rects from the trace | correct, the new size |
| Missing repaint | invalidate every client-surface window on geometry change | no change, although it fired more than a thousand times in one session |
| Asynchronous `XConfigureWindow` discarding the backing pixmap | `XSync` after a client window resize | no change |
| Missing sync in the non-OML swap path | `GLX_OML_sync_control` is present, so that path is not taken | not applicable |

## Analysis

The content the application produced does not end up in what
`X11DRV_client_surface_present` copies, for exactly one frame after the resize.
Later frames are fine, which suggests the drawable the GL context renders into
and the drawable the present reads from disagree for that one frame, rather than
a missing paint or a wrong rectangle.

Related observations that may be the same root cause:

- Dragging out a box leaves faint remnants of the preview lines.
- Maximizing the top level window used to leave a black bar on the right.

## Note for readers of this repository

This file exists because the investigation above is more useful filed upstream
than repeated. If you reproduce it on different hardware - especially on bare
metal with a Mesa driver other than SVGA3D - that is worth adding, since every
measurement so far comes from a single machine.
