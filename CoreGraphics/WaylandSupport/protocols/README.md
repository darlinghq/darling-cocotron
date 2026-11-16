# Vendored Wayland protocol XML

`wlr-output-management-unstable-v1.xml` is not part of wayland-protocols (it is a wlroots protocol), so it
is kept here, byte for byte, with its copyright and permission notice.

- Source: https://gitlab.freedesktop.org/wlroots/wlr-protocols, `unstable/wlr-output-management-unstable-v1.xml`
- Commit: a5028afbe4a1cf0daf020c4104c1565a09d6e58a
- Copyright: 2019 Purism SPC
- Licence: the permission notice at the top of the file (use, copy, modify, distribute and sell without fee,
  provided the copyright and permission notice are kept; no warranty). It is permissive and compatible with
  this project's MIT licence.

It is used to generate the interface tables for the `zwlr_output_manager_v1` family, which the Wayland
backends use to change display modes on compositors that offer it (wlroots-based ones).
