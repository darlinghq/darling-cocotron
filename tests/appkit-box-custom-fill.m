// Copyright (C) 2026 Lubos Dolezel
// A custom box (NSBoxCustom) draws its fill color over what is behind it: with the default
// clear fill the superview shows through, a translucent fill blends with it, and a corner radius
// leaves the corners showing it. A box made in code keeps the custom properties set on it, with
// the defaults of macOS 10.14.4 and 26.7.3 (where all of this was observed).
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

#define CHECK(cond, ...) do { if (!(cond)) { printf("FAIL %s:%d: ", __FILE__, __LINE__); printf(__VA_ARGS__); printf("\n"); failures++; } } while (0)

@interface RedView : NSView
@end

@implementation RedView
- (void) drawRect: (NSRect) rect {
    [[NSColor colorWithSRGBRed: 1 green: 0 blue: 0 alpha: 1] setFill];
    NSRectFill(rect);
}
@end

static NSBox *customBox(NSRect frame) {
    NSBox *box = [[NSBox alloc] initWithFrame: frame];
    [box setBoxType: NSBoxCustom];
    [box setTitlePosition: NSNoTitle];
    [box setBorderWidth: 0];
    [box setBorderColor: [NSColor clearColor]];
    return box;
}

// The pixel at a point of the content view, in its flipped-to-top bitmap coordinates.
static void pixel(NSBitmapImageRep *rep, NSView *view, NSPoint point, CGFloat rgba[4]) {
    CGFloat scale = [rep pixelsWide] / NSWidth([view bounds]);
    NSColor *color = [[rep colorAtX: (NSInteger) (point.x * scale)
                                  y: (NSInteger) ((NSHeight([view bounds]) - point.y) * scale)]
            colorUsingColorSpace: [NSColorSpace sRGBColorSpace]];
    [color getRed: &rgba[0] green: &rgba[1] blue: &rgba[2] alpha: &rgba[3]];
}

static BOOL near(CGFloat a, CGFloat b) {
    return a > b - 0.06 && a < b + 0.06;
}

// Compares with a reference pixel, as the bitmap's color space can shift the colors drawn a little.
static void expect(NSBitmapImageRep *rep, NSView *view, NSPoint point, const CGFloat reference[4], const char *what) {
    CGFloat rgba[4];
    pixel(rep, view, point, rgba);
    CHECK(near(rgba[0], reference[0]) && near(rgba[1], reference[1]) && near(rgba[2], reference[2]) && near(rgba[3], 1),
          "%s at %g,%g: %.2f %.2f %.2f alpha %.2f, expected %.2f %.2f %.2f alpha 1", what, point.x, point.y,
          rgba[0], rgba[1], rgba[2], rgba[3], reference[0], reference[1], reference[2]);
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        [NSApplication sharedApplication];

        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 300, 100)
                                                       styleMask: NSWindowStyleMaskTitled
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        RedView *red = [[RedView alloc] initWithFrame: NSMakeRect(0, 0, 300, 100)];
        [window setContentView: red];

        NSBox *clear = customBox(NSMakeRect(10, 10, 80, 80));
        CHECK([clear fillColor] != nil && [[clear fillColor] alphaComponent] == 0, "the default fill color is clear");
        CHECK([clear cornerRadius] == 0, "the default corner radius is %g", [clear cornerRadius]);
        NSBox *plain = [[NSBox alloc] initWithFrame: NSMakeRect(0, 0, 50, 50)];
        CHECK([plain borderWidth] == 1, "the default border width is %g", [plain borderWidth]);
        CHECK([plain borderColor] != nil, "a box has a default border color");
        [plain setFillColor: [NSColor blueColor]];
        CHECK([[plain fillColor] isEqual: [NSColor blueColor]], "a box made in code keeps its fill color");
        [red addSubview: clear];

        NSBox *translucent = customBox(NSMakeRect(110, 10, 80, 80));
        [translucent setFillColor: [NSColor colorWithSRGBRed: 0 green: 0 blue: 1 alpha: 0.5]];
        [red addSubview: translucent];

        NSBox *rounded = customBox(NSMakeRect(210, 10, 80, 80));
        [rounded setFillColor: [NSColor colorWithSRGBRed: 0 green: 1 blue: 0 alpha: 1]];
        [rounded setCornerRadius: 20];
        [red addSubview: rounded];

        [window orderFront: nil];
        [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.3]];

        NSBitmapImageRep *rep = [red bitmapImageRepForCachingDisplayInRect: [red bounds]];
        [red cacheDisplayInRect: [red bounds] toBitmapImageRep: rep];

        CGFloat background[4], translucentPixel[4], greenPixel[4];
        pixel(rep, red, NSMakePoint(5, 50), background);
        CHECK(background[0] > 0.9 && background[1] < 0.3 && background[2] < 0.3, "the superview is red: %.2f %.2f %.2f",
              background[0], background[1], background[2]);
        expect(rep, red, NSMakePoint(50, 50), background, "inside the clear box");
        expect(rep, red, NSMakePoint(212, 12), background, "in a corner of the rounded box");
        pixel(rep, red, NSMakePoint(150, 50), translucentPixel);
        CHECK(translucentPixel[0] > 0.35 && translucentPixel[0] < 0.75 && translucentPixel[2] > 0.35 && translucentPixel[2] < 0.75 &&
              translucentPixel[3] > 0.95, "the translucent box blends blue with the red behind it: %.2f %.2f %.2f alpha %.2f",
              translucentPixel[0], translucentPixel[1], translucentPixel[2], translucentPixel[3]);
        pixel(rep, red, NSMakePoint(250, 50), greenPixel);
        CHECK(greenPixel[1] > 0.9 && greenPixel[0] < 0.3, "the rounded box is filled green: %.2f %.2f %.2f",
              greenPixel[0], greenPixel[1], greenPixel[2]);
    }
    if (failures) {
        printf("%d failures\n", failures);
        return 1;
    }
    printf("PASS\n");
    return 0;
}
