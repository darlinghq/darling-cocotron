# Vendored Wayland protocol XML

The protocols here are not part of the wayland-protocols release every supported system has (or not at all), so they
are kept in this tree, byte for byte, with their copyright and permission notices.

## wlr-output-management

`wlr-output-management-unstable-v1.xml` is a wlroots protocol.

- Source: https://gitlab.freedesktop.org/wlroots/wlr-protocols, `unstable/wlr-output-management-unstable-v1.xml`
- Commit: a5028afbe4a1cf0daf020c4104c1565a09d6e58a
- Copyright: 2019 Purism SPC
- Licence: the permission notice at the top of the file (use, copy, modify, distribute and sell without fee,
  provided the copyright and permission notice are kept; no warranty). It is permissive and compatible with
  this project's MIT licence.

It is used to generate the interface tables for the `zwlr_output_manager_v1` family, which the Wayland
backends use to change display modes on compositors that offer it (wlroots-based ones).

## appmenu

`appmenu.xml` is KDE's `org_kde_kwin_appmenu_manager` protocol, which tells the compositor where on the
session bus the `com.canonical.dbusmenu` object with a window's menu is.

- Source: https://invent.kde.org/libraries/plasma-wayland-protocols, `src/protocols/appmenu.xml`
- Commit: cd65734cccdf2c60b2e446b0e6416400e697755d
- Copyright: 2017 David Edmundson
- Licence: MIT (`SPDX-License-Identifier: MIT` in the file), the same as this project.

The AppKit Wayland backend uses it to put the application's main menu in the global menu of Plasma (the
Global Menu applet and the application menu button of window title bars).

## plasma-shell

`plasma-shell.xml` is KDE's `org_kde_plasma_shell` / `org_kde_plasma_surface` protocol, kept unmodified. The AppKit
Wayland backend uses only `set_skip_taskbar` and `set_skip_switcher`, so that a toplevel that is not an application
window stays out of task lists and window switchers (xdg-shell cannot say so).

- Source: https://invent.kde.org/libraries/plasma-wayland-protocols, `src/protocols/plasma-shell.xml`
- Commit: cd65734cccdf2c60b2e446b0e6416400e697755d
- Copyright: 2013-2014 Pier Luigi Fiorini
- Licence: LGPL-2.1-or-later (`SPDX-License-Identifier` in the file). See THIRD-PARTY-NOTICES.md.
- The file warns that the protocol is a desktop-environment detail; KDE's own client libraries use these requests for
  skip-taskbar on Wayland, and KWin offers the global to ordinary clients.
- The backend checks the opcodes it uses against the generated tables at start (`WaylandCheckOpcodes`).

## wlr-layer-shell-unstable-v1.xml

Also a wlroots protocol, kept byte for byte. It is used for the application menu bar, a layer surface
anchored along the top edge.

- Source: https://gitlab.freedesktop.org/wlroots/wlr-protocols, `unstable/wlr-layer-shell-unstable-v1.xml`
- Commit: a5028afbe4a1cf0daf020c4104c1565a09d6e58a
- Copyright: 2017 Drew DeVault
- Licence: the permission notice at the top of the file (use, copy, modify, distribute and sell without fee,
  provided the copyright notice appears in all copies and supporting documentation; no warranty). It is
  permissive and compatible with this project's MIT licence.

## xdg-toplevel-icon

`xdg-toplevel-icon-v1.xml` is the staging protocol `xdg_toplevel_icon_manager_v1`, with which a client gives a
toplevel an icon from pixel buffers (or an icon name). It is in wayland-protocols from 1.34 on; the file is kept
here so that systems with an older release still build the backend.

- Source: https://gitlab.freedesktop.org/wayland/wayland-protocols, `staging/xdg-toplevel-icon/xdg-toplevel-icon-v1.xml`
  (wayland-protocols 1.50)
