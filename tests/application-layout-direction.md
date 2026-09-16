# NSApplication layout direction regression

Build `application-layout-direction.m` as a standalone Objective-C executable linked with AppKit and Foundation using the Darling SDK. Run it with the matching AppKit framework. It needs no display connection.

The test substitutes the bundle localization selection, then queries an NSApplication subclass for English, Arabic, Hebrew, Persian, Romanian, mixed localization lists in both orders, and an empty list. The original method implementation is restored before exit. The pre-fix library reports a missing selector. The expected fixed result is `layout direction checks=8 failures=0`.

This checks the application API and localization selection. It does not assert automatic RTL mirroring of views or full Terminal compatibility.
