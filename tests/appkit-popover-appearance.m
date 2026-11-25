// Copyright (C) 2026 Lubos Dolezel
//
// NSPopover's appearance (NSAppearanceCustomization,
// https://developer.apple.com/documentation/appkit/nsappearancecustomization).
// It has none of its own at first. Its effective appearance is the one set, or
// without one the vibrant appearance that matches the application's: this is
// the quirk in NSPopover.m (observed on macOS 26.7.3, x86_64).
#import <AppKit/AppKit.h>

static int failures;

static void report(const char *name, BOOL ok)
{
    printf("%s: %s\n", ok ? "PASS" : "FAIL", name);
    if (!ok)
        failures++;
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSPopover *popover = [[[NSPopover alloc] init] autorelease];
        report("conforms to NSAppearanceCustomization", [popover conformsToProtocol: @protocol(NSAppearanceCustomization)]);
        report("no appearance at first", popover.appearance == nil);

        NSAppearance *dark = [NSAppearance appearanceNamed: NSAppearanceNameDarkAqua];
        popover.appearance = dark;
        report("set: kept and effective", popover.appearance == dark
               && [popover.effectiveAppearance.name isEqualToString: NSAppearanceNameDarkAqua]);

        popover.appearance = nil;
        NSApp.appearance = [NSAppearance appearanceNamed: NSAppearanceNameAqua];
        report("quirk: a light application, vibrant light",
               [popover.effectiveAppearance.name isEqualToString: NSAppearanceNameVibrantLight]);
        NSApp.appearance = dark;
        report("quirk: a dark application, vibrant dark",
               [popover.effectiveAppearance.name isEqualToString: NSAppearanceNameVibrantDark]);
    }
    return failures != 0;
}
