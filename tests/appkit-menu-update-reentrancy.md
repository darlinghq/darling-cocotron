Build `appkit-menu-update-reentrancy.m` against the matching AppKit headers and framework without ARC; run
it inside a Darling prefix (`PASS` and exit 0 on success). It needs no window server and no `NSApplication`:
every item has no action, so validation does not look for a target.

The documentation says the delegate's `-menuNeedsUpdate:` is sent just before a menu is shown, when
tracking begins, that the delegate may change the menu there, that validation follows it, and that `-update`
validates the items. It says nothing about a delegate that updates the menu it was asked to update, or about two menus
whose delegates update each other. The test pins the behaviour chosen for that gap (a GUESS): while a menu is
waiting for its delegate, a nested update of the same menu does not send `-menuNeedsUpdate:` again, and
another menu is not held back by it.

Every delegate counts its depth and gives up beyond 6, so a framework that does recurse fails the checks
instead of overflowing the stack. The checks, with the sequence of delegate calls that must be seen:

- a normal update: one call, not nested; a later update after a nested one: one call
- the delegate updates its own menu: one call, depth 1 (master: 6 calls, the depth limit is hit)
- the delegate removes an item, adds one and updates: one call, and the changes stay (master: 6 calls)
- the delegate removes and adds without an update: one call (the same on master)
- the delegate updates and then raises: the exception reaches the caller of `-update`, one call, and the
  next update asks the delegate again, which shows the guard was cleared (master: 6 calls)
- two menus whose delegates update each other, started from either: A then B, depth 2 (master: the limit)
- a delegate that updates another menu: that menu's delegate is asked once (the same on master)
- a submenu whose delegate updates it: asked once; a parent whose delegate updates its submenu: the
  submenu is asked for that and again for the update of the submenus (the second the same on master)
- a copy made inside the delegate and updated there: the copy's delegate is asked (the same on master)

Limits of the guard: it bounds the recursion through the delegate only. Recursion through validation is
unchanged and still unbounded (a target's `-validateMenuItem:` that calls `[menu update]` recurses, on master
and on this branch alike); a guard over the whole of `-update` would be a different design that turns a nested
`[menu update]` into a no-op. A side effect of the nested update running the submenu loop: each submenu's
delegate is asked twice per top-level update (once nested, once by the outer loop), and on the tracking path
(which updates the menu without its submenus) the submenus are updated eagerly, before they open.

Not tested: that the nested update still validates the items and updates the submenus (validation needs an
`NSApplication` to find a target; the nested update's remaining steps are a GUESS), and a delegate that
releases its menu while updating. The depth limit makes the failing cases on master report counts instead
of crashing; the same input to a real application overflows the stack.
