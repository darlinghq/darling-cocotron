// Copyright (C) 2026 Lubos Dolezel
// The default content hugging and compression resistance priorities of views and controls,
// for views made in code and decoded from an archive without priorities of their own (as from a
// nib). Observed on macOS 10.14.4 and 26.7.3: controls hug vertically at
// NSLayoutPriorityDefaultHigh, a few classes hug like plain views, and a stepper also hugs
// horizontally. A button's default follows its type and bezel style. Covers the QUIRK in
// NSButton.m: the defaults for a few bezel styles changed after macOS 10.14.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(NSView *view, const char *how, NSLayoutPriority horizontal, NSLayoutPriority vertical) {
    NSLayoutPriority h = [view contentHuggingPriorityForOrientation: NSLayoutConstraintOrientationHorizontal];
    NSLayoutPriority v = [view contentHuggingPriorityForOrientation: NSLayoutConstraintOrientationVertical];
    NSLayoutPriority ch = [view contentCompressionResistancePriorityForOrientation: NSLayoutConstraintOrientationHorizontal];
    NSLayoutPriority cv = [view contentCompressionResistancePriorityForOrientation: NSLayoutConstraintOrientationVertical];

    if (h != horizontal || v != vertical || ch != 750 || cv != 750) {
        printf("FAIL %s (%s): hugging %g %g, compression resistance %g %g; expected hugging %g %g, 750 750\n",
               object_getClassName(view), how, h, v, ch, cv, horizontal, vertical);
        failures++;
    }
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        [NSApplication sharedApplication];

        // macOS 11 is AppKit 2022; macOS 10.14 is 1671.
        BOOL modernButtons = NSAppKitVersionNumber >= 2000;
        struct { NSString *name; NSLayoutPriority horizontal, vertical; } classes[] = {
            { @"NSView", 250, 250 },
            { @"NSControl", 250, 750 },
            { @"NSTextField", 250, 750 },
            { @"NSSecureTextField", 250, 750 },
            { @"NSSearchField", 250, 750 },
            { @"NSComboBox", 250, 750 },
            { @"NSButton", 250, modernButtons ? 750 : 250 },
            { @"NSPopUpButton", 250, 750 },
            { @"NSSlider", 250, 750 },
            { @"NSStepper", 750, 750 },
            { @"NSSegmentedControl", 250, 750 },
            { @"NSLevelIndicator", 250, 750 },
            { @"NSColorWell", 250, 250 },
            { @"NSDatePicker", 250, 750 },
            { @"NSImageView", 250, 250 },
            { @"NSProgressIndicator", 250, 750 },
            { @"NSPathControl", 250, 750 },
            { @"NSScrollView", 250, 250 },
            { @"NSBox", 250, 250 },
            { @"NSTableView", 250, 750 },
            { @"NSMatrix", 250, 750 },
            { @"NSStackView", 250, 250 },
            { @"NSSplitView", 250, 250 },
            { @"NSTabView", 250, 250 },
            { @"NSScroller", 250, 750 },
        };

        for (size_t i = 0; i < sizeof(classes) / sizeof(classes[0]); i++) {
            Class class = NSClassFromString(classes[i].name);
            NSView *view = [[class alloc] initWithFrame: NSMakeRect(0, 0, 50, 20)];
            expect(view, "initWithFrame:", classes[i].horizontal, classes[i].vertical);
        }

        // A control decoded from an archive that has no priorities of its own gets its class's defaults.
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject: [[NSTextField alloc] initWithFrame: NSMakeRect(0, 0, 50, 20)]];
        expect([NSKeyedUnarchiver unarchiveObjectWithData: data], "decoded", 250, 750);

        // A button's default follows its type and bezel style; the same on macOS 10.14.4 and 26.7.3.
        struct { NSButtonType type; NSBezelStyle bezel; NSLayoutPriority horizontal, vertical; } buttons[] = {
            { NSButtonTypeMomentaryPushIn, NSBezelStyleRounded, 250, 750 },
            { NSButtonTypeMomentaryPushIn, NSBezelStyleRegularSquare, 250, 250 },
            { NSButtonTypeMomentaryPushIn, NSBezelStyleShadowlessSquare, 250, 250 },
            { NSButtonTypeMomentaryPushIn, NSBezelStyleDisclosure, 750, 750 },
            { NSButtonTypePushOnPushOff, NSBezelStyleCircular, 750, 750 },
            { NSButtonTypeMomentaryPushIn, NSBezelStyleHelpButton, 750, 750 },
            { NSButtonTypeToggle, NSBezelStyleTexturedRounded, 250, 750 },
            { NSButtonTypeMomentaryPushIn, NSBezelStyleRoundRect, 250, 750 },
            { NSButtonTypeMomentaryChange, NSBezelStyleRecessed, 250, 750 },
            { NSButtonTypeMomentaryPushIn, NSBezelStyleRoundedDisclosure, 750, 750 },
            { NSButtonTypeSwitch, NSBezelStyleRounded, 250, 250 },
            { NSButtonTypeRadio, NSBezelStyleCircular, 250, 250 },
            // QUIRK (NSButton.m): these changed after macOS 10.14.
            { NSButtonTypeMomentaryPushIn, NSBezelStyleTexturedSquare, 250, modernButtons ? 250 : 750 },
            { NSButtonTypeMomentaryPushIn, NSBezelStyleSmallSquare, 250, modernButtons ? 250 : 750 },
            { NSButtonTypeMomentaryPushIn, NSBezelStyleInline, 250, modernButtons ? 250 : 750 },
        };
        for (size_t i = 0; i < sizeof(buttons) / sizeof(buttons[0]); i++) {
            NSButton *button = [[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 80, 30)];
            [button setButtonType: buttons[i].type];
            [button setBezelStyle: buttons[i].bezel];
            char how[64];
            snprintf(how, sizeof(how), "type %d bezel %d", (int) buttons[i].type, (int) buttons[i].bezel);
            expect(button, how, buttons[i].horizontal, buttons[i].vertical);
        }
        NSButton *borderless = [[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 80, 30)];
        [borderless setBezelStyle: NSBezelStyleRounded];
        [borderless setBordered: NO];
        expect(borderless, "borderless", 250, 250);
        expect([NSButton buttonWithTitle: @"Push" target: nil action: NULL], "buttonWithTitle:", 250, 750);
        expect([NSButton checkboxWithTitle: @"Check" target: nil action: NULL], "checkboxWithTitle:", 250, 250);
        NSPopUpButton *popUp = [[NSPopUpButton alloc] initWithFrame: NSMakeRect(0, 0, 80, 30) pullsDown: NO];
        expect(popUp, "pop-up", 250, 750);
        [popUp setBezelStyle: NSBezelStyleShadowlessSquare];
        expect(popUp, "square pop-up", 250, 250);

        // A priority that was set stays when the button's look changes, and survives archiving.
        NSButton *button = [[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 80, 30)];
        [button setContentHuggingPriority: 300 forOrientation: NSLayoutConstraintOrientationVertical];
        [button setBezelStyle: NSBezelStyleRounded];
        expect(button, "set to 300", 250, 300);
        data = [NSKeyedArchiver archivedDataWithRootObject: button];
        expect([NSKeyedUnarchiver unarchiveObjectWithData: data], "set to 300, decoded", 250, 300);

        // Priorities set on a view survive archiving.
        NSView *view = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 50, 20)];
        [view setContentHuggingPriority: 750 forOrientation: NSLayoutConstraintOrientationVertical];
        data = [NSKeyedArchiver archivedDataWithRootObject: view];
        expect([NSKeyedUnarchiver unarchiveObjectWithData: data], "decoded after setting", 250, 750);
    }
    if (failures) {
        printf("%d failures\n", failures);
        return 1;
    }
    printf("PASS\n");
    return 0;
}
