// Copyright (C) 2026 Lubos Dolezel
//
// Guest test: +[NSApplication _accessibilityInitialize], the SPI that WebKit's
// web content process calls. Observed on macOS 26.7.3 (x86_64) with the same
// calls: NSApp exists afterwards, an instance of the class the message was
// sent to, and calling it again is harmless.
#import <Cocoa/Cocoa.h>
#include <stdio.h>
#include <string.h>

@interface NSApplication (AccessibilitySPI)
+ (void)_accessibilityInitialize;
@end

@interface TestApplication : NSApplication
@end
@implementation TestApplication
@end

static int failures;

static void report(const char *name, BOOL ok)
{
    printf("%s: %s\n", ok ? "PASS" : "FAIL", name);
    if (!ok)
        failures++;
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        report("implemented", [NSApplication respondsToSelector: @selector(_accessibilityInitialize)]);
        report("no NSApp before", NSApp == nil);
        // The subclass case needs a process of its own, as NSApp is made once.
        BOOL subclass = argc > 1 && strcmp(argv[1], "subclass") == 0;
        if (subclass) {
            [TestApplication _accessibilityInitialize];
            report("sent to a subclass, NSApp is an instance of it", [NSApp isMemberOfClass: [TestApplication class]]);
        } else {
            [NSApplication _accessibilityInitialize];
            report("NSApp exists afterwards", NSApp != nil && [NSApp isMemberOfClass: [NSApplication class]]);
        }
        NSApplication *app = NSApp;
        [NSApplication _accessibilityInitialize];
        report("a second call keeps the same NSApp", NSApp == app);
    }
    return failures != 0;
}
