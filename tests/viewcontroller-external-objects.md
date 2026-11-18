# View controller external objects

`viewcontroller-external-objects.py DIR` writes `DIR/ViewObjectsController.archive`, a view controller archived with
`NSExternalObjectsTableForViewLoading` the way a storyboard scene's controller nib archives it (`UpstreamPlaceholder-1` is the
controller itself, `UpstreamPlaceholder-2` another object), and `DIR/ViewObjects-view.nib`, whose view reaches both
through `NSNibExternalObjectPlaceholder`.

Build `viewcontroller-external-objects.m` as a standalone Objective-C executable linked with AppKit and Foundation
using the Darling SDK, copy the fixture into the prefix, and run `viewcontroller-external-objects DIR` in a Darling
guest. It needs no display connection.

The expected result is `view controller external objects checks=6 failures=0`. A controller that is only decoded must also be deallocated: a table that retains its owner is a retain cycle. The pre-fix library ignores the table, so
loading the view raises "No object in the external name table for nib placeholder 'UpstreamPlaceholder-1'".
