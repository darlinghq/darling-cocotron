// Copyright (C) 2026 Lubos Dolezel
//
// Guest test: +[NSApplication _preventDockConnections], the SPI that WebKit's
// web content process calls. Observed on macOS 26.7.3 (x86_64) with the same
// calls: it can be called before NSApp exists, more than once, and after, and
// the application's activation policy behaves as without it.
#import <Cocoa/Cocoa.h>
#include <stdio.h>

@interface NSApplication (DockSPI)
+ (void)_preventDockConnections;
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
        report("implemented", [NSApplication respondsToSelector: @selector(_preventDockConnections)]);
        [NSApplication _preventDockConnections];
        report("before NSApp exists", NSApp == nil);
        [NSApplication _preventDockConnections];
        [NSApplication sharedApplication];
        [NSApplication _preventDockConnections];
        report("after NSApp exists", NSApp != nil);
        report("activation policy can still be set",
               [NSApp setActivationPolicy: NSApplicationActivationPolicyRegular]
               && [NSApp activationPolicy] == NSApplicationActivationPolicyRegular);
    }
    return failures != 0;
}
