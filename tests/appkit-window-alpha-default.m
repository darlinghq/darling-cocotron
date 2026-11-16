// Copyright (C) 2026 Lubos Dolezel
//
// A new window is fully opaque: -alphaValue answers 1.0 until it is set, and answers what was set.
// Build: guest-cc.sh -o t appkit-window-alpha-default.m -framework Cocoa
#import <Cocoa/Cocoa.h>

static int failures;
#define CHECK(c, ...) do { if (!(c)) { failures++; printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 200, 100)
                                                  styleMask:NSWindowStyleMaskTitled
                                                    backing:NSBackingStoreBuffered defer:YES];
        CHECK([w alphaValue] == 1.0, "a new window is opaque, alphaValue is %f", (double)[w alphaValue]);
        [w setAlphaValue:0.25];
        CHECK([w alphaValue] == 0.25, "alphaValue after setting 0.25 is %f", (double)[w alphaValue]);
        [w setAlphaValue:0];
        CHECK([w alphaValue] == 0.0, "alphaValue after setting 0 is %f", (double)[w alphaValue]);
        NSWindow *b = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 50, 50)
                                                  styleMask:NSWindowStyleMaskBorderless
                                                    backing:NSBackingStoreBuffered defer:YES];
        CHECK([b alphaValue] == 1.0, "a new borderless window is opaque, alphaValue is %f", (double)[b alphaValue]);
    }
    printf(failures ? "FAILED\n" : "PASSED\n");
    return failures != 0;
}
