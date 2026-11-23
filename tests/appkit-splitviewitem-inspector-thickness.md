Build `appkit-splitviewitem-inspector-thickness.m` against the matching AppKit
headers and framework; run it inside a Darling prefix (`PASS` and exit 0 on
success). It needs no window server.

The documentation declares `minimumThickness`, `maximumThickness`,
`collapseBehavior`, `isSpringLoaded` and `allowsFullHeightLayout` as read-write
properties and `init(inspectorWithViewController:)` as a factory whose items have
the `inspector` behavior (macOS 11.0). It states the defaults: both thickness
limits are `unspecifiedDimension` (no limit), the collapse behavior is `default`,
spring loading is off, full-height layout is on. For an inspector it adds, from
macOS 14, that the item can collapse and has a minimum and maximum thickness of
270. The test therefore checks the factory result (behavior, view controller,
collapsibility, thickness), the defaults of a plain item and of a bare `-init`, the sidebar and
content list standards, a set/get round trip of every `NSSplitViewItemCollapseBehavior` case,
several thicknesses and both Boolean values, independence from one another and
from `canCollapse`, `collapsed` and `holdingPriority`, a subclass whose own setters
wrap the superclass ones (the failing receiver in a real application), items
decoded from a keyed archive, and `respondsToSelector:` for every accessor and the
factory.

Marked QUIRK in the source, black-box behaviour of macOS 26.7.3 (the sidebar and content
list values also of Mac OS X 10.14.4): the numbers of `NSSplitViewItemUnspecifiedDimension`
(-1) and `NSSplitViewItemBehaviorInspector` (3), an inspector's holding priority (261), the
sidebar's minimum thickness (140) and spring loading, the content list's minimum thickness
(200) and holding priority (255), and assigning the unspecified constant storing it (also for
an inspector). On master the factory raises an unrecognized-selector exception and the
accessors fall into the catch-all (they store nothing), so only some checks fail there; with
ARC the test does not compile against master's header. The values are only stored, so no
layout effect is tested.
