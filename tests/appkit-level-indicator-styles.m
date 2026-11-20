// Copyright (C) 2026 Lubos Dolezel
//
// The relevancy and rating styles of NSLevelIndicator look like the ones of macOS 10.14 in the light appearance,
// rating indicators take clicks and report the sizes macOS 10.14 reports, and the rating images are nil by default
// and replace the stars when set. Expected values were sampled from renders at 1x on macOS 10.14.4 and 26.7.3
// (black-box observation, see vd-upstream/mac-probes/aqua-leftovers-level.m); each test_quirk_* function pins the
// QUIRK-tagged behaviour of the same name in NSLevelIndicatorCell. Passes on macOS 10.14.4.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL %s line %d: %s\n", __func__, __LINE__, #c); failures++; } } while (0)

@interface ActiveWindow : NSWindow
@end
@implementation ActiveWindow
- (BOOL) isKeyWindow { return YES; }
- (BOOL) isMainWindow { return YES; }
- (BOOL) canBecomeKeyWindow { return YES; }
@end
@interface ActiveApp : NSApplication
@end
@implementation ActiveApp
- (BOOL) isActive { return YES; }
@end

static NSWindow *window;

static NSBitmapImageRep *snap(NSView *view) {
    [[window contentView] addSubview: view];
    NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect: [view bounds]];
    [view cacheDisplayInRect: [view bounds] toBitmapImageRep: rep];
    [view removeFromSuperview];
    return rep;
}

