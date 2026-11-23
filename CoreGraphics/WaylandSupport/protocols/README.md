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
