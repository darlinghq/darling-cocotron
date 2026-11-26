// Copyright (C) 2026 Lubos Dolezel
//
// Private AppKit functions and constants web engines call:
//  - NSDrawMenuBackground paints the menu background colour over the bounds, without a frame line, limited to
//    the clip rectangle unless that is empty.
//  - _NSDrawCarbonThemeListBox draws the frame of a text area and leaves its inside alone; the frame is lighter
//    when the box is not enabled.
//  - NSInitializeCGFocusRingStyleForTime fills in a focus ring style whose ordering follows the placement.
//  - NSAccessibilityHandleFocusChanged can be called; NSAccessibilityCreateAXUIElementRef may give NULL (Darling's
//    HIServices has no AXUIElement type); NSAccessibilityUnregisterUniqueIdForUIElement takes any object or nil,
//    more than once.
//  - _NSResetKillRingOperationFlag ends the yanked state, so the next append extends the current entry.
//  - the pop-up menu option keys and the text attribute names exist and differ; _NXSmartPaste is the type
//    WebKit names for it.
// Build: clang -framework AppKit appkit-webkit-private-functions.m
#import <AppKit/AppKit.h>
#include <dlfcn.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

// As WebKit declares it (pal/spi/cg/CoreGraphicsSPI.h).
typedef struct {
    unsigned int version;
    int32_t tint;
    int32_t ordering;
    CGFloat alpha;
    CGFloat radius;
    CGFloat threshold;
    CGRect bounds;
    int accumulate;
} FocusRingStyle;

static NSBitmapImageRep *bitmap(NSInteger width, NSInteger height) {
    return [[NSBitmapImageRep alloc] initWithBitmapDataPlanes: NULL pixelsWide: width pixelsHigh: height
            bitsPerSample: 8 samplesPerPixel: 4 hasAlpha: YES isPlanar: NO
            colorSpaceName: NSCalibratedRGBColorSpace bytesPerRow: 0 bitsPerPixel: 0];
}

static void fillRed(NSInteger width, NSInteger height) {
    [[NSColor colorWithCalibratedRed: 1 green: 0 blue: 0 alpha: 1] setFill];
    NSRectFill(NSMakeRect(0, 0, width, height));
}

static void test_menu_background(void) {
    void (*drawMenuBackground)(NSRect, NSRect, NSUInteger) = dlsym(RTLD_DEFAULT, "NSDrawMenuBackground");
    CHECK(drawMenuBackground != NULL);
    if (drawMenuBackground == NULL)
        return;

    NSBitmapImageRep *rep = bitmap(10, 10);

    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext: [NSGraphicsContext graphicsContextWithBitmapImageRep: rep]];
    fillRed(10, 10);
    drawMenuBackground(NSMakeRect(0, 0, 10, 10), NSZeroRect, 0x200);
    [NSGraphicsContext restoreGraphicsState];
    // The background covers the red, and has no frame line: the edges are
    // the colour of the middle.
    NSColor *middle = [[rep colorAtX: 5 y: 5] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
    CHECK(!([middle redComponent] > 0.97 && [middle greenComponent] < 0.03));
    for (NSInteger x = 0; x < 10; x += 9) {
        NSColor *c = [[rep colorAtX: x y: 5] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
        CHECK(fabs([c redComponent] - [middle redComponent]) < 0.03);
        CHECK(fabs([c greenComponent] - [middle greenComponent]) < 0.03);
    }

    // Limited to the clip rectangle.
    rep = bitmap(10, 10);
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext: [NSGraphicsContext graphicsContextWithBitmapImageRep: rep]];
    fillRed(10, 10);
    drawMenuBackground(NSMakeRect(0, 0, 10, 10), NSMakeRect(0, 0, 5, 10), 0);
    [NSGraphicsContext restoreGraphicsState];
    NSColor *outside = [[rep colorAtX: 8 y: 5] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
    CHECK([outside redComponent] > 0.97 && [outside greenComponent] < 0.03);
}

static double redOf(NSBitmapImageRep *rep, NSInteger x, NSInteger y) {
    return [[[rep colorAtX: x y: y] colorUsingColorSpaceName: NSCalibratedRGBColorSpace] redComponent];
}

static void test_list_box_frame(void) {
    void (*drawListBox)(NSRect, BOOL, BOOL, BOOL) = dlsym(RTLD_DEFAULT, "_NSDrawCarbonThemeListBox");
    CHECK(drawListBox != NULL);
    if (drawListBox == NULL)
        return;

    NSBitmapImageRep *enabled = bitmap(20, 20), *disabled = bitmap(20, 20);
    NSBitmapImageRep *reps[2] = {enabled, disabled};

    for (int i = 0; i < 2; i++) {
        [NSGraphicsContext saveGraphicsState];
        [NSGraphicsContext setCurrentContext: [NSGraphicsContext graphicsContextWithBitmapImageRep: reps[i]]];
        fillRed(20, 20);
        drawListBox(NSMakeRect(0, 0, 20, 20), i == 0, YES, YES);
        [NSGraphicsContext restoreGraphicsState];
    }
    // The inside keeps what was there; the edge is darkened, less so when not enabled.
    CHECK(redOf(enabled, 10, 10) > 0.97);
    CHECK(redOf(enabled, 0, 10) < 0.95);
    CHECK(redOf(enabled, 0, 10) < redOf(disabled, 0, 10));
    CHECK(redOf(disabled, 0, 10) < 0.97);
}

static void test_focus_ring_style(void) {
    BOOL (*initialize)(NSFocusRingPlacement, FocusRingStyle *, NSTimeInterval) =
            dlsym(RTLD_DEFAULT, "NSInitializeCGFocusRingStyleForTime");
    CHECK(initialize != NULL);
    if (initialize == NULL)
        return;

    // the settled ring (from 0.25 s in), as macOS 26.7.3 and 10.14.4 give it;
    // NO means the appearance animation is over
    FocusRingStyle style;
    memset(&style, 0x55, sizeof(style));
    CHECK(!initialize(NSFocusRingOnly, &style, 1000));
    CHECK(style.version == 0 && style.tint == 0 && style.ordering == 0);
    CHECK(fabs(style.alpha - 0.5) < 1e-6 && fabs(style.radius - 3.00438541) < 1e-6 &&
          fabs(style.threshold - 0.15) < 1e-6);
    CHECK(style.accumulate == 0 && CGRectIsEmpty(style.bounds));
    CHECK(!initialize(NSFocusRingBelow, &style, 1000) && style.ordering == 1);
    CHECK(!initialize(NSFocusRingAbove, &style, 1000) && style.ordering == 2);
}

static void test_accessibility(void) {
    void (*focusChanged)(void) = dlsym(RTLD_DEFAULT, "NSAccessibilityHandleFocusChanged");
    CFTypeRef (*createElement)(id) = dlsym(RTLD_DEFAULT, "NSAccessibilityCreateAXUIElementRef");
    void (*unregister)(id) = dlsym(RTLD_DEFAULT, "NSAccessibilityUnregisterUniqueIdForUIElement");
    CHECK(focusChanged != NULL && createElement != NULL && unregister != NULL);
    if (focusChanged == NULL || createElement == NULL || unregister == NULL)
        return;

    // Darling has no AXUIElement type yet, so it makes no element (macOS does);
    // the calls must still be safe
    focusChanged();
    NSView *view = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)];
    CFTypeRef element = createElement(view);
    if (element != NULL)
        CFRelease(element);

    // forgetting an element's id is safe for a view, more than once, for any object and for nil
    unregister(view);
    unregister(view);
    NSObject *object = [[NSObject alloc] init];
    unregister(object);
    [object release];
    unregister(nil);
    [view release];
}

