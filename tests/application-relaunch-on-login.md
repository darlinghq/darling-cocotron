# NSApplication relaunch on login

Build `application-relaunch-on-login.m` as a standalone Objective-C executable linked with AppKit and
Foundation using the Darling SDK, and run it in a Darling guest. It needs no display connection.

`-disableRelaunchOnLogin` and `-enableRelaunchOnLogin` keep a counter: the app relaunches at login only
while every disable has been matched by an enable, and an enable with nothing to undo changes nothing.
The test checks nesting, the extra enable, and 8 threads calling both methods concurrently. It reads
the state through the private `-_relaunchesOnLogin`, because Darling has no login session that would
act on it. The pre-fix library reports missing selectors. The expected fixed result is
`relaunch on login checks=11 failures=0`.
