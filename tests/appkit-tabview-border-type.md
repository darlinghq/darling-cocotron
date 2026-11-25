Build `appkit-tabview-border-type.m` against the matching AppKit headers and
framework; run it inside a Darling prefix (`PASS` and exit 0 on success). It
needs no window server except for the last block, which renders a tab view into
a bitmap and prints `SKIP` when that is not possible.

The documentation declares `tabViewBorderType` and `tabPosition` as read-write
properties (macOS 10.12) and nothing else. The test checks that the accessors
exist, accept every case of both enums without raising and read them back, on a
plain tab view, on a subclass instance and on a tab view decoded from a keyed
archive. The remaining checks are black-box observations of macOS 26.7.3 and
Mac OS X 10.14.4 (x86_64 and i386, identical; marked QUIRK in the source): the
tab view type fixes the position and the border type, setting the position
sets the type, setting the border type sets the type of a view without tabs,
and what is drawn follows the type. On master the border type accessors do
not exist, so the run ends with an unrecognized-selector exception.
