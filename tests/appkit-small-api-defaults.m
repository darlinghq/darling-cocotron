/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Values and defaults of small AppKit API as observed on macOS (the
// observations are in the project's Mac evidence notes): NSImage capInsets and
// resizingMode, NSTextField allowsEditingTextAttributes, NSVisualEffectView
// maskImage and emphasized, NSApplicationLoad, NSStatusItem behavior, button,
// visible and the action forwarded to the button, +colorForControlTint:, and
// NSAccessibilityFullScreenButtonAttribute.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <math.h>

static int failures;
#define CHECK(cond, what) do { if (!(cond)) { printf("FAIL: %s\n", what); failures++; } } while (0)

static BOOL rgbIs(NSColor *color, double r, double g, double b) {
    color = [color colorUsingColorSpace: [NSColorSpace sRGBColorSpace]];
    return fabs([color redComponent] - r) < 0.002 && fabs([color greenComponent] - g) < 0.002 &&
           fabs([color blueComponent] - b) < 0.002;
}

int main(void) {
    @autoreleasepool {
        CHECK([NSAccessibilityFullScreenButtonAttribute isEqual: @"AXFullScreenButton"], "full screen button attribute value");

        CHECK(NSImageResizingModeStretch == 0 && NSImageResizingModeTile == 1, "NSImageResizingMode values");
        NSImage *image = [[NSImage alloc] initWithSize: NSMakeSize(4, 4)];
        NSEdgeInsets zero = {0, 0, 0, 0};
        NSEdgeInsets got = [image capInsets];
        CHECK(memcmp(&got, &zero, sizeof zero) == 0, "capInsets default zero");
        CHECK([image resizingMode] == NSImageResizingModeStretch, "resizingMode default stretch");
        [image setCapInsets: NSEdgeInsetsMake(1, 2, 3, 4)];
        [image setResizingMode: NSImageResizingModeTile];
        NSImage *copy = [image copy];
        got = [copy capInsets];
        CHECK(got.top == 1 && got.left == 2 && got.bottom == 3 && got.right == 4, "capInsets copied");
        CHECK([copy resizingMode] == NSImageResizingModeTile, "resizingMode copied");

        NSTextField *field = [[NSTextField alloc] initWithFrame: NSMakeRect(0, 0, 50, 20)];
        CHECK(![field allowsEditingTextAttributes], "text field allowsEditingTextAttributes default NO");
        [field setAllowsEditingTextAttributes: YES];
        CHECK([field allowsEditingTextAttributes] && [[field cell] allowsEditingTextAttributes],
              "text field setting reaches the cell");

        NSVisualEffectView *effect = [[NSVisualEffectView alloc] initWithFrame: NSMakeRect(0, 0, 50, 20)];
        CHECK([effect maskImage] == nil && ![effect isEmphasized], "visual effect view defaults");
        [effect setMaskImage: image];
        [effect setEmphasized: YES];
        CHECK([effect maskImage] == image && [effect isEmphasized], "visual effect view setters");

        CHECK(NSApplicationLoad() == YES && NSApp != nil, "NSApplicationLoad");

        CHECK(rgbIs([NSColor colorForControlTint: NSDefaultControlTint], 0.608, 0.757, 0.910), "default tint colour");
        CHECK(rgbIs([NSColor colorForControlTint: NSBlueControlTint], 0.608, 0.757, 0.910), "blue tint colour");
        CHECK(rgbIs([NSColor colorForControlTint: NSGraphiteControlTint], 0.729, 0.757, 0.800), "graphite tint colour");
        CHECK(rgbIs([NSColor colorForControlTint: NSClearControlTint], 0.82, 0.82, 0.82), "clear tint colour");
        CHECK(rgbIs([NSColor colorForControlTint: (NSControlTint) 99], 0.82, 0.82, 0.82), "unknown tint colour");

        NSStatusItem *item = [[NSStatusBar systemStatusBar] statusItemWithLength: NSVariableStatusItemLength];
        CHECK([item behavior] == 0, "status item behavior default");
        CHECK([item isVisible], "status item visible by default");
        CHECK(NSStatusItemBehaviorRemovalAllowed == 2 && NSStatusItemBehaviorTerminationOnRemoval == 4, "behavior values");
        NSStatusBarButton *button = [item button];
        CHECK(button != nil && [button isKindOfClass: [NSButton class]], "status item has a button");
        CHECK(![button appearsDisabled], "button appearsDisabled default");
        [item setTarget: NSApp];
        [item setAction: @selector(hide:)];
        CHECK([button target] == NSApp && [button action] == @selector(hide:), "target and action reach the button");
        [item setVisible: NO];
        CHECK(![item isVisible], "status item hidden");
        [item setBehavior: NSStatusItemBehaviorRemovalAllowed];
        CHECK([item behavior] == NSStatusItemBehaviorRemovalAllowed, "behavior set");
        [[NSStatusBar systemStatusBar] removeStatusItem: item];
    }
    printf(failures ? "FAIL\n" : "PASS\n");
    return failures != 0;
}
