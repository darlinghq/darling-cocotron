/*
 * Copyright (C) 2026 Lubos Dolezel
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
// NSQuickDrawView (32-bit only, as on macOS): the view's QuickDraw port, its
// pixels shown in the view, and QDFlushPortBuffer. Needs a display. Exit code
// 0 is success, otherwise the number of the failed check.
#import <Cocoa/Cocoa.h>
#include <stdio.h>
#include <string.h>

#ifdef __LP64__

int main(void) {
    printf("SKIP: NSQuickDrawView is 32-bit only\n");
    return 0;
}

#else

#define CHECK(n, cond) do { if (!(cond)) { printf("FAIL check %d: %s\n", n, #cond); return n; } } while (0)

static void pixelAt(NSBitmapImageRep *rep, int x, int y, int *r, int *g, int *b) {
    unsigned char *data = [rep bitmapData];
    NSInteger bytesPerPixel = [rep bitsPerPixel] / 8;
    unsigned char *p = data + y * [rep bytesPerRow] + x * bytesPerPixel;
    *r = p[0];
    *g = p[1];
    *b = p[2];
}

int main(void) {
    @autoreleasepool {
        NSApplicationLoad();
        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 40, 30)
                                                       styleMask: NSWindowStyleMaskBorderless
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        NSView *view = [[NSQuickDrawView alloc] initWithFrame: NSMakeRect(0, 0, 40, 30)];
        [window setContentView: view];
        [window orderFront: nil];
        for (int i = 0; i < 3; i++)
            [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.05]];
        [view display];

        CHECK(1, [view isFlipped]);
        void *port = [(NSQuickDrawView *) view qdPort];
        CHECK(2, port != NULL);
        CHECK(3, [(NSQuickDrawView *) view qdPort] == port);

        // The port is as large as the view, with the origin at the top left.
        Rect bounds;
        GetPortBounds(port, &bounds);
        CHECK(4, bounds.top == 0 && bounds.left == 0 && bounds.bottom == 30 && bounds.right == 40);
        PixMapHandle pixMap = GetPortPixMap(port);
        CHECK(5, pixMap != NULL && GetPixDepth(pixMap) == 32);

        // Paint the top-left quarter red (ARGB, alpha byte ignored) and flush.
        CHECK(6, LockPortBits(port) == noErr);
        unsigned char *base = (unsigned char *) GetPixBaseAddr(pixMap);
        long rowBytes = GetPixRowBytes(pixMap);
        CHECK(7, base != NULL && rowBytes >= 40 * 4);
        memset(base, 0, rowBytes * 30);
        for (int y = 0; y < 15; y++) {
            for (int x = 0; x < 20; x++) {
                unsigned char *p = base + y * rowBytes + x * 4;
                p[0] = 0;
                p[1] = 255;
                p[2] = 0;
                p[3] = 0;
            }
        }
        CHECK(8, UnlockPortBits(port) == noErr);
        QDFlushPortBuffer(port, NULL);

        NSRect rect = [view bounds];
        NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect: rect];
        [view cacheDisplayInRect: rect toBitmapImageRep: rep];
        int r, g, b;
        pixelAt(rep, 5, 5, &r, &g, &b);
        CHECK(9, r > 200 && g < 40 && b < 40);
        pixelAt(rep, 30, 20, &r, &g, &b);
        CHECK(10, !(r > 200 && g < 40 && b < 40));
        pixelAt(rep, 30, 5, &r, &g, &b);
        CHECK(11, !(r > 200 && g < 40 && b < 40));
        pixelAt(rep, 5, 20, &r, &g, &b);
        CHECK(12, !(r > 200 && g < 40 && b < 40));

        // A flush of part of the port keeps the rest of the pixels.
        RgnHandle part = NewRgn();
        SetRectRgn(part, 0, 0, 10, 10);
        QDFlushPortBuffer(port, part);
        DisposeRgn(part);
        rep = [view bitmapImageRepForCachingDisplayInRect: rect];
        [view cacheDisplayInRect: rect toBitmapImageRep: rep];
        pixelAt(rep, 15, 12, &r, &g, &b);
        CHECK(13, r > 200 && g < 40 && b < 40);

        [window orderOut: nil];
        [window release];
        [view release];
    }
    printf("PASS\n");
    return 0;
}

#endif
