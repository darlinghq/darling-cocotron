Build `appkit-datepicker-presents-calendar-overlay.m` against the matching AppKit headers and
framework; run it inside a Darling prefix (`PASS` and exit 0 on success). It needs no window
server.

The documentation lists `presentsCalendarOverlay` (macOS 10.15.4) as a settable Boolean on
`NSDatePicker` that switches a pop-up calendar on for editing the calendar part of a text-field
style picker, and says it starts as `NO`. The test
checks, on a plain picker and on an application subclass whose setter wraps the superclass one
(the failing receiver in a real application was a subclass): the documented default, set/get
round trips, the value and the picker's style, elements, mode and bezel not overwriting one
another, two pickers not sharing it, and `respondsToSelector:` for both accessors.

Observed on macOS 26.7.3 (probe `p768.m` of batch 12a): the value is independent of the picker's style, mode, elements and bezel, and an archive carries it under the key `presentsCalendarOverlay`, which the test decodes. On master the
selectors do not exist: with ARC the test does not compile against master's header, without ARC
the first call raises an unrecognized-selector exception. The value is only stored: no overlay
is presented, so nothing about it appearing is tested.
