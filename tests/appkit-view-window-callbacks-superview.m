/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// A subview added to a view that is in a window runs -viewWillMoveToWindow:
// and -viewDidMoveToWindow: with -superview already set to the new parent.
// Removing the view clears the superview before the window callbacks run.
// Run with -p to print what was observed instead of checking it (that is how
// the expected lines were read on macOS 26.7.3 and 10.14.4).
// Prints PASS, or FAIL lines and exit status 1.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>

static NSMutableString *log_;

@interface ProbeView : NSView
@end

@implementation ProbeView
- (void) viewWillMoveToWindow: (NSWindow *) newWindow {
    [log_ appendFormat: @"willMoveToWindow(new %s) superview=%s window=%s\n", newWindow ? "set" : "nil",
        [self superview] ? "set" : "nil", [self window] ? "set" : "nil"];
}
- (void) viewDidMoveToWindow {
    [log_ appendFormat: @"didMoveToWindow superview=%s window=%s\n", [self superview] ? "set" : "nil",
        [self window] ? "set" : "nil"];
}
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        BOOL print = argc > 1 && strcmp(argv[1], "-p") == 0;
        [NSApplication sharedApplication];
        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 200, 200)
                                                       styleMask: NSWindowStyleMaskTitled
                                                         backing: NSBackingStoreBuffered
                                                           defer: YES];
        NSView *parent = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 200, 200)];
        [window setContentView: parent];
        ProbeView *child = [[ProbeView alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)];
        log_ = [NSMutableString string];

        [parent addSubview: child];
        [child removeFromSuperview];

        NSString *expected =
            @"willMoveToWindow(new set) superview=set window=nil\n"
             "didMoveToWindow superview=set window=set\n"
             "willMoveToWindow(new nil) superview=nil window=set\n"
             "didMoveToWindow superview=nil window=nil\n";
        if (print) {
            printf("%s", [log_ UTF8String]);
            return 0;
        }
        if (![log_ isEqualToString: expected]) {
            printf("FAIL: got\n%swanted\n%s", [log_ UTF8String], [expected UTF8String]);
            return 1;
        }
        puts("PASS");
    }
    return 0;
}
