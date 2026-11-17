// Copyright (C) 2026 Lubos Dolezel
//
// A slider without tick marks looks like the Aqua one of macOS 10.14 in the light appearance: a 3 point track,
// blue up to the knob in an active window and light after it, with a round white knob. The knob rectangle is a
// square of 21 points (15 and 12 for the small and mini sizes). Expected values were sampled from renders of a
// 160 x 24 slider with the value 4 of 0 to 10 on Mac OS X 10.14.4 (black-box observation; QUIRK-tagged drawing in
// NSGraphicsStyle (NSSlider, NSSliderAqua)).
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static BOOL gActive = YES;

@interface ActiveWindow : NSWindow
@end
@implementation ActiveWindow
- (BOOL) isKeyWindow { return gActive; }
- (BOOL) isMainWindow { return gActive; }
@end
@interface ActiveApp : NSApplication
@end
@implementation ActiveApp
- (BOOL) isActive { return gActive; }
@end

static NSWindow *window;

static NSBitmapImageRep *render(NSControlSize size, BOOL enabled, NSSlider **sliderOut) {
    NSSlider *slider = [[NSSlider alloc] initWithFrame: NSMakeRect(0, 0, 160, 24)];
    [slider setMinValue: 0];
    [slider setMaxValue: 10];
    [slider setDoubleValue: 4];
    [[slider cell] setControlSize: size];
    [slider setEnabled: enabled];
    [[window contentView] addSubview: slider];
    NSBitmapImageRep *rep = [slider bitmapImageRepForCachingDisplayInRect: [slider bounds]];
    [slider cacheDisplayInRect: [slider bounds] toBitmapImageRep: rep];
    if (sliderOut)
        *sliderOut = slider;
    else
        [slider removeFromSuperview];
    return rep;
}

static void rgba(NSBitmapImageRep *rep, int x, int y, int *c) {
    NSColor *color = [[rep colorAtX: x y: y] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
    c[0] = lround([color redComponent] * 255);
    c[1] = lround([color greenComponent] * 255);
    c[2] = lround([color blueComponent] * 255);
    c[3] = lround([color alphaComponent] * 255);
}

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
        int c[4];
        NSSlider *slider;
        NSBitmapImageRep *rep = render(NSControlSizeRegular, YES, &slider);

        // knob rectangle sizes
        CHECK([[slider cell] knobRectFlipped: NO].size.width == 21 && [[slider cell] knobRectFlipped: NO].size.height == 21);
        [slider removeFromSuperview];

        // the track: 3 points thick (rows 10 to 12), blue before the knob, light after it
        int top = -1, bottom = -1;
        for (int y = 0; y < 24; y++) {
            rgba(rep, 30, y, c);
            if (c[3] > 100) {
                if (top < 0)
                    top = y;
                bottom = y;
            }
        }
        CHECK(top == 10 && bottom == 12);
        rgba(rep, 30, 11, c);
        CHECK(c[3] == 255 && abs(c[0] - 61) <= 14 && abs(c[1] - 130) <= 14 && abs(c[2] - 253) <= 14);
        rgba(rep, 120, 11, c);
        CHECK(c[3] > 35 && c[3] < 80 && c[0] < 40);
        // the knob: white in the middle, 14 to 16 points across
        rgba(rep, 65, 11, c);
        CHECK(c[0] > 245 && c[1] > 245 && c[2] > 245 && c[3] == 255);
        int white = 0;
        for (int x = 40; x < 100; x++) {
            rgba(rep, x, 11, c);
            white += c[0] > 235 && c[3] > 235;
        }
        CHECK(white >= 11 && white <= 16);
        // the knob is centred at 4/10 of the travel (Mojave: x 65 to 66)
        int first = -1, last = -1;
        for (int x = 40; x < 100; x++) {
            rgba(rep, x, 11, c);
            if (c[0] > 235 && c[3] > 235) {
                if (first < 0)
                    first = x;
                last = x;
            }
        }
        CHECK(abs((first + last) / 2 - 66) <= 3);

        // small and mini: smaller knobs
        render(NSControlSizeSmall, YES, &slider);
        CHECK([[slider cell] knobRectFlipped: NO].size.width == 15);
        [slider removeFromSuperview];
        render(NSControlSizeMini, YES, &slider);
        CHECK([[slider cell] knobRectFlipped: NO].size.width == 12);
        [slider removeFromSuperview];

        // disabled: no blue
        rep = render(NSControlSizeRegular, NO, NULL);
        rgba(rep, 30, 11, c);
        CHECK(c[3] < 200 || c[2] < 200 || c[0] > 140);
    }
    if (failures)
        return 1;
    printf("PASS\n");
    return 0;
}
