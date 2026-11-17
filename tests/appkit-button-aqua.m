// Copyright (C) 2026 Lubos Dolezel
//
// Check boxes and radio buttons look like the Aqua ones of macOS 10.14 in the light appearance: a white box
// with a gray outline when off, a blue box with a white mark when on or mixed in an active window, a
// darker blue while pressed, and a white box with a dark mark in a window that is not active. Rounded push
// buttons have a white bezel, and a blue one when default or pressed.
// Expected values were sampled from renders of title-less buttons in 60x18 frames on Mac OS X 10.14.4
// (black-box observation; QUIRK-tagged drawing in NSGraphicsStyle (NSButtonAqua)).
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

static NSWindow *window, *inactiveWindow;

static NSBitmapImageRep *renderIn(NSWindow *window, NSButtonType type, NSControlSize size, NSInteger state, BOOL pressed, BOOL enabled) {
    NSButton *button = [[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 60, 18)];
    [[window contentView] addSubview: button];
    [button setButtonType: type];
    [button setTitle: @""];
    [[button cell] setControlSize: size];
    if (type == NSButtonTypeSwitch)
        [button setAllowsMixedState: YES];
    [button setState: state];
    [button setEnabled: enabled];
    [[button cell] setHighlighted: pressed];
    NSBitmapImageRep *rep = [button bitmapImageRepForCachingDisplayInRect: [button bounds]];
    [button cacheDisplayInRect: [button bounds] toBitmapImageRep: rep];
    [button removeFromSuperview];
    return rep;
}

#define render(...) renderIn(window, __VA_ARGS__)

