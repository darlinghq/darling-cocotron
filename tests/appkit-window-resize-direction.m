/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// The private -[NSWindow _resizeDirectionForMouseLocation:] (window
// coordinates, returns NSInteger): -1 where the window cannot be resized,
// otherwise 0 right, 1 top right, 2 top, 3 top left, 4 left, 5 bottom left,
// 6 bottom, 7 bottom right. Expected values were observed on macOS at points
// well inside the edge bands and corners; the exact band widths are not
// pinned. Windows are created with defer:NO (macOS answers -1 for deferred ones); needs a display.
#import <AppKit/AppKit.h>
#import <objc/message.h>
#include <stdio.h>

static int failures;

static NSInteger dir(NSWindow *w, double x, double y) {
    return ((NSInteger (*)(id, SEL, NSPoint))objc_msgSend)(
            w, NSSelectorFromString(@"_resizeDirectionForMouseLocation:"), NSMakePoint(x, y));
}

static void expect(NSInteger got, NSInteger want, const char *what) {
    if (got != want) {
        fprintf(stderr, "FAIL: %s: got %ld, want %ld\n", what, (long) got, (long) want);
        failures++;
    }
}

static NSWindow *make(NSWindowStyleMask mask) {
    return [[NSWindow alloc] initWithContentRect: NSMakeRect(200, 200, 300, 200)
                                       styleMask: mask
                                         backing: NSBackingStoreBuffered
                                           defer: NO];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindowStyleMask titled = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable;

        for (int k = 0; k < 2; k++) {
            NSWindow *w = make(k == 0 ? titled | NSWindowStyleMaskResizable
                                      : NSWindowStyleMaskBorderless | NSWindowStyleMaskResizable);
            NSSize s = [w frame].size;
            double W = s.width, H = s.height;
            const char *n = k == 0 ? "titled resizable" : "borderless resizable";
            expect(dir(w, W / 2, H / 2), -1, n);
            expect(dir(w, 2, H / 2), 4, "left edge");
            expect(dir(w, W - 2, H / 2), 0, "right edge");
            expect(dir(w, W / 2, 2), 6, "bottom edge");
            expect(dir(w, W / 2, H - 2), 2, "top edge");
            expect(dir(w, 2, 2), 5, "bottom left corner");
            expect(dir(w, W - 2, 2), 7, "bottom right corner");
            expect(dir(w, 2, H - 2), 3, "top left corner");
            expect(dir(w, W - 2, H - 2), 1, "top right corner");
            expect(dir(w, -50, H / 2), -1, "far outside left");
            expect(dir(w, W + 50, H / 2), -1, "far outside right");
            expect(dir(w, W / 2, -50), -1, "far outside below");
            expect(dir(w, W / 2, H + 50), -1, "far outside above");
        }

        // Not resizable: -1 everywhere.
        NSWindow *fixed = make(titled);
        NSWindow *plain = make(NSWindowStyleMaskBorderless);
        NSSize s = [fixed frame].size;
        double xs[] = {2, 150, s.width - 2}, ys[] = {2, 100, s.height - 2};
        for (int i = 0; i < 3; i++)
            for (int j = 0; j < 3; j++) {
                expect(dir(fixed, xs[i], ys[j]), -1, "titled non-resizable");
                expect(dir(plain, xs[i], ys[j]), -1, "borderless non-resizable");
            }
    }
    if (failures == 0)
        printf("PASS\n");
    return failures == 0 ? 0 : 1;
}
