# Third-party notices

Files kept here unmodified from other projects. Each entry names the source, the pinned commit, the copyright
and the licence.

## wlr-output-management-unstable-v1.xml

- Location: `CoreGraphics/WaylandSupport/protocols/wlr-output-management-unstable-v1.xml`
- Source: https://gitlab.freedesktop.org/wlroots/wlr-protocols (`unstable/wlr-output-management-unstable-v1.xml`)
- Commit: a5028afbe4a1cf0daf020c4104c1565a09d6e58a
- Copyright: 2019 Purism SPC
- Licence: the permission notice at the top of the file (a permissive notice allowing use, copying,
  modification, distribution and sale without fee, provided the notice is kept).

## plasma-shell.xml

- Location: `CoreGraphics/WaylandSupport/protocols/plasma-shell.xml`
- Source: https://invent.kde.org/libraries/plasma-wayland-protocols (`src/protocols/plasma-shell.xml`)
- Commit: cd65734cccdf2c60b2e446b0e6416400e697755d
- Copyright: 2013-2014 Pier Luigi Fiorini
- Licence: LGPL-2.1-or-later. The file is kept unmodified; `wayland-scanner` generates the interface tables
  from it at build time (as for the other protocol files, the generated code carries the file's notice).

## wlr-layer-shell-unstable-v1.xml

- Location: `CoreGraphics/WaylandSupport/protocols/wlr-layer-shell-unstable-v1.xml`
- Source: https://gitlab.freedesktop.org/wlroots/wlr-protocols (`unstable/wlr-layer-shell-unstable-v1.xml`)
- Commit: a5028afbe4a1cf0daf020c4104c1565a09d6e58a
- Copyright: 2017 Drew DeVault
- Licence: the permission notice at the top of the file (a permissive notice allowing use, copying,
  modification, distribution and sale without fee, provided the copyright notice is kept).

## xdg-toplevel-icon-v1.xml

- Location: `CoreGraphics/WaylandSupport/protocols/xdg-toplevel-icon-v1.xml`
- Source: https://gitlab.freedesktop.org/wayland/wayland-protocols (`staging/xdg-toplevel-icon/xdg-toplevel-icon-v1.xml`,
  wayland-protocols 1.50)
- Copyright: 2023-2024 Matthias Klumpp, 2024 David Edmundson
- Licence: MIT (the permission notice at the top of the file). The file is kept unmodified; `wayland-scanner`
  generates the interface tables from it at build time.

## DejaVuSans.ttf

- Location: `tests/fixtures/fonts/DejaVuSans.ttf`, licence text in `tests/fixtures/fonts/DejaVu-LICENSE.txt`
- Source: https://dejavu-fonts.github.io/ (DejaVu Sans 2.37, as packaged by Debian fonts-dejavu-core)
- Copyright: Bitstream, Inc. (Bitstream Vera), Tavmjong Bah, and the DejaVu contributors
- Licence: the Bitstream Vera licence with the DejaVu additions in the public domain (free to use, copy,
  embed and redistribute with the licence text; the font may not be sold by itself).
- Use: a font with identical data on every platform, so the CoreText metrics tests can compare against
  values measured on macOS.
