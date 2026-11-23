Build `appkit-datepicker-presents-calendar-overlay.m` against the matching AppKit headers and
framework; run it inside a Darling prefix (`PASS` and exit 0 on success). It needs no window
server.

The documentation declares `presentsCalendarOverlay` (macOS 10.15.4) as a read-write Boolean
property of `NSDatePicker`: whether a graphical calendar overlay is presented when a calendar
element is edited in a text-field style date picker. It states the default is `NO`. The test
checks, on a plain picker and on an application subclass whose setter wraps the superclass one
(the failing receiver in a real application was a subclass): the documented default, set/get
round trips, the value and the picker's style, elements, mode and bezel not overwriting one
another, two pickers not sharing it, and `respondsToSelector:` for both accessors.

Marked GUESS in the test: the value is independent of the picker's style. On master the
selectors do not exist: with ARC the test does not compile against master's header, without ARC
the first call raises an unrecognized-selector exception. The value is only stored: no overlay
is presented, so nothing about it appearing is tested.