static void rgba(NSBitmapImageRep *rep, int x, int y, int *c) {
    NSColor *color = [[rep colorAtX: x y: y] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
    c[0] = lround([color redComponent] * 255);
    c[1] = lround([color greenComponent] * 255);
    c[2] = lround([color blueComponent] * 255);
    c[3] = lround([color alphaComponent] * 255);
}

static BOOL near(int *c, int r, int g, int b, int tolerance) {
    return c[3] == 255 && abs(c[0] - r) <= tolerance && abs(c[1] - g) <= tolerance && abs(c[2] - b) <= tolerance;
}

// number of pixels in the row that are mostly opaque
static int coverage(NSBitmapImageRep *rep, int y) {
    int n = 0, c[4];
    for (int x = 0; x < (int) [rep pixelsWide]; x++) {
        rgba(rep, x, y, c);
        if (c[3] >= 128)
            n++;
    }
    return n;
}

static NSBitmapImageRep *renderPush(BOOL defaulted, BOOL pressed, BOOL enabled) {
    NSButton *button = [[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 80, 32)];
    [[window contentView] addSubview: button];
    [button setBezelStyle: NSBezelStyleRounded];
    [button setTitle: @"Button"];
    [button sizeToFit];
    [button setFrameSize: NSMakeSize(80, [button frame].size.height)];
    [button setEnabled: enabled];
    if (defaulted) {
        [button setKeyEquivalent: @"\r"];
        [window setDefaultButtonCell: [button cell]];
    }
    [[button cell] setHighlighted: pressed];
    NSBitmapImageRep *rep = [button bitmapImageRepForCachingDisplayInRect: [button bounds]];
    [button cacheDisplayInRect: [button bounds] toBitmapImageRep: rep];
    [window setDefaultButtonCell: nil];
    [button removeFromSuperview];
    return rep;
}

// first row with alpha of at least 25 and last fully opaque row in the column
static void pushRows(NSBitmapImageRep *rep, int x, int *top, int *bottom) {
    int c[4];
    *top = *bottom = -1;
    for (int y = 0; y < (int) [rep pixelsHigh]; y++) {
        rgba(rep, x, y, c);
        if (c[3] >= 25 && *top < 0)
            *top = y;
        if (c[3] == 255)
            *bottom = y;
    }
}

int main(void)
{
    @autoreleasepool {
        [ActiveApp sharedApplication];
        [NSApp setActivationPolicy: NSApplicationActivationPolicyRegular];
        window = [[ActiveWindow alloc] initWithContentRect: NSMakeRect(0, 0, 100, 100)
                                                  styleMask: NSWindowStyleMaskTitled
                                                    backing: NSBackingStoreBuffered
                                                      defer: NO];
        [window makeKeyAndOrderFront: nil];
        inactiveWindow = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 100, 100)
                                                     styleMask: NSWindowStyleMaskTitled
                                                       backing: NSBackingStoreBuffered
                                                         defer: NO];
        int c[4];

        // check box, off: white inside, gray outline, 14 points wide
        NSBitmapImageRep *rep = render(NSButtonTypeSwitch, NSControlSizeRegular, NSControlStateValueOff, NO, YES);
        CHECK([rep pixelsWide] == 60 && [rep pixelsHigh] == 18);
        rgba(rep, 8, 9, c);
        CHECK(near(c, 255, 255, 255, 4));
        rgba(rep, 2, 9, c);
        CHECK(near(c, 184, 184, 184, 14));
        rgba(rep, 8, 2, c);
        CHECK(near(c, 165, 165, 165, 14));
        CHECK(coverage(rep, 9) == 14);

        // on: blue, white mark at the centre; the pressed box is a deeper blue
        rep = render(NSButtonTypeSwitch, NSControlSizeRegular, NSControlStateValueOn, NO, YES);
        rgba(rep, 4, 4, c);
        CHECK(near(c, 61, 130, 253, 12));
        rgba(rep, 2, 9, c);
        CHECK(c[3] == 255 && c[2] > 220 && c[0] < 90);
        rep = render(NSButtonTypeSwitch, NSControlSizeRegular, NSControlStateValueOn, YES, YES);
        rgba(rep, 4, 4, c);
        CHECK(near(c, 15, 98, 253, 14));

        // mixed: blue with a white bar
        rep = render(NSButtonTypeSwitch, NSControlSizeRegular, NSControlStateValueMixed, NO, YES);
        rgba(rep, 4, 4, c);
        CHECK(near(c, 61, 130, 253, 12));
        rgba(rep, 8, 9, c);
        CHECK(c[0] > 200 && c[1] > 200 && c[2] > 220);

        // control sizes: 12 and 10 points
        CHECK(coverage(render(NSButtonTypeSwitch, NSControlSizeSmall, NSControlStateValueOff, NO, YES), 9) == 12);
        CHECK(coverage(render(NSButtonTypeSwitch, NSControlSizeMini, NSControlStateValueOff, NO, YES), 9) == 10);

        // radio button: a 16 point circle, blue with a white dot in the middle when on
        rep = render(NSButtonTypeRadio, NSControlSizeRegular, NSControlStateValueOn, NO, YES);
        rgba(rep, 4, 9, c);
        CHECK(near(c, 61, 130, 253, 12));
        rgba(rep, 8, 9, c);
        CHECK(near(c, 255, 255, 255, 12));
        CHECK(coverage(rep, 9) == 16);
        rep = render(NSButtonTypeRadio, NSControlSizeRegular, NSControlStateValueOff, NO, YES);
        rgba(rep, 8, 9, c);
        CHECK(near(c, 255, 255, 255, 4));
        rgba(rep, 8, 5, c);
        CHECK(near(c, 255, 255, 255, 12));
        CHECK(coverage(rep, 9) == 16);
        CHECK(coverage(render(NSButtonTypeRadio, NSControlSizeSmall, NSControlStateValueOff, NO, YES), 9) == 14);
        CHECK(coverage(render(NSButtonTypeRadio, NSControlSizeMini, NSControlStateValueOff, NO, YES), 9) == 10);

        // the title starts clear of the box: column 17 (the box ends at 15 or 16, the title and its ink start at 18 or later) are empty
        for (int radio = 0; radio < 2; radio++) {
            NSButton *titled = [[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 100, 20)];
            [[window contentView] addSubview: titled];
            [titled setButtonType: radio ? NSButtonTypeRadio : NSButtonTypeSwitch];
            [titled setTitle: @"Option"];
            NSBitmapImageRep *tr = [titled bitmapImageRepForCachingDisplayInRect: [titled bounds]];
            [titled cacheDisplayInRect: [titled bounds] toBitmapImageRep: tr];
            [titled removeFromSuperview];
            int inkAfter = 0;
            for (int x = 17; x < 18; x++)
                for (int y = 0; y < 20; y++) {
                    rgba(tr, x, y, c);
                    inkAfter += c[3] > 30;
                }
            CHECK(inkAfter == 0);
            int firstInk = -1;
            for (int x = 18; x < 40 && firstInk < 0; x++)
                for (int y = 0; y < 20; y++) {
                    rgba(tr, x, y, c);
                    if (c[3] > 30) { firstInk = x; break; }
                }
            CHECK(firstInk >= 18 && firstInk <= 22);
        }

        // disabled: the box is fainter than the enabled one
        rep = render(NSButtonTypeSwitch, NSControlSizeRegular, NSControlStateValueOff, NO, NO);
        rgba(rep, 2, 9, c);
        CHECK(c[3] > 0 && c[3] < 200);

        // a window that is not active draws the on state without blue
        gActive = NO;
        rep = renderIn(inactiveWindow, NSButtonTypeSwitch, NSControlSizeRegular, NSControlStateValueOn, NO, YES);
        rgba(rep, 4, 4, c);
        CHECK(near(c, 255, 255, 255, 12));
        rgba(rep, 5, 9, c);
        CHECK(c[0] < 110);
        gActive = YES;

        // a button with the Return key equivalent becomes the window's default button on its own (observed on
        // Mac OS X 10.14.4 and macOS 26.7.3); one added to the window later does not take over, one given the key equivalent in the window does
        {
            NSWindow *plain = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 200, 100)
                                                          styleMask: NSWindowStyleMaskTitled
                                                            backing: NSBackingStoreBuffered
                                                              defer: NO];
            NSButton *ok = [NSButton buttonWithTitle: @"OK" target: nil action: nil];
            [ok setKeyEquivalent: @"\r"];
            [[plain contentView] addSubview: ok];
            CHECK([plain defaultButtonCell] == [ok cell]);
            NSButton *other = [NSButton buttonWithTitle: @"Other" target: nil action: nil];
            [[plain contentView] addSubview: other];
            [other setKeyEquivalent: @"\r"];
            CHECK([plain defaultButtonCell] == [other cell]);
            NSButton *early = [NSButton buttonWithTitle: @"Early" target: nil action: nil];
            [early setKeyEquivalent: @"\r"];
            [[plain contentView] addSubview: early];
            CHECK([plain defaultButtonCell] == [other cell]);
            NSButton *late = [NSButton buttonWithTitle: @"Late" target: nil action: nil];
            NSWindow *second = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 200, 100)
                                                           styleMask: NSWindowStyleMaskTitled
                                                             backing: NSBackingStoreBuffered
                                                               defer: NO];
            [[second contentView] addSubview: late];
            CHECK([second defaultButtonCell] == nil);
            [late setKeyEquivalent: @"\r"];
            CHECK([second defaultButtonCell] == [late cell]);
        }

        // rounded push button: white bezel; blue gradient when default or pressed; fainter when disabled.
        // Columns are sampled away from the title; rows are relative to the bezel's top and bottom edge.
        int top, bottom;
        rep = renderPush(NO, NO, YES);
        pushRows(rep, 10, &top, &bottom);
        CHECK(top >= 0 && bottom - top >= 17 && bottom - top <= 21);
        rgba(rep, 10, top + 5, c);
        CHECK(near(c, 255, 255, 255, 4));
        rgba(rep, 10, top, c);
        CHECK(c[3] > 0 && c[3] < 140 && c[0] < 40);
        rep = renderPush(YES, NO, YES);
        pushRows(rep, 10, &top, &bottom);
        rgba(rep, 10, top + 1, c);
        CHECK(near(c, 107, 161, 250, 28));
        rgba(rep, 10, bottom - 1, c);
        CHECK(near(c, 17, 100, 255, 28));
        rep = renderPush(NO, YES, YES);
        pushRows(rep, 10, &top, &bottom);
        rgba(rep, 10, top + 1, c);
        CHECK(near(c, 76, 139, 253, 28));
        rgba(rep, 10, bottom - 1, c);
        CHECK(near(c, 15, 88, 231, 28));
        rep = renderPush(NO, NO, NO);
        pushRows(rep, 10, &top, &bottom);
        rgba(rep, 10, top + 8, c);
        CHECK(c[3] > 90 && c[3] < 200);
        // a default button is not blue in a window that is not active
        gActive = NO;
        window = inactiveWindow;
        rep = renderPush(YES, NO, YES);
        pushRows(rep, 10, &top, &bottom);
        rgba(rep, 10, top + 5, c);
        CHECK(near(c, 255, 255, 255, 4));
        gActive = YES;
    }
    if (failures)
        return 1;
    printf("PASS\n");
    return 0;
}