static void test_kill_ring_operation_flag(void) {
    void (*initRing)(void) = dlsym(RTLD_DEFAULT, "_NSInitializeKillRing");
    void (*append)(NSString *) = dlsym(RTLD_DEFAULT, "_NSAppendToKillRing");
    void (*prepend)(NSString *) = dlsym(RTLD_DEFAULT, "_NSPrependToKillRing");
    void (*newSequence)(void) = dlsym(RTLD_DEFAULT, "_NSNewKillRingSequence");
    void (*setYanked)(void) = dlsym(RTLD_DEFAULT, "_NSSetKillRingToYankedState");
    void (*resetFlag)(void) = dlsym(RTLD_DEFAULT, "_NSResetKillRingOperationFlag");
    NSString *(*yank)(void) = dlsym(RTLD_DEFAULT, "_NSYankFromKillRing");
    CHECK(initRing && append && prepend && newSequence && setYanked && resetFlag && yank);
    if (!(initRing && append && prepend && newSequence && setYanked && resetFlag && yank))
        return;

    initRing();
    newSequence();
    resetFlag();
    append(@"b");
    resetFlag();
    prepend(@"a");
    resetFlag();
    append(@"c");
    CHECK([yank() isEqualToString: @"abc"]);
    // as on macOS 26.7.3: it undoes the yanked state, so the next kill adds to
    // the entry; without it, the next kill starts a new one
    setYanked();
    resetFlag();
    append(@"x");
    CHECK([yank() isEqualToString: @"abcx"]);
    setYanked();
    append(@"y");
    CHECK([yank() isEqualToString: @"y"]);
}

static NSString *stringSymbol(const char *name) {
    NSString **symbol = dlsym(RTLD_DEFAULT, name);
    return symbol != NULL ? *symbol : nil;
}

static void test_constants(void) {
    const char *names[] = {"NSPopUpMenuPopupButtonBounds", "NSPopUpMenuPopupButtonLabelOffset",
                           "NSPopUpMenuPopupButtonSize", "NSPopUpMenuPopupButtonWidget",
                           "NSTextCompletionAttributeName", "NSTextInsertionUndoableAttributeName",
                           "_NXSmartPaste"};
    size_t count = sizeof(names) / sizeof(names[0]);
    NSMutableSet *values = [NSMutableSet set];

    for (size_t i = 0; i < count; i++) {
        NSString *value = stringSymbol(names[i]);
        CHECK(value != nil && [value length] > 0);
        if (value != nil)
            [values addObject: value];
    }
    CHECK([values count] == count);
    // The value WebKit itself uses for the same type (WebSmartPastePboardType).
    CHECK([stringSymbol("_NXSmartPaste") isEqualToString: @"NeXT smart paste pasteboard type"]);
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        test_menu_background();
        test_list_box_frame();
        test_focus_ring_style();
        test_accessibility();
        test_kill_ring_operation_flag();
        test_constants();
    }
    if (failures == 0)
        printf("PASS\n");
    return failures != 0;
}
