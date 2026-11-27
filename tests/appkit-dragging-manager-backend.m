// CFLAGS: -framework Foundation -framework AppKit
/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Which dragging manager the display has. Both window systems have their drag and drop run by CoreGraphics (CGSDrag.h:
// XDND on X11, the data device on Wayland), so the display's manager is AppKit's, on top of that interface.
// Usage: appkit-dragging-manager-backend (on either window system)
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
        [NSApplication sharedApplication];
        BOOL (*available)(void) = dlsym(RTLD_DEFAULT, "_CGSDragAvailable");
        expect(available != NULL, @"CoreGraphics has the drag and drop SPI");
        expect(available != NULL && available(), @"CoreGraphics runs the drags of this window system");
        NSString *manager = NSStringFromClass([[NSDraggingManager draggingManager] class]);
        NSString *wanted = @"NSCGSDraggingManager";
        expect([manager isEqualToString: wanted], [NSString stringWithFormat: @"the display's dragging manager is %@ (%@)", wanted, manager]);
        printf(failures == 0 ? "ALL PASSED\n" : "FAILED %d\n", failures);
        return failures != 0;
    }
}
