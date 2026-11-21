/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * NSColor: creating and converting colours, and reading the dynamic system colours' preferences, must not need a
 * window server. The catalog (System) colours do need the display, so none is asked for here. Run it with no
 * DISPLAY or WAYLAND_DISPLAY set.
 */
#import <AppKit/AppKit.h>
#include <stdio.h>

int main(void)
{
    @autoreleasepool {
        NSColor *c = [NSColor colorWithCalibratedWhite: 0.5 alpha: 1.0];
        NSColor *rgb = [c colorUsingColorSpace: [NSColorSpace sRGBColorSpace]];
        NSColor *dyn = [NSColor colorWithName: @"test" dynamicProvider: ^NSColor *(NSAppearance *a) {
            return [NSColor redColor];
        }];
        if (rgb == nil || dyn == nil || [NSColor colorWithSRGBRed: 1 green: 0 blue: 0 alpha: 1] == nil) {
            printf("FAIL: colour creation\n");
            return 1;
        }
    }
    printf("ok\n");
    return 0;
}