// c = {red, green, blue, alpha} of a pixel, x and y from the top left corner
static void rgba(NSBitmapImageRep *rep, int x, int y, int *c) {
    NSColor *color = [[rep colorAtX: x y: y] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
    c[0] = lround([color redComponent] * 255);
    c[1] = lround([color greenComponent] * 255);
    c[2] = lround([color blueComponent] * 255);
    c[3] = lround([color alphaComponent] * 255);
}

static int alphaAt(NSBitmapImageRep *rep, int x, int y) {
    int c[4];
    rgba(rep, x, y, c);
    return c[3];
}

static BOOL near(int a, int b, int tolerance) {
    return abs(a - b) <= tolerance;
}

static NSLevelIndicator *make(NSLevelIndicatorStyle style, NSRect frame) {
    NSLevelIndicator *l = [[[NSLevelIndicator alloc] initWithFrame: frame] autorelease];
    [[l cell] setLevelIndicatorStyle: style];
    return l;
}

static void test_quirk_relevancy_style(void) {
    NSLevelIndicator *l = make(NSLevelIndicatorStyleRelevancy, NSMakeRect(0, 0, 100, 20));
    [l setMaxValue: 100];
    [l setDoubleValue: 0];
    NSBitmapImageRep *rep = snap(l);
    CHECK(alphaAt(rep, 50, 3) == 0 && alphaAt(rep, 50, 16) == 0);
    CHECK(near(alphaAt(rep, 50, 4), 26, 2) && near(alphaAt(rep, 50, 15), 26, 2));
    CHECK(near(alphaAt(rep, 0, 8), 26, 2) && near(alphaAt(rep, 99, 8), 26, 2));
    [l setDoubleValue: 50];
    rep = snap(l);
    CHECK(near(alphaAt(rep, 0, 4), 140, 3) && near(alphaAt(rep, 1, 4), 83, 3));
    CHECK(near(alphaAt(rep, 48, 15), 140, 3) && near(alphaAt(rep, 49, 15), 83, 3));
    CHECK(near(alphaAt(rep, 50, 9), 26, 2) && near(alphaAt(rep, 99, 9), 26, 2));
    CHECK(alphaAt(rep, 10, 3) == 0);
    [l setDoubleValue: 100];
    rep = snap(l);
    CHECK(near(alphaAt(rep, 98, 8), 140, 3) && near(alphaAt(rep, 99, 8), 83, 3));
    // disabled and small look the same
    [l setEnabled: NO];
    [[l cell] setControlSize: NSControlSizeSmall];
    rep = snap(l);
    CHECK(near(alphaAt(rep, 0, 8), 140, 3) && near(alphaAt(rep, 1, 8), 83, 3));
    CHECK([[l cell] cellSize].height == 12);
}

static void test_quirk_rating_style(void) {
    NSLevelIndicator *l = make(NSLevelIndicatorStyleRating, NSMakeRect(0, 0, 100, 20));
    [l setDoubleValue: 3];
    NSBitmapImageRep *rep = snap(l);
    for (int star = 0; star < 5; star++) {
        int expected = star < 3 ? 127 : 25;
        CHECK(near(alphaAt(rep, star * 12 + 6, 9), expected, 8));
        CHECK(near(alphaAt(rep, star * 12 + 5, 12), expected, 8));
        CHECK(alphaAt(rep, star * 12 + 1, 4) == 0 && alphaAt(rep, star * 12 + 6, 3) == 0 &&
              alphaAt(rep, star * 12 + 6, 16) == 0);
        // the notch between the legs and the gaps between the arms and the top are empty
        CHECK(alphaAt(rep, star * 12 + 6, 15) < 8 && alphaAt(rep, star * 12 + 1, 7) < 3);
    }
    CHECK(alphaAt(rep, 61, 9) == 0 && alphaAt(rep, 90, 9) == 0);
    // the top tip is thin, the arms reach the cell edges of the unit
    CHECK(alphaAt(rep, 5, 5) > 10 && alphaAt(rep, 5, 5) < 70);
    CHECK(alphaAt(rep, 0, 9) > 20 && alphaAt(rep, 11, 9) > 20);
    // a half value rounds up; disabled and editable look the same
    [l setDoubleValue: 2.5];
    rep = snap(l);
    CHECK(near(alphaAt(rep, 30, 9), 127, 8));
    [l setEnabled: NO];
    [l setEditable: YES];
    rep = snap(l);
    CHECK(near(alphaAt(rep, 30, 9), 127, 8) && near(alphaAt(rep, 42, 9), 25, 8));

    NSLevelIndicator *q = make(NSLevelIndicatorStyleRating, NSMakeRect(0, 0, 100, 20));
    int maxes[] = {1, 4, 7};
    for (int i = 0; i < 3; i++) {
        [q setMaxValue: maxes[i]];
        CHECK([[q cell] cellSize].width == 12 * maxes[i] && [[q cell] cellSize].height == 12);
        CHECK([q intrinsicContentSize].width == 12 * maxes[i] && [q intrinsicContentSize].height == 12);
    }
    CHECK([q ratingImage] == nil && [q ratingPlaceholderImage] == nil);
}

static NSImage *solidImage(NSColor *color, NSSize size) {
    NSImage *image = [[[NSImage alloc] initWithSize: size] autorelease];
    [image lockFocus];
    [color setFill];
    NSRectFill(NSMakeRect(0, 0, size.width, size.height));
    [image unlockFocus];
    return image;
}

static void test_rating_images(void) {
    NSLevelIndicator *l = make(NSLevelIndicatorStyleRating, NSMakeRect(0, 0, 100, 20));
    NSImage *full = solidImage([NSColor redColor], NSMakeSize(12, 12));
    NSImage *empty = solidImage([NSColor blueColor], NSMakeSize(12, 12));
    [l setRatingImage: full];
    [l setRatingPlaceholderImage: empty];
    CHECK([l ratingImage] == full && [l ratingPlaceholderImage] == empty);
    [l setDoubleValue: 2];
    NSBitmapImageRep *rep = snap(l);
    int c[4];
    rgba(rep, 6, 9, c);
    CHECK(c[0] > 240 && c[1] < 20 && c[2] < 20 && c[3] > 240);
    rgba(rep, 18, 9, c);
    CHECK(c[0] > 240 && c[1] < 20 && c[2] < 20 && c[3] > 240);
    rgba(rep, 30, 9, c);
    CHECK(c[0] < 20 && c[1] < 20 && c[2] > 240 && c[3] > 240);
    rgba(rep, 54, 9, c);
    CHECK(c[2] > 240 && c[3] > 240);
    [l setRatingImage: nil];
    [l setRatingPlaceholderImage: nil];
    CHECK([l ratingImage] == nil);
}

static double clickAt(NSLevelIndicator *l, double x, double start) {
    [l setDoubleValue: start];
    NSPoint p = [l convertPoint: NSMakePoint(x, 10) toView: nil];
    NSTimeInterval t = [NSDate timeIntervalSinceReferenceDate];
    NSEvent *down = [NSEvent mouseEventWithType: NSLeftMouseDown location: p modifierFlags: 0 timestamp: t
                                   windowNumber: [window windowNumber] context: nil eventNumber: 1 clickCount: 1 pressure: 1];
    NSEvent *up = [NSEvent mouseEventWithType: NSLeftMouseUp location: p modifierFlags: 0 timestamp: t
                                 windowNumber: [window windowNumber] context: nil eventNumber: 1 clickCount: 1 pressure: 0];
    [NSApp postEvent: up atStart: NO];
    [l mouseDown: down];
    return [l doubleValue];
}

static void test_quirk_rating_clicks(void) {
    NSLevelIndicator *l = make(NSLevelIndicatorStyleRating, NSMakeRect(20, 20, 100, 20));
    [[window contentView] addSubview: l];
    [l setEditable: YES];
    CHECK(clickAt(l, 1, 0) == 1 && clickAt(l, 10, 0) == 1 && clickAt(l, 19, 0) == 2 && clickAt(l, 21, 0) == 2);
    CHECK(clickAt(l, 30, 0) == 3 && clickAt(l, 50, 0) == 5 && clickAt(l, 99, 0) == 5);
    CHECK(clickAt(l, 30, 3) == 3 && clickAt(l, 5, 1) == 1 && clickAt(l, 50, 5) == 5);
    [l setMaxValue: 3];
    CHECK(clickAt(l, 50, 0) == 3);
    [l setMaxValue: 5];
    [l setEditable: NO];
    CHECK(clickAt(l, 30, 1) == 1);
    [l setEditable: YES];
    [l setEnabled: NO];
    CHECK(clickAt(l, 30, 1) == 1);
    [l removeFromSuperview];
}

int main(void) {
    @autoreleasepool {
        [ActiveApp sharedApplication];
        window = [[ActiveWindow alloc] initWithContentRect: NSMakeRect(0, 0, 300, 100) styleMask: NSTitledWindowMask
                                                   backing: NSBackingStoreBuffered defer: NO];
        [window makeKeyAndOrderFront: nil];
        test_quirk_relevancy_style();
        test_quirk_rating_style();
        test_rating_images();
        test_quirk_rating_clicks();
    }
    if (failures) { printf("FAIL (%d)\n", failures); return 1; }
    printf("PASS\n");
    return 0;
}
