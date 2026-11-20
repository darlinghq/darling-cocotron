// Copyright (C) 2026 Lubos Dolezel
//
// A view in a layer-backed hierarchy that redraws part of itself
// (-setNeedsDisplayInRect:, or the overlap with a sibling being redrawn) keeps
// what it drew elsewhere, and the redrawn part starts out clear. -drawRect:
// gets the rect that needs updating; the rest of the view stays as it was.
//
// Pixels are read from the screen by a host program named by PIXEL_GRAB (a
// command taking the window title and "<label> <x> <y>" triples, top-left
// window coordinates, printing "pixel <label> RRGGBB"), such as
//   PIXEL_GRAB="/Volumes/SystemRoot/usr/bin/python3 -I <host path>/quartzcore-metal-layer-plane-grab.py"
// Without PIXEL_GRAB the test cannot read the screen and exits 2.

#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

static NSString *const kTitle = @"layer-partial-redisplay";
static int failures;

@interface Swatch : NSView {
@public
    NSColor *color; // nil: draws nothing
}
@end

@implementation Swatch
- (void)drawRect:(NSRect)rect
{
    if (color) {
        [color set];
        NSRectFill(rect);
    }
}
@end

@interface Backdrop : NSView
@end

@implementation Backdrop
- (void)drawRect:(NSRect)rect
{
    [[NSColor colorWithCalibratedWhite:0.5 alpha:1] set];
    NSRectFill(rect);
}
@end

static void settle(double seconds)
{
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

// Window content is 300x200; y is measured from the top of the content.
static unsigned pixel(int x, int y)
{
    char command[1024];
    snprintf(command, sizeof command, "%s %s p %d %d", getenv("PIXEL_GRAB"), [kTitle UTF8String], x, y);
    FILE *pipe = popen(command, "r");
    char line[256], label[64];
    unsigned value = 0xFFFFFFFF;
    while (pipe != NULL && fgets(line, sizeof line, pipe) != NULL) {
        unsigned v;
        if (sscanf(line, "pixel %63s %x", label, &v) == 2)
            value = v;
    }
    if (pipe != NULL)
        pclose(pipe);
    return value;
}

static BOOL near(unsigned a, unsigned b)
{
    for (int shift = 0; shift < 24; shift += 8) {
        int d = (int)((a >> shift) & 0xFF) - (int)((b >> shift) & 0xFF);
        if (d > 48 || d < -48)
            return NO;
    }
    return YES;
}

static void expectPixel(const char *label, int x, int y, unsigned expected)
{
    unsigned got = pixel(x, y);
    BOOL ok = near(got, expected);
    printf("%s %s: pixel (%d,%d) %06X, expected %06X\n", ok ? "PASS" : "FAIL", label, x, y, got, expected);
    failures += !ok;
}

enum { RED = 0xFF0000, BLUE = 0x0000FF, GREEN = 0x00FF00, GRAY = 0x808080 };

int main(void)
{
    if (!getenv("PIXEL_GRAB")) {
        printf("PIXEL_GRAB is not set; this test reads the window from the screen\n");
        return 2;
    }
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 300, 200)
                                                       styleMask:NSWindowStyleMaskTitled
                                                         backing:NSBackingStoreBuffered
                                                           defer:NO];
        [window setTitle:kTitle];
        Backdrop *root = [[Backdrop alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)];
        [root setWantsLayer:YES];
        [window setContentView:root];

        // One view, a dirty rect in its left half.
        Swatch *swatch = [[Swatch alloc] initWithFrame:NSMakeRect(20, 100, 200, 80)];
        swatch->color = [NSColor redColor];
        [root addSubview:swatch];
        [window makeKeyAndOrderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];
        settle(3);
        expectPixel("first display", 170, 60, RED);

        swatch->color = [NSColor blueColor];
        [swatch setNeedsDisplayInRect:NSMakeRect(0, 0, 100, 80)];
        settle(1.5);
        expectPixel("dirty half redrawn", 70, 60, BLUE);
        expectPixel("rest of the view kept", 170, 60, RED);

        // The redrawn part starts clear: a view drawing nothing there shows what is below.
        swatch->color = nil;
        [swatch setNeedsDisplayInRect:NSMakeRect(100, 0, 100, 80)];
        settle(1.5);
        expectPixel("redrawn part starts clear", 170, 60, GRAY);
        expectPixel("other half kept", 70, 60, BLUE);

        // Overlapping siblings: redrawing the top one redraws the overlap of the one below.
        Swatch *below = [[Swatch alloc] initWithFrame:NSMakeRect(20, 10, 120, 60)];
        below->color = [NSColor greenColor];
        Swatch *above = [[Swatch alloc] initWithFrame:NSMakeRect(130, 10, 120, 60)];
        above->color = [NSColor redColor];
        [root addSubview:below];
        [root addSubview:above];
        settle(1.5);
        [above setNeedsDisplay:YES];
        settle(1.5);
        expectPixel("view below an overlapping sibling kept", 60, 160, GREEN);
        expectPixel("overlapping sibling", 200, 160, RED);
    }
    printf("failures=%d\n", failures);
    return failures ? 1 : 0;
}
