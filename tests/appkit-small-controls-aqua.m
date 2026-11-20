// Copyright (C) 2026 Lubos Dolezel
//
// Sliders, check boxes and radio buttons, steppers, spinning progress indicators, capacity level indicators and
// colour wells look like the Aqua ones of macOS 10.14 in the light appearance, and report the metrics that macOS
// 10.14 reports. Expected values were sampled from renders at 1x on Mac OS X 10.14.4 (black-box observation, see
// vd-upstream/mac-probes/aqua-small-controls.m); each test_quirk_* function pins the QUIRK-tagged behaviour of the
// same name in AppKit (NSSliderCell, NSSlider, NSGraphicsStyle, NSStepperCell, NSProgressIndicator,
// NSLevelIndicatorCell). Passes on macOS 10.14.4.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL %s line %d: %s\n", __func__, __LINE__, #c); failures++; } } while (0)

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
static const NSControlSize sizes[3] = {NSControlSizeRegular, NSControlSizeSmall, NSControlSizeMini};

static NSBitmapImageRep *snap(NSView *view) {
    [[window contentView] addSubview: view];
    NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect: [view bounds]];
    [view cacheDisplayInRect: [view bounds] toBitmapImageRep: rep];
    [view removeFromSuperview];
    return rep;
}

// the colour of a pixel, x and y from the top left corner; c[4] is the gray value composited over white
static void rgba(NSBitmapImageRep *rep, int x, int y, int *c) {
    NSColor *color = [[rep colorAtX: x y: y] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
    c[0] = lround([color redComponent] * 255);
    c[1] = lround([color greenComponent] * 255);
    c[2] = lround([color blueComponent] * 255);
    c[3] = lround([color alphaComponent] * 255);
    c[4] = lround(c[0] * c[3] / 255.0 + 255 - c[3]);
}

static int alphaAt(NSBitmapImageRep *rep, int x, int y) {
    int c[5];
    rgba(rep, x, y, c);
    return c[3];
}

static BOOL near(int a, int b, int tolerance) {
    return abs(a - b) <= tolerance;
}

static NSSlider *makeSlider(NSRect frame, NSControlSize size, NSInteger ticks, NSTickMarkPosition position) {
    NSSlider *slider = [[NSSlider alloc] initWithFrame: frame];
    [[slider cell] setControlSize: size];
    [slider setMinValue: 0];
    [slider setMaxValue: 10];
    [slider setDoubleValue: 4];
    [slider setNumberOfTickMarks: ticks];
    [slider setTickMarkPosition: position];
    return slider;
}

// QUIRK: linear slider geometry (NSSliderCell -_aquaGeometry)
static void test_quirk_slider_geometry(void) {
    // horizontal, no tick marks, at the thickness of -cellSize: the track rows and the knob's columns
    static const int thickness[3] = {19, 15, 13}, trackTop[3] = {8, 6, 4}, knobLeft[3] = {59, 60, 61},
                     knobWidth[3] = {15, 11, 9}, trackInset[3] = {3, 1, 1};
    for (int z = 0; z < 3; z++) {
        NSBitmapImageRep *rep = snap(makeSlider(NSMakeRect(0, 0, 160, thickness[z]), sizes[z], 0, 0));
        int c[5], x = 120;

        CHECK(alphaAt(rep, x, trackTop[z] - 1) < 40);
        CHECK(alphaAt(rep, x, trackTop[z] + 1) > 40);
        CHECK(alphaAt(rep, x, trackTop[z] + 3) < 40);
        // the track starts a few points from the end
        CHECK(alphaAt(rep, trackInset[z] - 1, trackTop[z] + 1) < 40);
        CHECK(alphaAt(rep, trackInset[z] + 1, trackTop[z] + 1) > 40);
        // the blue fill before the knob
        rgba(rep, 30, trackTop[z] + 1, c);
        CHECK(c[3] > 200 && near(c[0], 61, 20) && near(c[1], 130, 20) && near(c[2], 253, 20));
        // the knob: white across its width on the track's middle row
        int first = -1, last = -1;
        for (int i = 40; i < 100; i++) {
            rgba(rep, i, trackTop[z] + 1, c);
            if (c[3] > 235 && c[0] > 235 && c[2] > 235) {
                if (first < 0)
                    first = i;
                last = i;
            }
        }
        CHECK(near(first, knobLeft[z] + 1, 1) && near(last, knobLeft[z] + knobWidth[z] - 2, 1));
    }
    // a taller view: the slider is centred (rounded down)
    NSBitmapImageRep *rep = snap(makeSlider(NSMakeRect(0, 0, 160, 30), NSControlSizeRegular, 0, 0));
    CHECK(alphaAt(rep, 120, 8 + 5 + 1) > 40 && alphaAt(rep, 120, 8 + 5 - 1) < 40);

    // a wider vertical view: the slider is centred, rounded up
    rep = snap(makeSlider(NSMakeRect(0, 0, 30, 160), NSControlSizeRegular, 0, 0));
    CHECK(alphaAt(rep, 13, 40) < 40 && alphaAt(rep, 15, 40) > 40 && alphaAt(rep, 17, 40) < 40);

    // vertical, no tick marks: track columns 8 to 10, the knob measured from the bottom
    rep = snap(makeSlider(NSMakeRect(0, 0, 19, 160), NSControlSizeRegular, 0, 0));
    CHECK(alphaAt(rep, 7, 40) < 40 && alphaAt(rep, 9, 40) > 40 && alphaAt(rep, 11, 40) < 40);
    {
        int c[5], first = -1, last = -1;
        for (int y = 60; y < 120; y++) {
            rgba(rep, 9, y, c);
            if (c[3] > 235 && c[0] > 235 && c[2] > 235) {
                if (first < 0)
                    first = y;
                last = y;
            }
        }
        // the knob's centre is 66 points from the bottom: row 93
        CHECK(near((first + last) / 2, 93, 1));
    }

    // tick marks below: 11 marks at floor(10.5 + i * 13.9), rows 18 to 21; a pointed knob ending at row 18
    rep = snap(makeSlider(NSMakeRect(0, 0, 160, 24), NSControlSizeRegular, 11, NSTickMarkBelow));
    CHECK(alphaAt(rep, 10, 19) > 60 && alphaAt(rep, 80, 19) > 60 && alphaAt(rep, 149, 19) > 60);
    CHECK(alphaAt(rep, 85, 19) < 20 && alphaAt(rep, 80, 23) < 20);
    // no blue fill with tick marks
    {
        int c[5];
        rgba(rep, 30, 9, c);
        CHECK(c[3] > 20 && c[2] - c[0] < 40);
    }
    // the point: narrow at row 17, as wide as the knob at row 9
    {
        int c[5], wide = 0, narrow = 0;
        for (int x = 50; x < 85; x++) {
            rgba(rep, x, 9, c);
            wide += c[3] > 200 && c[0] > 235;
            narrow += alphaAt(rep, x, 17) > 128;
        }
        CHECK(wide >= 12 && narrow >= 1 && narrow <= 5);
    }
    // vertical sliders with tick marks: the knob points at them
    rep = snap(makeSlider(NSMakeRect(0, 0, 24, 160), NSControlSizeRegular, 11, NSTickMarkRight));
    CHECK(alphaAt(rep, 18, 93) > 128 && alphaAt(rep, 18, 88) < 60);
    rep = snap(makeSlider(NSMakeRect(0, 0, 24, 160), NSControlSizeRegular, 11, NSTickMarkLeft));
    CHECK(alphaAt(rep, 5, 93) > 128 && alphaAt(rep, 5, 88) < 60);
    // tick marks above: they start at row 3, the track at row 14
    rep = snap(makeSlider(NSMakeRect(0, 0, 160, 24), NSControlSizeRegular, 11, NSTickMarkAbove));
    CHECK(alphaAt(rep, 80, 4) > 60 && alphaAt(rep, 80, 1) < 20);
    CHECK(alphaAt(rep, 140, 15) > 40 && alphaAt(rep, 140, 12) < 20);
}

// QUIRK: -cellSize, -knobThickness and -intrinsicContentSize
static void test_quirk_slider_cell_size(void) {
    static const CGFloat plain[3] = {19, 15, 13}, ticked[3] = {24, 18, 15}, knob[3] = {21, 15, 12},
                         knobTicksH[3] = {19, 13, 11}, knobTicksV[3] = {20, 14, 12}, intrinsic[3] = {15, 13, 12},
                         intrinsicBelow[3] = {21, 18, 15}, intrinsicAbove[3] = {22, 17, 15};
    for (int z = 0; z < 3; z++) {
        NSSlider *s = makeSlider(NSMakeRect(0, 0, 160, 30), sizes[z], 0, 0);
        NSSize cs = [[s cell] cellSize];
        CHECK(cs.width == 40000 && cs.height == plain[z]);
        CHECK([s knobThickness] == knob[z]);
        CHECK([s intrinsicContentSize].height == intrinsic[z]);
        [s setNumberOfTickMarks: 5];
        cs = [[s cell] cellSize];
        CHECK(cs.width == 40000 && cs.height == ticked[z]);
        CHECK([s knobThickness] == knobTicksH[z]);
        CHECK([s intrinsicContentSize].height == intrinsicBelow[z]);
        [s setTickMarkPosition: NSTickMarkAbove];
        CHECK([s intrinsicContentSize].height == intrinsicAbove[z]);

        NSSlider *v = makeSlider(NSMakeRect(0, 0, 30, 160), sizes[z], 5, NSTickMarkRight);
        snap(v);
        CHECK([v knobThickness] == knobTicksV[z]);
        CHECK([[v cell] cellSize].width == ticked[z] && [[v cell] cellSize].height == 40000);
    }
    NSSlider *c = makeSlider(NSMakeRect(0, 0, 28, 30), NSControlSizeRegular, 0, 0);
    [[c cell] setSliderType: NSSliderTypeCircular];
    CHECK([[c cell] cellSize].width == 28 && [[c cell] cellSize].height == 30);
    CHECK([c intrinsicContentSize].width == 24 && [c intrinsicContentSize].height == 24);
    [[c cell] setControlSize: NSControlSizeSmall];
    CHECK([[c cell] cellSize].width == 18 && [[c cell] cellSize].height == 20);
}

// QUIRK: the knob rectangle (NSSliderCell -knobRectFlipped:)
static void test_quirk_slider_knob_rect(void) {
    static const NSRect expected[3] = {{{56, -1}, {21, 21}}, {{58, 0}, {15, 15}}, {{60, 0}, {12, 12}}};
    static const CGFloat thickness[3] = {19, 15, 13};
    for (int z = 0; z < 3; z++) {
        NSSlider *s = makeSlider(NSMakeRect(0, 0, 160, thickness[z]), sizes[z], 0, 0);
        snap(s);
        CHECK(NSEqualRects([[s cell] knobRectFlipped: YES], expected[z]));
    }
    NSSlider *s = makeSlider(NSMakeRect(0, 0, 160, 24), NSControlSizeRegular, 11, NSTickMarkBelow);
    snap(s);
    NSRect r = [[s cell] knobRectFlipped: YES];
    CHECK(r.size.width == 19 && r.size.height == 22 && r.origin.x == 57);
}

// QUIRK: circular slider (NSSliderCell -drawCircularSliderWithFrame:inView:)
static void test_quirk_circular_slider(void) {
    NSSlider *s = makeSlider(NSMakeRect(0, 0, 28, 30), NSControlSizeRegular, 0, 0);
    [[s cell] setSliderType: NSSliderTypeCircular];
    [s setDoubleValue: 2.5];
    NSBitmapImageRep *rep = snap(s);
    int c[5];

    // a disc 22 points across from (3, 4)
    CHECK(alphaAt(rep, 14, 2) < 20 && alphaAt(rep, 14, 5) > 200);
    CHECK(alphaAt(rep, 1, 15) < 20 && alphaAt(rep, 4, 15) > 200);
    // the dot a quarter turn clockwise from the top, 7 points right of the centre at (14, 15)
    rgba(rep, 21, 15, c);
    CHECK(c[3] > 200 && c[4] < 140);
    rgba(rep, 7, 15, c);
    CHECK(c[4] > 235);
    rgba(rep, 14, 8, c);
    CHECK(c[4] > 235);
}

static NSButton *makeToggle(BOOL radio, int z, CGFloat height) {
    static const CGFloat widths[3] = {61, 56, 50};
    NSButton *b = [[NSButton alloc] initWithFrame: NSMakeRect(0, 0, widths[z], height)];
    [b setButtonType: radio ? NSRadioButton : NSSwitchButton];
    [[b cell] setControlSize: sizes[z]];
    [b setTitle: @""];
    [b setAllowsMixedState: YES];
    return b;
}

static int firstInkRow(NSBitmapImageRep *rep, int x, int threshold) {
    for (int y = 0; y < [rep pixelsHigh]; y++)
        if (alphaAt(rep, x, y) > threshold)
            return y;
    return -1;
}

// QUIRK: toggle placement (NSGraphicsStyle NSAquaToggleBoxRect)
static void test_quirk_toggle_placement(void) {
    static const int checkTop[3] = {2, 3, 5}, radioTop[3] = {1, 2, 4};
    static const int checkX[3] = {8, 8, 8}, radioX[3] = {8, 8, 8};
    for (int z = 0; z < 3; z++) {
        NSButton *check = makeToggle(NO, z, 18), *radio = makeToggle(YES, z, 18);
        CHECK(firstInkRow(snap(check), checkX[z], 128) == checkTop[z]);
        CHECK(firstInkRow(snap(radio), radioX[z], 40) == radioTop[z]);
        [check setFrameSize: NSMakeSize([check frame].size.width, 40)];
        [radio setFrameSize: NSMakeSize([radio frame].size.width, 40)];
        CHECK(firstInkRow(snap(check), checkX[z], 128) == checkTop[z] + 11);
        CHECK(firstInkRow(snap(radio), radioX[z], 40) == radioTop[z] + 11);
    }
}

// QUIRK: mixed state of check boxes and radio buttons (NSGraphicsStyle NSAquaDrawToggle)
static void test_quirk_toggle_mixed(void) {
    NSButton *radio = makeToggle(YES, 0, 18);
    [radio setState: NSControlStateValueMixed];
    NSBitmapImageRep *rep = snap(radio);
    int c[5];

    // a white bar on rows 8 and 9 from column 5 to 12, blue above and below it
    rgba(rep, 5, 8, c);
    CHECK(c[0] > 180 && c[2] > 180);
    rgba(rep, 11, 9, c);
    CHECK(c[0] > 230 && c[1] > 230);
    rgba(rep, 8, 6, c);
    CHECK(c[2] - c[0] > 100);
    // a disabled pressed check box shows no pressed look
    NSButton *check = makeToggle(NO, 0, 18);
    [check setEnabled: NO];
    NSBitmapImageRep *plain = snap(check);
    [[check cell] setHighlighted: YES];
    NSBitmapImageRep *pressed = snap(check);
    int a[5], b[5];
    rgba(plain, 8, 8, a);
    rgba(pressed, 8, 8, b);
    CHECK(near(a[4], b[4], 3));
}

// QUIRK: stepper placement and the pressed look of -setHighlighted: (NSStepperCell -_capsuleRectInFrame:flipped:)
static void test_quirk_stepper(void) {
    static const int width[3] = {19, 15, 13}, height[3] = {27, 22, 15}, top[3] = {3, 1, 0}, bodyH[3] = {22, 19, 15};
    for (int z = 0; z < 3; z++) {
        NSStepper *s = [[NSStepper alloc] initWithFrame: NSMakeRect(0, 0, 50, 50)];
        [[s cell] setControlSize: sizes[z]];
        [s sizeToFit];
        CHECK([s frame].size.width == width[z] && [s frame].size.height == height[z]);
        NSBitmapImageRep *rep = snap(s);
        int x = width[z] / 2;
        CHECK(firstInkRow(rep, x, 20) == top[z]);
        // the capsule's lowest opaque row
        int bottom = -1;
        for (int y = 0; y < height[z]; y++)
            if (alphaAt(rep, x, y) > 128)
                bottom = y;
        CHECK(near(bottom, top[z] + bodyH[z] - 2, 1));
        // in a 40 point high frame the capsule moves down by half the difference
        [s setFrameSize: NSMakeSize(width[z], 40)];
        CHECK(firstInkRow(snap(s), x, 20) == top[z] + (40 - height[z]) / 2);
    }
    NSStepper *s = [[NSStepper alloc] initWithFrame: NSMakeRect(0, 0, 19, 27)];
    [[s cell] setHighlighted: YES];
    NSBitmapImageRep *rep = snap(s);
    int c[5];
    rgba(rep, 5, 20, c);
    CHECK(c[3] > 200 && c[2] - c[0] > 100);
    rgba(rep, 5, 8, c);
    CHECK(c[0] > 230 && c[2] > 230);
}

// QUIRK: the spinning style at its control size (NSProgressIndicator -_spinnerRect)
static void test_quirk_spinner_size(void) {
    NSProgressIndicator *p = [[NSProgressIndicator alloc] initWithFrame: NSMakeRect(0, 0, 40, 40)];
    [p setStyle: NSProgressIndicatorStyleSpinning];
    [p setControlSize: NSControlSizeSmall];
    [p setFrameSize: NSMakeSize(40, 40)];
    [p setDisplayedWhenStopped: YES];
    NSBitmapImageRep *rep = snap(p);
    int minX = 40, maxX = -1, minY = 40, maxY = -1;
    for (int y = 0; y < 40; y++)
        for (int x = 0; x < 40; x++)
            if (alphaAt(rep, x, y) > 30) {
                minX = MIN(minX, x);
                maxX = MAX(maxX, x);
                minY = MIN(minY, y);
                maxY = MAX(maxY, y);
            }
    // a 16 point spinner from (12, 12)
    CHECK(minX >= 12 && maxX <= 27 && minY >= 12 && maxY <= 27);
    CHECK(maxX - minX >= 11 && maxY - minY >= 11);
}

// QUIRK: level indicator defaults and -cellSize (NSLevelIndicatorCell -init)
static void test_quirk_level_indicator_defaults(void) {
    NSLevelIndicator *l = [[NSLevelIndicator alloc] initWithFrame: NSMakeRect(0, 0, 100, 18)];
    NSLevelIndicatorCell *cell = [l cell];
    CHECK([cell isKindOfClass: [NSLevelIndicatorCell class]]);
    CHECK([cell levelIndicatorStyle] == NSLevelIndicatorStyleDiscreteCapacity);
    CHECK([cell maxValue] == 5 && [cell warningValue] == 0 && [cell criticalValue] == 0);
    NSLevelIndicatorCell *continuous =
            [[NSLevelIndicatorCell alloc] initWithLevelIndicatorStyle: NSLevelIndicatorStyleContinuousCapacity];
    CHECK([continuous maxValue] == 100 && [continuous minValue] == 0);
    CHECK([continuous cellSize].width == 40000 && [continuous cellSize].height == 18);
}

// QUIRK: level indicator fill colours (NSLevelIndicatorCell -_fillColor)
static void test_quirk_level_indicator_colors(void) {
    static const double thresholds[4][2] = {{0, 0}, {6, 0}, {0, 8}, {8, 6}}, values[3] = {3, 7, 9};
    // 0 green, 1 yellow, 2 red, from vd-upstream/mac-probes/aqua-small-controls-2.r148.txt
    static const int expected[4][3] = {{0, 0, 0}, {1, 0, 0}, {1, 1, 2}, {2, 1, 0}};
    static const int colors[3][3] = {{54, 210, 66}, {254, 206, 9}, {252, 44, 49}};
    for (int t = 0; t < 4; t++)
        for (int v = 0; v < 3; v++) {
            NSLevelIndicator *l = [[NSLevelIndicator alloc] initWithFrame: NSMakeRect(0, 0, 100, 18)];
            [[l cell] setLevelIndicatorStyle: NSLevelIndicatorStyleContinuousCapacity];
            [l setMaxValue: 10];
            [l setWarningValue: thresholds[t][0]];
            [l setCriticalValue: thresholds[t][1]];
            [l setDoubleValue: values[v]];
            int c[5];
            rgba(snap(l), 10, 8, c);
            const int *e = colors[expected[t][v]];
            CHECK(near(c[0], e[0], 8) && near(c[1], e[1], 8) && near(c[2], e[2], 8));
        }
}

// QUIRK: level indicator bar and tick marks (NSLevelIndicatorCell -drawWithFrame:inView:)
static void test_quirk_level_indicator(void) {
    NSLevelIndicator *l = [[NSLevelIndicator alloc] initWithFrame: NSMakeRect(0, 0, 100, 18)];
    [[l cell] setLevelIndicatorStyle: NSLevelIndicatorStyleContinuousCapacity];
    [l setMaxValue: 10];
    [l setDoubleValue: 3];
    NSBitmapImageRep *rep = snap(l);
    int c[5];

    // a 16 point high bar at the top, filled to 30 points, light gray after that
    CHECK(alphaAt(rep, 50, 8) > 10 && alphaAt(rep, 50, 17) < 5);
    rgba(rep, 25, 8, c);
    CHECK(near(c[1], 210, 10) && c[0] < 100);
    rgba(rep, 35, 8, c);
    CHECK(c[4] > 200 && c[4] < 250 && near(c[0], c[2], 10));
    // tick marks: minor rows 19 to 21, major rows 18 to 23 at columns 0, 49 and 99
    [l setNumberOfTickMarks: 11];
    [l setNumberOfMajorTickMarks: 3];
    [l setFrameSize: NSMakeSize(100, 24)];
    rep = snap(l);
    CHECK(alphaAt(rep, 49, 18) > 30 && alphaAt(rep, 49, 23) > 30);
    CHECK(alphaAt(rep, 9, 20) > 30 && alphaAt(rep, 9, 18) < 10 && alphaAt(rep, 9, 22) < 10);
    CHECK(alphaAt(rep, 14, 20) < 10);

    // discrete: one rounded segment per unit, filled ones green
    [[l cell] setLevelIndicatorStyle: NSLevelIndicatorStyleDiscreteCapacity];
    [l setNumberOfTickMarks: 0];
    [l setFrameSize: NSMakeSize(100, 18)];
    rep = snap(l);
    rgba(rep, 25, 8, c);
    CHECK(near(c[1], 210, 10) && c[0] < 100);
    rgba(rep, 45, 8, c);
    CHECK(c[4] > 200 && c[4] < 250 && near(c[0], c[2], 10));
}

// QUIRK: colour well (NSGraphicsStyle -drawColorWellBorderInRect:enabled:bordered:active:)
static void test_quirk_color_well(void) {
    NSColorWell *w = [[NSColorWell alloc] initWithFrame: NSMakeRect(0, 0, 44, 23)];
    [w setColor: [NSColor colorWithCalibratedRed: 1 green: 0 blue: 0 alpha: 1]];
    NSBitmapImageRep *rep = snap(w);
    int c[5];

    rgba(rep, 3, 0, c);
    CHECK(near(c[4], 175, 4));
    rgba(rep, 2, 1, c);
    CHECK(near(c[4], 227, 4));
    rgba(rep, 2, 21, c);
    CHECK(near(c[4], 247, 4));
    rgba(rep, 8, 5, c);
    CHECK(near(c[4], 138, 6));
    rgba(rep, 6, 6, c);
    CHECK(c[0] > 240 && c[1] < 20 && c[2] < 20);
    [w setEnabled: NO];
    rgba(snap(w), 8, 5, c);
    CHECK(near(c[4], 168, 6));
    [w setEnabled: YES];
    [w setBordered: NO];
    rep = snap(w);
    rgba(rep, 5, 0, c);
    CHECK(near(c[4], 142, 6));
    rgba(rep, 0, 5, c);
    CHECK(near(c[4], 190, 6));
    rgba(rep, 2, 2, c);
    CHECK(c[0] > 240 && c[1] < 20);
}

int main(void)
{
    @autoreleasepool {
        [ActiveApp sharedApplication];
        [NSApp setActivationPolicy: NSApplicationActivationPolicyRegular];
        window = [[ActiveWindow alloc] initWithContentRect: NSMakeRect(0, 0, 300, 300)
                                                 styleMask: NSWindowStyleMaskTitled
                                                   backing: NSBackingStoreBuffered
                                                     defer: NO];
        [window makeKeyAndOrderFront: nil];

        test_quirk_slider_geometry();
        test_quirk_slider_cell_size();
        test_quirk_slider_knob_rect();
        test_quirk_circular_slider();
        test_quirk_toggle_placement();
        test_quirk_toggle_mixed();
        test_quirk_stepper();
        test_quirk_spinner_size();
        test_quirk_level_indicator_defaults();
        test_quirk_level_indicator_colors();
        test_quirk_level_indicator();
        test_quirk_color_well();
    }
    if (failures) {
        fprintf(stderr, "%d failures\n", failures);
        return 1;
    }
    printf("PASS\n");
    return 0;
}