- Copyright: 2023-2024 Matthias Klumpp, 2024 David Edmundson
- Licence: the MIT permission notice at the top of the file.

The AppKit Wayland backend uses it to show the application icon (`-[NSApplication applicationIconImage]`) on every
toplevel, so compositors do not have to guess an icon from the `app_id`. See `WaylandToplevelIcon.m`.

## color-management

`color-management-v1.xml` is the staging `wp_color_manager_v1` family. The backends use it to describe the
colorimetry of window contents, including extended dynamic range and HDR metadata, and to observe the preferred
description of a surface and the descriptions of outputs.

- Source: https://gitlab.freedesktop.org/wayland/wayland-protocols, `staging/color-management/color-management-v1.xml`
  (wayland-protocols 1.50)
- Commit: 3eab2dccf4bfdd85c16d312a6c8c8fbc2a6e73a8
- Copyright: 2019 Sebastian Wick, 2019 Erwin Burema, 2020 AMD, 2020-2024 Collabora, Ltd., 2024 Xaver Hugl,
  2022-2025 Red Hat, Inc.
- Licence: the MIT permission notice at the top of the file.

## color-representation

`color-representation-v1.xml` is the staging `wp_color_representation_manager_v1` family. The backends use it to
declare alpha mode and YUV coefficients/range/chroma for surfaces.

- Source: https://gitlab.freedesktop.org/wayland/wayland-protocols,
  `staging/color-representation/color-representation-v1.xml` (wayland-protocols 1.50)
- Commit: 3eab2dccf4bfdd85c16d312a6c8c8fbc2a6e73a8
- Copyright: 2022 Simon Ser, 2022 Red Hat, Inc., 2022 Collabora, Ltd., 2022-2025 Red Hat, Inc.
- Licence: the MIT permission notice at the top of the file.

## xdg-session-management

`xdg-session-management-v1.xml` is the staging `xdg_session_manager_v1` protocol. The AppKit Wayland backend uses it
to connect its saved window state to a compositor-managed session, so a relaunched application can ask the compositor
to restore its toplevels.

- Source: https://gitlab.freedesktop.org/wayland/wayland-protocols,
  `staging/xdg-session-management/xdg-session-management-v1.xml` (wayland-protocols 1.50)
- Commit: 3eab2dccf4bfdd85c16d312a6c8c8fbc2a6e73a8
- Copyright: 2018 Mike Blumenkrantz, 2018 Samsung Electronics Co., Ltd, 2018 Red Hat Inc.
- Licence: the MIT permission notice at the top of the file.

## pointer-warp

`pointer-warp-v1.xml` is the staging `wp_pointer_warp_v1` protocol. The CoreGraphics Wayland backend uses it to
honour `CGWarpMouseCursorPosition()` when the compositor offers it, instead of asking for a short pointer lock.

- Source: https://gitlab.freedesktop.org/wayland/wayland-protocols, `staging/pointer-warp/pointer-warp-v1.xml`
  (wayland-protocols 1.50)
- Commit: 3eab2dccf4bfdd85c16d312a6c8c8fbc2a6e73a8
- Copyright: 2024 Neal Gompa, 2024 Xaver Hugl, 2024 Matthias Klumpp, 2024 Vlad Zahorodnii
- Licence: the MIT permission notice at the top of the file.

## cursor-shape

`cursor-shape-v1.xml` is the staging `wp_cursor_shape_manager_v1` protocol. The AppKit Wayland backend uses it
to set a themed cursor by name instead of a surface image when the compositor offers it.

- Source: https://gitlab.freedesktop.org/wayland/wayland-protocols, `staging/cursor-shape/cursor-shape-v1.xml`
  (wayland-protocols 1.50)
- Commit: 3eab2dccf4bfdd85c16d312a6c8c8fbc2a6e73a8
- Copyright: 2018 The Chromium Authors, 2023 Simon Ser
- Licence: the MIT permission notice at the top of the file.

## xdg-dialog

