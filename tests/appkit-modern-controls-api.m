// Copyright (C) 2026 Lubos Dolezel
//
// The macOS 13 to 26 control API: NSComboButton, NSItemBadge, NSGlassEffectView and its container,
// NSToolbarItem.badge, borderShape and tintProminence, and the enumeration values of the public AppKit
// headers. The shapes and defaults are those of the public headers and of macOS 26.7.3 (observed by
// running the same calls there). Exit status 77 means the window system is not available.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

_Static_assert(NSControlBorderShapeAutomatic == 0 && NSControlBorderShapeCapsule == 1
               && NSControlBorderShapeRoundedRectangle == 2 && NSControlBorderShapeCircle == 3, "border shape");
_Static_assert(NSTintProminenceAutomatic == 0 && NSTintProminenceNone == 1
               && NSTintProminencePrimary == 2 && NSTintProminenceSecondary == 3, "tint prominence");
_Static_assert(NSComboButtonStyleSplit == 0 && NSComboButtonStyleUnified == 1, "combo button style");
_Static_assert(NSGlassEffectViewStyleRegular == 0 && NSGlassEffectViewStyleClear == 1, "glass style");
_Static_assert(NSTokenStyleDefault == 0 && NSTokenStyleNone == 1 && NSTokenStyleRounded == 2
               && NSTokenStyleSquared == 3 && NSTokenStylePlainSquared == 4, "token style");
_Static_assert(NSVisualEffectMaterialAppearanceBased == 0 && NSVisualEffectMaterialLight == 1
               && NSVisualEffectMaterialDark == 2 && NSVisualEffectMaterialMediumLight == 8
               && NSVisualEffectMaterialUltraDark == 9, "visual effect material");
_Static_assert(NSAccessibilityOrientationUnknown == 0 && NSAccessibilityOrientationVertical == 1
               && NSAccessibilityOrientationHorizontal == 2, "orientation");

