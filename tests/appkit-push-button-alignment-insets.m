// Copyright (C) 2026 Lubos Dolezel
//
// A rounded push button is laid out by its bezel: -alignmentRectInsets is the room around the bezel in the frame
// (the shadow is below it), the intrinsic size is that of the bezel, and the bezel is drawn inside the frame
// without the insets. Pins the QUIRK in NSButtonCell. Reference: macOS 10.14.4. Insets (top, left, bottom, right)
// are (4, 6, 7, 6) regular, (3, 5, 6, 5) small and (0, 1, 1, 1) mini; bezel heights 21, 18 and 15; in a frame of
// the intrinsic size plus the insets the ink of the bezel covers rows top..frame-bottom-1 and columns
// left..frame-right-1.
//
// Build: clang -fobjc-arc -framework AppKit appkit-push-button-alignment-insets.m
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <unistd.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

// Bounding box of the pixels that are not (nearly) white.
static BOOL inkBox(NSBitmapImageRep *rep, NSInteger *x0, NSInteger *x1, NSInteger *y0, NSInteger *y1) {
    *x0 = *y0 = 1 << 30; *x1 = *y1 = -1;
    for (NSInteger y = 0; y < [rep pixelsHigh]; y++)
        for (NSInteger x = 0; x < [rep pixelsWide]; x++) {
            NSColor *c = [[rep colorAtX: x y: y] colorUsingColorSpace: [NSColorSpace deviceRGBColorSpace]];
            if ([c alphaComponent] > 0.1 && ([c redComponent] < 0.97 || [c greenComponent] < 0.97 || [c blueComponent] < 0.97)) {
                if (x < *x0) *x0 = x;
                if (x > *x1) *x1 = x;
                if (y < *y0) *y0 = y;
                if (y > *y1) *y1 = y;
            }
        }
    return *x1 >= 0;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSControlSize sizes[3] = {NSControlSizeRegular, NSControlSizeSmall, NSControlSizeMini};
        CGFloat insets[3][4] = {{4, 6, 7, 6}, {3, 5, 6, 5}, {0, 1, 1, 1}};
        CGFloat bezelHeight[3] = {21, 18, 15};

        for (int k = 0; k < 3; k++) {
            NSButton *b = [[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 100, 40)];
            [b setBezelStyle: NSBezelStyleRounded];
            [b setButtonType: NSButtonTypeMomentaryPushIn];
            [b setTitle: @""];
            [[b cell] setControlSize: sizes[k]];
            [[b cell] setFont: [NSFont systemFontOfSize: [NSFont systemFontSizeForControlSize: sizes[k]]]];

            NSEdgeInsets i = [b alignmentRectInsets];
            CHECK(i.top == insets[k][0] && i.left == insets[k][1] && i.bottom == insets[k][2] && i.right == insets[k][3]);
            CHECK([b intrinsicContentSize].height == bezelHeight[k]);

            // A frame of the alignment rectangle plus the insets shows the bezel from the insets on.
            NSSize frameSize = NSMakeSize(100, bezelHeight[k] + i.top + i.bottom);
            [b setFrame: NSMakeRect(0, 0, frameSize.width, frameSize.height)];
            NSView *container = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 140, 80)];
            [container addSubview: b];
            NSWindow *w = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 140, 80)
                                                      styleMask: NSWindowStyleMaskTitled
                                                        backing: NSBackingStoreBuffered defer: NO];
            [w setContentView: container];
            NSBitmapImageRep *rep = [b bitmapImageRepForCachingDisplayInRect: [b bounds]];
            [b cacheDisplayInRect: [b bounds] toBitmapImageRep: rep];
            NSInteger x0, x1, y0, y1;
            CHECK(inkBox(rep, &x0, &x1, &y0, &y1));
            double scale = (double)[rep pixelsWide] / frameSize.width;
            fprintf(stderr, "size %d: ink x %ld..%ld y %ld..%ld of %ldx%ld\n", k, (long)x0, (long)x1, (long)y0, (long)y1,
                    (long)[rep pixelsWide], (long)[rep pixelsHigh]);
            CHECK(scale == 1);
            CHECK(x0 == i.left && x1 == frameSize.width - i.right - 1);
            // The last row is the bezel's shadow line, which may be too light to count as ink here.
            CHECK(y0 == i.top && y1 >= frameSize.height - i.bottom - 2 && y1 <= frameSize.height - i.bottom - 1);
            [w close];
        }

        // Constraints position the bezel: the frame is the alignment rectangle plus the insets.
        NSView *container = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 200, 100)];
        NSButton *b = [[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)];
        [b setBezelStyle: NSBezelStyleRounded];
        [b setButtonType: NSButtonTypeMomentaryPushIn];
        [b setTitle: @""];
        [b setTranslatesAutoresizingMaskIntoConstraints: NO];
        [container addSubview: b];
        [container addConstraints: [NSLayoutConstraint constraintsWithVisualFormat: @"H:|-20-[b]" options: 0 metrics: nil views: @{@"b": b}]];
        [container addConstraints: [NSLayoutConstraint constraintsWithVisualFormat: @"V:|-20-[b]" options: 0 metrics: nil views: @{@"b": b}]];
        [container layoutSubtreeIfNeeded];
        NSRect f = [b frame];
        // the container is not flipped: the frame is 16 below the top edge and 32 high
        CHECK(f.origin.x == 14 && f.origin.y == 100 - 16 - 32 && f.size.width == 28 + 12 && f.size.height == 21 + 11);
        fprintf(stderr, "frame %g,%g %gx%g\n", f.origin.x, f.origin.y, f.size.width, f.size.height);
        // Leave without draining the pool: releasing the views of the constraint part crashes the 32-bit
        // AppKit of macOS 10.14.4 (a bug unrelated to the behaviour tested here).
        if (!failures) printf("PASS\n");
        fflush(stdout);
        _exit(failures ? 1 : 0);
    }
}
