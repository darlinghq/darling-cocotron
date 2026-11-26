// Copyright (C) 2026 Lubos Dolezel
//
// Guest test: -[NSApplication _accentColor], -_setAccentColor: and
// -_effectiveAccentColor, SPI that WebKit uses. Observed on macOS 26.7.3
// (x86_64) for an application without NSAccentColorName in its Info.plist,
// with the same calls.
#import <Cocoa/Cocoa.h>
#include <stdio.h>

@interface NSApplication (AccentColorSPI)
@property (copy, setter=_setAccentColor:) NSColor *_accentColor;
@property (readonly, copy) NSColor *_effectiveAccentColor;
@end

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
        report("no accent color by default", NSApp._accentColor == nil);
        report("no effective accent color by default", NSApp._effectiveAccentColor == nil);

        NSColor *system = [NSColor controlAccentColor];
        NSApp._accentColor = [NSColor redColor];
        report("the accent color is stored", [NSApp._accentColor isEqual: [NSColor redColor]]);
        report("it is the effective accent color", [NSApp._effectiveAccentColor isEqual: [NSColor redColor]]);
        report("controlAccentColor doesn't change", [[NSColor controlAccentColor] isEqual: system]);

        NSColor *translucent = [[NSColor redColor] colorWithAlphaComponent: 0.5];
        NSApp._accentColor = translucent;
        report("alpha is kept", [NSApp._effectiveAccentColor alphaComponent] == 0.5);

        NSApp._accentColor = nil;
        report("nil clears it", NSApp._accentColor == nil && NSApp._effectiveAccentColor == nil);
    }
    return failures != 0;
}
