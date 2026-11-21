// Copyright (C) 2026 Lubos Dolezel
//
// The filled part of a determinate NSProgressIndicator bar is as wide as on macOS 10.14: nothing for tiny
// fractions, the whole bar at the maximum and no thin sliver. Expected values: the number of blue columns in
// renders at 1x on macOS 10.14.4 (black-box observation, see vd-upstream/mac-probes/aqua-leftovers-progress-3.m);
// test_quirk_progress_bar_fill pins the QUIRK-tagged behaviour of the same name in NSGraphicsStyle.
// Passes on macOS 10.14.4.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL %s line %d: %s\n", __func__, __LINE__, #c); failures++; } } while (0)

@interface ActiveWindow : NSWindow
@end
@implementation ActiveWindow
- (BOOL) isKeyWindow { return YES; }
- (BOOL) isMainWindow { return YES; }
@end
@interface ActiveApp : NSApplication
@end
@implementation ActiveApp
- (BOOL) isActive { return YES; }
@end

static NSWindow *window;

static int blueColumns(int width, double min, double max, double value) {
    NSProgressIndicator *p = [[[NSProgressIndicator alloc] initWithFrame: NSMakeRect(0, 0, width, 14)] autorelease];
    [p setIndeterminate: NO];
    [p setMinValue: min];
    [p setMaxValue: max];
    [p setDoubleValue: value];
    [[window contentView] addSubview: p];
    NSBitmapImageRep *rep = [p bitmapImageRepForCachingDisplayInRect: [p bounds]];
    [p cacheDisplayInRect: [p bounds] toBitmapImageRep: rep];
    [p removeFromSuperview];
    int blue = 0;
    for (int x = 0; x < width; x++) {
        NSColor *c = [[rep colorAtX: x y: 6] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
        if ([c blueComponent] * 255 > 150 && [c redComponent] < 0.5 && [c alphaComponent] > 0.9)
            blue++;
    }
    return blue;
}

static int expected(int width, double fraction) {
    int cols = (int) floor(width * fraction + 1e-6) - 1;
    return cols < 0 ? 0 : (cols > width - 2 ? width - 2 : cols);
}

static void test_quirk_progress_bar_fill(void) {
    int widths[] = {20, 37, 60, 100, 200};
    for (int w = 0; w < 5; w++)
        for (int v = 0; v <= 100; v++) {
            int got = blueColumns(widths[w], 0, 100, v);
            if (got != expected(widths[w], v / 100.0))
                fprintf(stderr, "  width %d value %d: %d columns, expected %d\n", widths[w], v, got, expected(widths[w], v / 100.0));
            CHECK(got == expected(widths[w], v / 100.0));
        }
    // the maximum fills the whole bar, whatever the range, and values beyond it do too
    CHECK(blueColumns(60, 0, 1, 1) == 58 && blueColumns(60, 10, 20, 20) == 58 && blueColumns(60, 0, 100, 120) == 58);
    // a value of one percent in a 60 point wide view, and one point short of the maximum, draw no sliver
    CHECK(blueColumns(60, 0, 100, 1) == 0 && blueColumns(60, 0, 100, 3) == 0);
    CHECK(blueColumns(60, 0, 100, 0) == 0);
}

int main(void) {
    @autoreleasepool {
        [ActiveApp sharedApplication];
        window = [[ActiveWindow alloc] initWithContentRect: NSMakeRect(0, 0, 300, 100) styleMask: NSTitledWindowMask
                                                   backing: NSBackingStoreBuffered defer: NO];
        [window makeKeyAndOrderFront: nil];
        test_quirk_progress_bar_fill();
    }
    if (failures) { printf("FAIL (%d)\n", failures); return 1; }
    printf("PASS\n");
    return 0;
}