`xdg-dialog-v1.xml` is the staging `xdg_wm_dialog_v1` protocol. The AppKit Wayland backend uses it to tell the
compositor which toplevels are sheets or modal panels, so they can be presented as dialogs of their parent.

- Source: https://gitlab.freedesktop.org/wayland/wayland-protocols, `staging/xdg-dialog/xdg-dialog-v1.xml`
  (wayland-protocols 1.50)
- Commit: 3eab2dccf4bfdd85c16d312a6c8c8fbc2a6e73a8
- Copyright: 2023 Carlos Garnacho
- Licence: the MIT permission notice at the top of the file.

## xdg-system-bell

`xdg-system-bell-v1.xml` is the staging `xdg_system_bell_v1` protocol. It implements `NSBeep()` on Wayland,
where X11 has `XBell()` and the core protocol has no bell request.

- Source: https://gitlab.freedesktop.org/wayland/wayland-protocols,
  `staging/xdg-system-bell/xdg-system-bell-v1.xml` (wayland-protocols 1.50)
- Commit: 3eab2dccf4bfdd85c16d312a6c8c8fbc2a6e73a8
- Copyright: 2016, 2023 Red Hat
- Licence: the MIT permission notice at the top of the file.

## alpha-modifier

`alpha-modifier-v1.xml` is the staging `wp_alpha_modifier_v1` protocol. It lets the compositor apply
`NSWindow.alphaValue` to a Wayland surface, which the core protocol cannot do.

- Source: https://gitlab.freedesktop.org/wayland/wayland-protocols,
  `staging/alpha-modifier/alpha-modifier-v1.xml` (wayland-protocols 1.50)
- Commit: 3eab2dccf4bfdd85c16d312a6c8c8fbc2a6e73a8
- Copyright: 2024 Xaver Hugl
- Licence: the MIT permission notice at the top of the file.

## ext-idle-notify

`ext-idle-notify-v1.xml` is the staging `ext_idle_notifier_v1` protocol. The CoreGraphics Wayland backend uses
its idle/resumed events as the display sleep state reported by `CGDisplayIsAsleep()`.

- Source: https://gitlab.freedesktop.org/wayland/wayland-protocols,
  `staging/ext-idle-notify/ext-idle-notify-v1.xml` (wayland-protocols 1.50)
- Commit: 3eab2dccf4bfdd85c16d312a6c8c8fbc2a6e73a8
- Copyright: 2015 Martin Gräßlin, 2022 Simon Ser
- Licence: the MIT permission notice at the top of the file.

## idle-inhibit

`idle-inhibit-unstable-v1.xml` is the `zwp_idle_inhibit_manager_v1` protocol. The AppKit Wayland backend creates
an inhibitor for each visible, unoccluded toplevel so a shown window keeps the display awake.

- Source: https://gitlab.freedesktop.org/wayland/wayland-protocols,
  `unstable/idle-inhibit/idle-inhibit-unstable-v1.xml` (wayland-protocols 1.50)
- Commit: 3eab2dccf4bfdd85c16d312a6c8c8fbc2a6e73a8
- Copyright: 2015 Samsung Electronics Co., Ltd
- Licence: the MIT permission notice at the top of the file.

## xdg-toplevel-tag

`xdg-toplevel-tag-v1.xml` is the staging `xdg_toplevel_tag_manager_v1` protocol. AppKit sends a stable,
untranslated tag and the localized window title as a description for each of its toplevels, so a compositor
can remember window rules across launches.

- Source: https://gitlab.freedesktop.org/wayland/wayland-protocols,
  `staging/xdg-toplevel-tag/xdg-toplevel-tag-v1.xml` (wayland-protocols 1.50)
- Commit: 3eab2dccf4bfdd85c16d312a6c8c8fbc2a6e73a8
- Copyright: 2024 Xaver Hugl
- Licence: the MIT permission notice at the top of the file.
