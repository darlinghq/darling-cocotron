Build `appkit-window-accessibility-document.m` against the matching AppKit headers and
framework; run it inside a Darling prefix (`PASS` and exit 0 on success). It needs no window
server (the windows are never ordered in).

The documentation declares `accessibilityDocument` (macOS 10.10) as a `copy`, nullable
`NSString` property of the `NSAccessibility` protocol, "the URL for the file that the
accessibility element represents" (the setter: "sets the URL for the file ..."), with no
default and no further description. `NSWindow` conforms to the protocol. The test checks, on a
plain window, an application subclass whose setter wraps the superclass one (the failing
receiver in a real application was a subclass), a view, a menu item and an
`NSAccessibilityElement`: the default, set/get, replacement, an empty string, `nil`, the value
and the element's other accessibility state (identifier, help, placeholder value) not
overwriting one another, two windows not sharing it, the window's title not standing in for it,
and `respondsToSelector:` and protocol conformance on `NSWindow`.

Marked GUESS in the source: the default is `nil`; `nil` is accepted and reads back as `nil`;
the string is not parsed or checked as a URL. On master the selectors do not exist: with ARC
the test does not compile against master's header, without ARC the first call raises an
unrecognized-selector exception. The value is only stored: it has no effect on the
accessibility tree, and neither the `copy` semantics nor the attribute-based reading
(`accessibilityAttributeValue:` with the document attribute) are tested.
