// Copyright (C) 2026 Lubos Dolezel
// Guest half of the XDND drop-target test: a window whose view accepts
// text/uri-list drops as NSFilenamesPboardType. Run it on the shared Xvfb, then
// run xdnd-source-driver (host side) against the same display.
// Prints "READY" once the window is mapped, "DROPPED <path>" for the dropped
// file (a host path reaches the guest below /Volumes/SystemRoot) and "OK" when
// the drop was delivered exactly once.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>

@interface DropView : NSView {
@public
    int entered, dropped, bad;
}
@end

@implementation DropView
- (NSDragOperation) draggingEntered: (id<NSDraggingInfo>) sender {
    entered++;
    return NSDragOperationCopy;
}
- (NSDragOperation) draggingUpdated: (id<NSDraggingInfo>) sender {
    return NSDragOperationCopy;
}
- (BOOL) performDragOperation: (id<NSDraggingInfo>) sender {
    NSArray *files = [[sender draggingPasteboard] propertyListForType: NSFilenamesPboardType];
    if ([files count] != 1 || ![[files objectAtIndex: 0] isEqual: @"/Volumes/SystemRoot/tmp/xdnd test file.txt"]) {
        printf("FAIL: unexpected filenames %s\n", [[files description] UTF8String]);
        bad++;
        return NO;
    }
    printf("DROPPED %s\n", [[files objectAtIndex: 0] UTF8String]);
    dropped++;
    return YES;
}
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *window = [[NSWindow alloc]
                initWithContentRect: NSMakeRect(100, 100, 300, 200)
                          styleMask: NSTitledWindowMask
                            backing: NSBackingStoreBuffered
                              defer: NO];
        DropView *view = [[DropView alloc] initWithFrame: NSMakeRect(0, 0, 300, 200)];
        [view registerForDraggedTypes: [NSArray arrayWithObject: NSFilenamesPboardType]];
        [window setContentView: view];
        [window setTitle: @"xdnd-target"];
        [window makeKeyAndOrderFront: nil];

        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: 40];
        BOOL ready = NO;
        while (view->dropped == 0 && view->bad == 0 && [deadline timeIntervalSinceNow] > 0) {
            @autoreleasepool {
                NSEvent *e = [NSApp nextEventMatchingMask: NSAnyEventMask
                                                untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]
                                                   inMode: NSDefaultRunLoopMode
                                                  dequeue: YES];
                if (e)
                    [NSApp sendEvent: e];
                if (!ready && [window isVisible]) {
                    ready = YES;
                    printf("READY\n");
                    fflush(stdout);
                }
            }
        }
        BOOL ok = view->dropped == 1 && view->bad == 0 && view->entered >= 1;
        printf(ok ? "OK\n" : "FAIL: entered=%d dropped=%d\n", view->entered, view->dropped);
        return ok ? 0 : 1;
    }
}
