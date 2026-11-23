Build `appkit-toolbar-extension-and-display-mode-flags.m` against the matching AppKit
headers and framework; run it inside a Darling prefix (`PASS` and exit 0 on success). It
needs no window server.

The documentation declares `NSToolbar.allowsDisplayModeCustomization` (macOS 15, default
YES for apps linked on macOS 15 and later), `NSToolbar.allowsExtensionItems` (macOS 10.10,
default NO) and `NSToolbarItem.isBordered` (macOS 10.15, default NO; for an item with a
custom view the value is also applied to the view's `isBordered` property if it has one)
as read-write properties; `NSMenuToolbarItem` is a toolbar item and so has the last. The
test checks, on toolbars made in code, on a subclass whose own setters wrap the superclass
ones (the failing receiver in a real application was a subclass) and on toolbars decoded
from a keyed archive: the defaults, set/get round trips of both Boolean values, the two
flags not overwriting each other nor `allowsUserCustomization`, `displayMode` and
`autosavesConfiguration`, and two toolbars not sharing values. For items (plain, menu,
subclass, decoded): the default (enabled too, for those made in code: a decoded item
without keys is disabled), round trips, independence from `tag`, `enabled`,
`autovalidates`, `label` and `showsIndicator`, a copy keeping the value, the value being
handed to a view that has `-setBordered:` (a recording view and an `NSButton`) and a view
without it being left alone; `respondsToSelector:` for all six accessors.

Marked QUIRK in the source, black-box behaviour of macOS 26.7.3: the display mode default is
YES only for a program built against the macOS 15 SDK or later (the test compares with the SDK
version of its own binary), a view set after the flag is not given the flag, an item with a view
that answers `-isBordered` answers that view's value, and a menu toolbar item is bordered until
told otherwise. On master none of the selectors exists: with ARC the test does not compile against
master's headers, without ARC the calls raise unrecognized-selector exceptions. The values
are only stored, so no effect on the toolbar or its drawing is tested. The helper classes
use plain instance variables because the legacy (i386) Objective-C runtime does not
synthesize properties.
