// Copyright (C) 2026 Lubos Dolezel
//
// The bar-style NSProgressIndicator looks like the Aqua one of macOS 10.14 in the light appearance: a bar 6 points
// high, centred in the view and inset 1 point from its sides, with a very light track and a blue fill that has
// fully rounded outer ends and a square end at the progress value. Expected values were sampled from renders of
// 200 point wide bars on Mac OS X 10.14.4 (black-box observation; QUIRK-tagged drawing in
// NSGraphicsStyle (NSProgressIndicator)).
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static NSWindow *window;

static NSBitmapImageRep *render(double value, BOOL indeterminate, CGFloat height, NSControlSize size) {
    NSProgressIndicator *bar = [[NSProgressIndicator alloc] initWithFrame: NSMakeRect(0, 0, 200, height)];
    [bar setStyle: NSProgressIndicatorStyleBar];
    [bar setIndeterminate: indeterminate];
    [bar setUsesThreadedAnimation: NO];
    [bar setMinValue: 0];
    [bar setMaxValue: 100];
    [bar setDoubleValue: value];
    [bar setControlSize: size];
    [[window contentView] addSubview: bar];
    NSBitmapImageRep *rep = [bar bitmapImageRepForCachingDisplayInRect: [bar bounds]];
    [bar cacheDisplayInRect: [bar bounds] toBitmapImageRep: rep];
    [bar removeFromSuperview];
    return rep;
}

static void rgba(NSBitmapImageRep *rep, int x, int y, int *c) {
    NSColor *color = [[rep colorAtX: x y: y] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
    c[0] = lround([color redComponent] * 255);
    c[1] = lround([color greenComponent] * 255);
    c[2] = lround([color blueComponent] * 255);
    c[3] = lround([color alphaComponent] * 255);
}

// rows of the column and columns of the row that have any ink
static void extent(NSBitmapImageRep *rep, int fixed, int vertical, int *first, int *last) {
    int n = vertical ? (int) [rep pixelsHigh] : (int) [rep pixelsWide], c[4];
    *first = *last = -1;
    for (int i = 0; i < n; i++) {
        rgba(rep, vertical ? fixed : i, vertical ? i : fixed, c);
        if (c[3] > 0) {
            if (*first < 0)
                *first = i;
            *last = i;
        }
    }
}

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

int main(void)
{
    @autoreleasepool {
        [ActiveApp sharedApplication];
        [NSApp setActivationPolicy: NSApplicationActivationPolicyRegular];
        window = [[ActiveWindow alloc] initWithContentRect: NSMakeRect(0, 0, 300, 100)
                                                  styleMask: NSWindowStyleMaskTitled
                                                    backing: NSBackingStoreBuffered
                                                      defer: NO];
        [window makeKeyAndOrderFront: nil];
        int c[4], first, last;

        NSBitmapImageRep *rep = render(60, NO, 20, NSControlSizeRegular);
        // 6 points high, centred (rows 7 to 12); from x 1 to x 198
        extent(rep, 100, 1, &first, &last);
        CHECK(first == 7 && last == 12);
        extent(rep, 9, 0, &first, &last);
        CHECK(first >= 0 && first <= 2 && last >= 197 && last <= 198);
        // the fill is blue with a darker edge row, up to 60% of the bar; the track after it is very light
        rgba(rep, 60, 9, c);
        CHECK(c[3] == 255 && abs(c[0] - 61) <= 6 && abs(c[1] - 130) <= 6 && abs(c[2] - 253) <= 6);
        rgba(rep, 60, 7, c);
        CHECK(c[3] == 255 && abs(c[0] - 53) <= 12 && abs(c[1] - 113) <= 12 && abs(c[2] - 220) <= 12);
        rgba(rep, 115, 9, c);
        CHECK(c[2] > 240 && c[3] == 255);
        rgba(rep, 124, 9, c);
        CHECK(c[3] > 5 && c[3] < 40 && c[2] < 30);
        // the fill's left end is rounded: its corner pixel is not fully blue
        rgba(rep, 1, 7, c);
        CHECK(c[3] < 255);

        // a full bar's right end is rounded as well; an empty bar is the track only
        rep = render(100, NO, 20, NSControlSizeRegular);
        rgba(rep, 197, 9, c);
        CHECK(c[3] == 255 && c[2] > 240);
        rgba(rep, 198, 7, c);
        CHECK(c[3] < 255);
        rep = render(0, NO, 20, NSControlSizeRegular);
        rgba(rep, 50, 9, c);
        CHECK(c[3] > 5 && c[3] < 40 && c[2] < 30);

        // the bar is 6 points high in a smaller view too
        rep = render(60, NO, 12, NSControlSizeSmall);
        extent(rep, 100, 1, &first, &last);
        CHECK(first == 3 && last == 8);

        // a spinning indicator sizes to 32, 16 and 10 points and draws spokes inside that square
        static const struct { NSControlSize size; int side; } spinners[] = {
            { NSControlSizeRegular, 32 }, { NSControlSizeSmall, 16 }, { NSControlSizeMini, 10 }
        };
        for (int i = 0; i < 3; i++) {
            NSProgressIndicator *spinner = [[NSProgressIndicator alloc] initWithFrame: NSMakeRect(0, 0, 50, 50)];
            [spinner setStyle: NSProgressIndicatorStyleSpinning];
            [spinner setIndeterminate: YES];
            [spinner setUsesThreadedAnimation: NO];
            [spinner setControlSize: spinners[i].size];
            [spinner sizeToFit];
            CHECK([spinner frame].size.width == spinners[i].side && [spinner frame].size.height == spinners[i].side);
            NSBitmapImageRep *srep = [spinner bitmapImageRepForCachingDisplayInRect: [spinner bounds]];
            [spinner cacheDisplayInRect: [spinner bounds] toBitmapImageRep: srep];
            int minX = 1000, maxX = -1, dark = 0;
            for (int x = 0; x < spinners[i].side; x++)
                for (int y = 0; y < spinners[i].side; y++) {
                    rgba(srep, x, y, c);
                    if (c[3] > 30) {
                        minX = MIN(minX, x);
                        maxX = MAX(maxX, x);
                    }
                    dark += c[3] > 150 && c[0] < 100;
                }
            // the spokes reach the edge of the square, and the head spoke is dark
            CHECK(minX <= 1 && maxX >= spinners[i].side - 2);
            CHECK(dark >= 1);
        }

        // an indicator is displayed when stopped by default, and an indeterminate bar is filled with blue all the way
        CHECK([[[NSProgressIndicator alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)] isDisplayedWhenStopped]);
        rep = render(0, YES, 20, NSControlSizeRegular);
        rgba(rep, 100, 9, c);
        CHECK(c[3] == 255 && c[2] > 240 && c[0] > 100 && c[0] < 125);
        // the band is lighter in the middle than at the ends (Mojave at rest: 62 at the ends, 113 in the middle)
        rgba(rep, 8, 9, c);
        CHECK(c[0] > 50 && c[0] < 80);
        rgba(rep, 60, 9, c);
        CHECK(c[0] > 78 && c[0] < 100);
    }
    if (failures)
        return 1;
    printf("PASS\n");
    return 0;
}
