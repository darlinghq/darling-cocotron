// Copyright (C) 2026 Lubos Dolezel
//
// Guest test: -[CALayer contentsOpaque] / -setContentsOpaque:, SPI that WebKit
// sets on its compositing layers. Observed on macOS 26.7.3 (x86_64): NO by
// default, independent of the public opaque property in both directions,
// readable through key-value coding, default value NO, and no implicit action.
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>

@interface CALayer (ContentsOpaqueSPI)
@property BOOL contentsOpaque;
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
        CALayer *layer = [CALayer layer];
        report("implemented", [layer respondsToSelector: @selector(setContentsOpaque:)] && [layer respondsToSelector: @selector(contentsOpaque)]);
        report("NO by default", !layer.contentsOpaque);
        layer.contentsOpaque = YES;
        report("YES after setting YES", layer.contentsOpaque);
        report("setting it leaves opaque alone", !layer.opaque);
        layer.opaque = NO;
        report("setting opaque leaves it alone", layer.contentsOpaque);
        layer.opaque = YES;
        layer.contentsOpaque = NO;
        report("NO with opaque YES", !layer.contentsOpaque && layer.opaque);
        report("readable through key-value coding", [[layer valueForKey: @"contentsOpaque"] isEqual: @NO]);
        report("default value NO", [[CALayer defaultValueForKey: @"contentsOpaque"] isEqual: @NO]);
        report("no implicit action", [layer actionForKey: @"contentsOpaque"] == nil);
    }
    return failures != 0;
}