@interface Target : NSObject { @public int count; }
- (void) fire: (id) sender;
@end
@implementation Target
- (void) fire: (id) sender { count++; }
@end

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];

        CHECK(NSPlainTextTokenStyle == NSTokenStyleNone);
        CHECK([NSImageHintUserInterfaceLayoutDirection isEqualToString: @"NSImageHintUserInterfaceLayoutDirection"]);
        CHECK(@protocol(NSMenuItemValidation) != nil);

        // NSItemBadge
        CHECK([[NSItemBadge badgeWithText: @"Hi"].text isEqualToString: @"Hi"]);
        CHECK([[NSItemBadge badgeWithCount: 3].text isEqualToString: @"3"]);
        CHECK([[NSItemBadge indicatorBadge].text length] == 0);
        NSString *thousand = [NSNumberFormatter localizedStringFromNumber: @1234
                                                              numberStyle: NSNumberFormatterDecimalStyle];
        CHECK([[NSItemBadge badgeWithCount: 1234].text isEqualToString: thousand]);
        NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier: @"probe"];
        CHECK(item.badge == nil);
        NSItemBadge *badge = [NSItemBadge badgeWithText: @"7"];
        item.badge = badge;
        CHECK([item.badge.text isEqualToString: @"7"]);
        item.badge = nil;
        CHECK(item.badge == nil);

        // NSComboButton
        Target *target = [Target new];
        NSMenu *menu = [[NSMenu alloc] initWithTitle: @"m"];
        [menu addItemWithTitle: @"One" action: NULL keyEquivalent: @""];
        NSComboButton *combo = [NSComboButton comboButtonWithTitle: @"Go" menu: menu target: target action: @selector(fire:)];
        CHECK([combo.title isEqualToString: @"Go"]);
        CHECK(combo.image == nil);
        CHECK(combo.menu == menu);
        CHECK(combo.style == NSComboButtonStyleSplit);
        CHECK(combo.imageScaling == NSImageScaleProportionallyDown);
        CHECK(combo.target == target && combo.action == @selector(fire:));
        [combo performClick: nil];
        CHECK(target->count == 1);
        combo.style = NSComboButtonStyleUnified;
        CHECK(combo.style == NSComboButtonStyleUnified);
        combo.title = @"Run";
        CHECK([combo.title isEqualToString: @"Run"]);
        NSImage *image = [NSImage imageNamed: NSImageNameAddTemplate];
        NSComboButton *withImage = [NSComboButton comboButtonWithImage: image menu: nil target: nil action: NULL];
        CHECK(withImage.image == image);
        CHECK([withImage.title length] == 0);
        CHECK(withImage.menu != nil);
        NSComboButton *both = [NSComboButton comboButtonWithTitle: @"T" image: image menu: menu target: nil action: NULL];
        CHECK(both.image == image && [both.title isEqualToString: @"T"]);

        // The button draws something.
        NSRect frame = combo.frame;
        NSBitmapImageRep *rep = [combo bitmapImageRepForCachingDisplayInRect: combo.bounds];
        [combo cacheDisplayInRect: combo.bounds toBitmapImageRep: rep];
        BOOL drewSomething = NO;
        for (NSInteger y = 0; y < rep.pixelsHigh && !drewSomething; y++)
            for (NSInteger x = 0; x < rep.pixelsWide; x++)
                if ([[rep colorAtX: x y: y] alphaComponent] > 0.01) { drewSomething = YES; break; }
        CHECK(drewSomething);
        CHECK(frame.size.width > 0 && frame.size.height > 0);

        // NSGlassEffectView and its container
        NSGlassEffectView *glass = [[NSGlassEffectView alloc] initWithFrame: NSMakeRect(0, 0, 40, 40)];
        CHECK(glass.style == NSGlassEffectViewStyleRegular);
        CHECK(glass.cornerRadius == 8.0);
        CHECK(glass.tintColor == nil && glass.contentView == nil);
        NSView *content = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)];
        glass.contentView = content;
        CHECK(glass.contentView == content && content.superview == glass);
        glass.contentView = nil;
        CHECK(content.superview == nil);
        glass.cornerRadius = 3;
        glass.style = NSGlassEffectViewStyleClear;
        glass.tintColor = [NSColor redColor];
        CHECK(glass.cornerRadius == 3 && glass.style == NSGlassEffectViewStyleClear);
        CHECK([glass.tintColor isEqual: [NSColor redColor]]);
        NSGlassEffectContainerView *container = [[NSGlassEffectContainerView alloc] initWithFrame: NSMakeRect(0, 0, 40, 40)];
        CHECK(container.spacing == 0 && container.contentView == nil);
        container.spacing = 5;
        container.contentView = glass;
        CHECK(container.spacing == 5 && glass.superview == container);

        // Control presentation properties
        NSButton *button = [[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)];
        CHECK(button.borderShape == NSControlBorderShapeAutomatic && button.tintProminence == NSTintProminenceAutomatic);
        button.borderShape = NSControlBorderShapeCapsule;
        button.tintProminence = NSTintProminenceSecondary;
        CHECK(button.borderShape == NSControlBorderShapeCapsule && button.tintProminence == NSTintProminenceSecondary);
        NSSegmentedControl *segmented = [[NSSegmentedControl alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)];
        CHECK(segmented.borderShape == NSControlBorderShapeAutomatic);
        segmented.borderShape = NSControlBorderShapeCircle;
        CHECK(segmented.borderShape == NSControlBorderShapeCircle);
        NSSlider *slider = [[NSSlider alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)];
        CHECK(slider.tintProminence == NSTintProminenceAutomatic);
        slider.tintProminence = NSTintProminenceNone;
        CHECK(slider.tintProminence == NSTintProminenceNone);
    }

    if (failures == 0)
        printf("PASS: modern control API\n");
    return failures ? 1 : 0;
}
