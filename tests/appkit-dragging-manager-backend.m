// CFLAGS: -framework Foundation -framework AppKit
/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Which dragging manager the display has. A window system whose drag and drop CoreGraphics runs (CGSDrag.h: X11
// today) gets AppKit's manager on top of that interface; one whose CoreGraphics backend has none (Wayland, until its
// data device drag moves down) keeps the manager of its own AppKit backend, so that its drag and drop works as before.
// Usage: appkit-dragging-manager-backend x11|wayland
// Prints PASS or FAIL lines, then ALL PASSED or FAILED n.
#import <AppKit/AppKit.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

// Not in the public headers.
@interface NSDraggingManager : NSObject
+ (id) draggingManager;
@end

static int failures;
static void expect(BOOL ok, NSString *what) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", [what UTF8String]);
    if (!ok)
        failures++;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 2) {
            printf("usage: appkit-dragging-manager-backend x11|wayland\n");
            return 2;
        }
        BOOL x11 = strcmp(argv[1], "x11") == 0;
        [NSApplication sharedApplication];
        BOOL (*available)(void) = dlsym(RTLD_DEFAULT, "_CGSDragAvailable");
        expect(available != NULL, @"CoreGraphics has the drag and drop SPI");
        expect(available != NULL && available() == x11, [NSString stringWithFormat: @"CoreGraphics runs the drags of this window system: %@", x11 ? @"yes" : @"no"]);
        NSString *manager = NSStringFromClass([[NSDraggingManager draggingManager] class]);
        NSString *wanted = x11 ? @"NSCGSDraggingManager" : @"WaylandDraggingManager";
        expect([manager isEqualToString: wanted], [NSString stringWithFormat: @"the display's dragging manager is %@ (%@)", wanted, manager]);
        printf(failures == 0 ? "ALL PASSED\n" : "FAILED %d\n", failures);
        return failures != 0;
    }
}
