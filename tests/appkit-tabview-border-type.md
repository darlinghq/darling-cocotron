Build `appkit-tabview-border-type.m` against the matching AppKit headers and
framework; run it inside a Darling prefix (`PASS` and exit 0 on success). It
needs no window server except for the last block, which renders a tab view into
a bitmap and prints `SKIP` when that is not possible.

The documentation declares `tabViewBorderType` and `tabPosition` as read-write
properties (macOS 10.12) and nothing else. The test therefore checks the
accessors exist, accept every case of both enums without raising and read them
back, on a plain tab view, on a subclass instance and on a tab view decoded
from a keyed archive. The defaults (inferred from the names of the tab view type
constants: top tabs with a bezel border for the default type, no position and a line
or no border for the no-tab types) and border type none removing the drawn border are
this implementation's choice, marked GUESS in the source; so is -setTabViewType:
taking both values again from the new type. On master the border type accessors do
not exist, so the run ends with an unrecognized-selector exception; the position
round trip already passes there.
