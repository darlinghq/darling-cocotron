/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Setting the indentation level, tool tip or one of the state images of an
// item that is in a menu posts NSMenuDidChangeItemNotification for that menu;
// a state image only does so while it is the image for the item's state.
// Setting the target, action, tag or represented object posts nothing.
// Run with -p to print what was observed instead of checking it (that is how
// the expected lines were read on macOS 26.7.3).
// Prints PASS, or FAIL lines and exit status 1.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>

static int changes;

@interface Counter : NSObject
@end

@implementation Counter
- (void) changed: (NSNotification *) note {
    changes++;
}
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        BOOL print = argc > 1 && strcmp(argv[1], "-p") == 0;
        [NSApplication sharedApplication];
        Counter *counter = [[Counter alloc] init];
        NSMenu *menu = [[NSMenu alloc] initWithTitle: @"m"];
        NSMenuItem *item = [menu addItemWithTitle: @"a" action: NULL keyEquivalent: @""];
        NSImage *image = [[NSImage alloc] initWithSize: NSMakeSize(4, 4)];
        [[NSNotificationCenter defaultCenter] addObserver: counter
                                                 selector: @selector(changed:)
                                                     name: NSMenuDidChangeItemNotification
                                                   object: menu];
        NSMutableString *log = [NSMutableString string];
#define CHECK(label, stmt) \
    changes = 0; \
    stmt; \
    [log appendFormat: @"%s: %d\n", label, changes];
        CHECK("setIndentationLevel", [item setIndentationLevel: 1])
        CHECK("setToolTip", [item setToolTip: @"tip"])
        CHECK("setOnStateImage (state off)", [item setOnStateImage: [[NSImage alloc] initWithSize: NSMakeSize(4, 4)]])
        CHECK("setOffStateImage (state off)", [item setOffStateImage: [[NSImage alloc] initWithSize: NSMakeSize(4, 4)]])
        CHECK("setMixedStateImage (state off)", [item setMixedStateImage: [[NSImage alloc] initWithSize: NSMakeSize(4, 4)]])
        [item setState: NSControlStateValueOn];
        CHECK("setOnStateImage (state on)", [item setOnStateImage: [[NSImage alloc] initWithSize: NSMakeSize(4, 4)]])
        CHECK("setOffStateImage (state on)", [item setOffStateImage: [[NSImage alloc] initWithSize: NSMakeSize(4, 4)]])
        CHECK("setMixedStateImage (state on)", [item setMixedStateImage: [[NSImage alloc] initWithSize: NSMakeSize(4, 4)]])
        [item setState: NSControlStateValueMixed];
        CHECK("setOnStateImage (state mixed)", [item setOnStateImage: [[NSImage alloc] initWithSize: NSMakeSize(4, 4)]])
        CHECK("setOffStateImage (state mixed)", [item setOffStateImage: [[NSImage alloc] initWithSize: NSMakeSize(4, 4)]])
        CHECK("setMixedStateImage (state mixed)", [item setMixedStateImage: [[NSImage alloc] initWithSize: NSMakeSize(4, 4)]])
        CHECK("setTarget", [item setTarget: counter])
        CHECK("setAction", [item setAction: @selector(changed:)])
        CHECK("setTag", [item setTag: 3])
        CHECK("setRepresentedObject", [item setRepresentedObject: @"x"])

        if (print) {
            printf("%s", [log UTF8String]);
            return 0;
        }
        NSString *expected =
            @"setIndentationLevel: 1\n"
             "setToolTip: 1\n"
             "setOnStateImage (state off): 0\n"
             "setOffStateImage (state off): 1\n"
             "setMixedStateImage (state off): 0\n"
             "setOnStateImage (state on): 1\n"
             "setOffStateImage (state on): 0\n"
             "setMixedStateImage (state on): 0\n"
             "setOnStateImage (state mixed): 0\n"
             "setOffStateImage (state mixed): 0\n"
             "setMixedStateImage (state mixed): 1\n"
             "setTarget: 0\n"
             "setAction: 0\n"
             "setTag: 0\n"
             "setRepresentedObject: 0\n";
        if (![log isEqualToString: expected]) {
            printf("FAIL: got\n%swanted\n%s", [log UTF8String], [expected UTF8String]);
            return 1;
        }
        printf("PASS\n");
        return 0;
    }
}
