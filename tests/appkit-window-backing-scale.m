/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// NSWindow -backingScaleFactor asks the native window first and falls back to
// the screen when it reports no usable scale; the native subwindow and window
// base classes report the documented defaults. No window is shown.
#import <AppKit/AppKit.h>
#import <CoreGraphics/CGSubWindow.h>
#import <CoreGraphics/CGWindowPrivate.h>
#include <math.h>
#include <objc/runtime.h>
#include <stdio.h>

static int failures;

static void expect(BOOL condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

@interface ScaleReporter : NSObject {
@public
    CGFloat scale;
}
@end

@implementation ScaleReporter
- (CGFloat) backingScaleFactor {
    return scale;
}
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];

        CGSubWindow *sub = [[CGSubWindow alloc] init];
        expect([sub backingScaleFactor] == 1.0, "a subwindow has scale 1 by default");
        CGSize pixels = [sub drawablePixelSize];
        expect(pixels.width == 0 && pixels.height == 0, "a subwindow reports no exact pixel size by default");
        expect(![sub requiresMainThreadPresentation], "a subwindow does not require main thread presentation");
        [sub flush];
        [sub release];

        CGWindow *platform = [[CGWindow alloc] init];
        expect([platform backingScaleFactor] == 0, "a native window reports no scale by default");
        [platform release];

        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 100, 100)
                                                       styleMask: NSWindowStyleMaskTitled
                                                         backing: NSBackingStoreBuffered
                                                           defer: YES];
        Ivar ivar = class_getInstanceVariable([NSWindow class], "_platformWindow");
        expect(ivar != NULL, "NSWindow has a _platformWindow instance variable");
        if (ivar != NULL) {
            id original = object_getIvar(window, ivar);
            NSScreen *screen = [window screen];
            CGFloat screenScale = screen != nil ? [screen backingScaleFactor] : 1.0;

            ScaleReporter *native = [[ScaleReporter alloc] init];
            object_setIvar(window, ivar, native);
            const CGFloat usable[] = {1, 1.25, 1.5, 2};
            for (unsigned i = 0; i < 4; i++) {
                native->scale = usable[i];
                expect([window backingScaleFactor] == usable[i], "a usable native window scale is used");
            }
            const CGFloat unusable[] = {0, -1, NAN, INFINITY};
            for (unsigned i = 0; i < 4; i++) {
                native->scale = unusable[i];
                expect([window backingScaleFactor] == screenScale, "an unusable native scale falls back to the screen");
            }

            NSObject *noScale = [[NSObject alloc] init];
            object_setIvar(window, ivar, noScale);
            expect([window backingScaleFactor] == screenScale, "a native window without a scale uses the screen's");

            object_setIvar(window, ivar, original);
            [noScale release];
            [native release];
        }
        [window release];
    }
    if (failures == 0)
        printf("OK\n");
    return failures != 0;
}
