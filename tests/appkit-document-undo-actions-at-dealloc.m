// Copyright (C) 2026 Lubos Dolezel
//
// A document that goes away takes the undo actions of itself and of its window controllers out of
// its undo manager, which a window can keep alive longer than the document. Needs the
// non-retaining registerUndoWithTarget:selector:object: of darling-foundation (an undo manager
// does not own the targets of its actions:
// https://developer.apple.com/documentation/foundation/undomanager/registerundo(withtarget:selector:object:) ):
// with a manager that retains its targets, the registered actions keep the document alive and
// -dealloc never runs, so the last check fails there.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
static BOOL documentDeallocated;

static void expect(BOOL condition, const char *what) {
    printf("%s: %s\n", condition ? "PASS" : "FAIL", what);
    if (!condition)
        failures++;
}

@interface ProbeDocument : NSDocument
- (void)note:(id)ignored;
@end

@implementation ProbeDocument
- (void)note:(id)ignored {}
- (void)dealloc {
    documentDeallocated = YES;
    [super dealloc];
}
@end

@interface ProbeController : NSWindowController
- (void)note:(id)ignored;
@end

@implementation ProbeController
- (void)note:(id)ignored {}
@end

int main(void) {
    @autoreleasepool {
        ProbeDocument *doc = [[ProbeDocument alloc] init];
        NSUndoManager *manager = [[doc undoManager] retain];
        ProbeController *controller = [[ProbeController alloc] initWithWindow:nil];
        [doc addWindowController:controller];
        [controller release];
        [manager registerUndoWithTarget:doc selector:@selector(note:) object:nil];
        [manager registerUndoWithTarget:[[doc windowControllers] objectAtIndex:0] selector:@selector(note:) object:nil];
        expect([manager canUndo], "actions are registered");
        [doc release];
        expect(documentDeallocated, "the manager does not keep the document alive");
        expect(![manager canUndo], "no action of the dead document or its controller is left in a manager that outlives it");
        [manager release];
    }
    return failures;
}
