// Copyright (C) 2026 Lubos Dolezel
//
// An undo manager does not own the targets of its actions
// (https://developer.apple.com/documentation/foundation/undomanager/registerundo(withtarget:selector:object:)),
// and a window can keep the document's undo manager longer than the document lives. So an
// NSDocument removes the actions it and its window controllers registered when it goes away, and
// the actions of a window controller when that is removed from it, and the document does the same
// with the manager it stops using. This file passes with any NSUndoManager; the document going
// away is in appkit-document-undo-actions-at-dealloc.m, which needs the non-retaining
// registerUndoWithTarget:selector:object: of darling-foundation.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
static int documentRuns, controllerRuns;

static void expect(BOOL condition, const char *what) {
    printf("%s: %s\n", condition ? "PASS" : "FAIL", what);
    if (!condition)
        failures++;
}

@interface ProbeDocument : NSDocument
- (void)note:(id)ignored;
@end

@implementation ProbeDocument
- (void)note:(id)ignored { documentRuns++; }
@end

@interface ProbeController : NSWindowController
- (void)note:(id)ignored;
@end

@implementation ProbeController
- (void)note:(id)ignored { controllerRuns++; }
@end

int main(void) {
    @autoreleasepool {
        /* a window controller removed from the document takes its actions with it */
        ProbeDocument *doc = [[ProbeDocument alloc] init];
        NSUndoManager *manager = [[doc undoManager] retain];
        ProbeController *controller = [[ProbeController alloc] initWithWindow:nil];
        [doc addWindowController:controller];
        [manager registerUndoWithTarget:doc selector:@selector(note:) object:nil];
        [manager registerUndoWithTarget:controller selector:@selector(note:) object:nil];
        [doc removeWindowController:controller];
        [controller release];
        [manager endUndoGrouping];
        [manager undo];
        expect(documentRuns == 1, "the document's own action stays");
        expect(controllerRuns == 0, "the removed window controller's action is gone");

        /* replacing the undo manager takes the document's and its controllers' actions out of the
           old one, which a window may still hold; setting the same manager again changes nothing */
        [manager beginUndoGrouping];
        controller = [[ProbeController alloc] initWithWindow:nil];
        [doc addWindowController:controller];
        [manager registerUndoWithTarget:doc selector:@selector(note:) object:nil];
        [manager registerUndoWithTarget:controller selector:@selector(note:) object:nil];
        [doc setUndoManager:manager];
        expect([manager canUndo], "setting the same manager keeps its actions");
        NSUndoManager *replacement = [[NSUndoManager alloc] init];
        [doc setUndoManager:replacement];
        expect(![manager canUndo], "the old manager has no action of the document or its controller left");
        [doc removeWindowController:controller];
        [controller release];

        /* so does turning the undo manager off */
        [replacement beginUndoGrouping];
        [replacement registerUndoWithTarget:doc selector:@selector(note:) object:nil];
        [doc setHasUndoManager:NO];
        expect(![replacement canUndo] && [doc undoManager] == nil, "setHasUndoManager:NO empties the manager it drops");
        [replacement release];
        [manager release];
        [doc release];
    }
    return failures;
}
