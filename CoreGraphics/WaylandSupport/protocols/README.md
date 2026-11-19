# Vendored Wayland protocol XML

The protocols here are not part of wayland-protocols, so they are kept in this tree, byte for byte, with
their copyright and permission notices.

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
