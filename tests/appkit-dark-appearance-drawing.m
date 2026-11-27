// Copyright (C) 2026 Lubos Dolezel
//
// Views draw with the appearance they have: a window set to DarkAqua gives -drawRect: of its views
// +[NSAppearance currentDrawingAppearance] of DarkAqua, a dynamic colour such as windowBackgroundColor
// resolves for it, and -effectiveAppearance of the content view (a view without a superview) is the window's.
// A help bezel button (NSBezelStyleHelpButton) draws a round button and has the sizes macOS 10.14.4 gives:
// 25 x 25 regular, 18 x 19 small, 16 x 17 mini (26.7.3: 24, 20, 16, which are not followed).
// Usage: appkit-dark-appearance-drawing [hold seconds]   (with the hold the window stays up for a screenshot)
// Build: clang -framework AppKit appkit-dark-appearance-drawing.m (no ARC)
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

@interface ProbeView : NSView {
@public
    NSString *drawingAppearance;
    int draws;
}
@end
@implementation ProbeView
- (void) drawRect: (NSRect) rect {
    draws++;
    [drawingAppearance release];
    drawingAppearance = [[[NSAppearance currentDrawingAppearance] name] copy];
    [[NSColor windowBackgroundColor] setFill];
    NSRectFill([self bounds]);
}
@end

static double brightness(NSBitmapImageRep *rep, int x, int y) {
    NSColor *c = [[rep colorAtX: x y: y] colorUsingColorSpace: [NSColorSpace genericRGBColorSpace]];
    return ([c redComponent] + [c greenComponent] + [c blueComponent]) / 3;
}

static void drawWith(NSAppearanceName name, double *backgroundBrightness, NSString **seen) {
    NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 200, 120)
            styleMask: NSWindowStyleMaskTitled backing: NSBackingStoreBuffered defer: NO];
    [window setAppearance: [NSAppearance appearanceNamed: name]];
    ProbeView *view = [[[ProbeView alloc] initWithFrame: NSMakeRect(0, 0, 200, 120)] autorelease];
    [window setContentView: view];
    CHECK([[[view effectiveAppearance] name] isEqualToString: name]);
    NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect: [view bounds]];
    [view cacheDisplayInRect: [view bounds] toBitmapImageRep: rep];
    CHECK(view->draws > 0);
    *seen = [[view->drawingAppearance copy] autorelease];
    *backgroundBrightness = brightness(rep, 100, 60);
    [window orderOut: nil];
    [window release];
}

int main(int argc, char **argv) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [NSApplication sharedApplication];

    double light = 0, dark = 0;
    NSString *lightSeen = nil, *darkSeen = nil;
    drawWith(NSAppearanceNameAqua, &light, &lightSeen);
    drawWith(NSAppearanceNameDarkAqua, &dark, &darkSeen);
    CHECK([lightSeen isEqualToString: NSAppearanceNameAqua]);
    CHECK([darkSeen isEqualToString: NSAppearanceNameDarkAqua]);
    CHECK(light > 0.7);
    CHECK(dark < 0.4);

    static const CGFloat widths[3] = {25, 18, 16}, heights[3] = {25, 19, 17};
    for (int i = 0; i < 3; i++) {
        NSButton *button = [[[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)] autorelease];
        [button setBezelStyle: NSBezelStyleHelpButton];
        [button setTitle: @""];
        [[button cell] setControlSize: (NSControlSize) i];
        NSSize size = [[button cell] cellSize];
        if (size.width != widths[i] || size.height != heights[i])
            fprintf(stderr, "  help button, control size %d: %gx%g, expected %gx%g\n", i, size.width, size.height, widths[i], heights[i]);
        CHECK(size.width == widths[i] && size.height == heights[i]);
    }

    // The regular help button is a circle: its corners stay clear, its middle is filled.
    NSButton *help = [[[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 25, 25)] autorelease];
    [help setBezelStyle: NSBezelStyleHelpButton];
    [help setTitle: @""];
    NSBitmapImageRep *rep = [help bitmapImageRepForCachingDisplayInRect: [help bounds]];
    [help cacheDisplayInRect: [help bounds] toBitmapImageRep: rep];
    CHECK([[rep colorAtX: 0 y: 0] alphaComponent] < 0.1);
    CHECK([[rep colorAtX: 24 y: 24] alphaComponent] < 0.1);
    CHECK([[rep colorAtX: 5 y: 12] alphaComponent] > 0.5);

    if (argc > 1) {
        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 360, 160)
                styleMask: NSWindowStyleMaskTitled backing: NSBackingStoreBuffered defer: NO];
        [window setTitle: @"q3 appearance"];
        [window setAppearance: [NSAppearance appearanceNamed: argc > 2 ? NSAppearanceNameAqua : NSAppearanceNameDarkAqua]];
        NSView *content = [[[ProbeView alloc] initWithFrame: NSMakeRect(0, 0, 360, 160)] autorelease];
        [window setContentView: content];
        NSButton *h = [[[NSButton alloc] initWithFrame: NSMakeRect(20, 100, 25, 25)] autorelease];
        [h setBezelStyle: NSBezelStyleHelpButton]; [h setTitle: @""];
        NSButton *t = [[[NSButton alloc] initWithFrame: NSMakeRect(70, 100, 90, 24)] autorelease];
        [t setBezelStyle: NSBezelStyleTexturedRounded]; [t setTitle: @"Textured"];
        NSButton *r = [[[NSButton alloc] initWithFrame: NSMakeRect(180, 100, 90, 24)] autorelease];
        [r setBezelStyle: NSBezelStyleRounded]; [r setTitle: @"Push"];
        NSTextField *label = [NSTextField labelWithString: @"Label text"];
        [label setFrame: NSMakeRect(20, 40, 200, 20)];
        [content addSubview: h]; [content addSubview: t]; [content addSubview: r]; [content addSubview: label];
        [window makeKeyAndOrderFront: nil];
        [NSApp activateIgnoringOtherApps: YES];
        [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: atof(argv[1])]];
    }
    if (failures == 0)
        printf("PASS appkit-dark-appearance-drawing\n");
    [pool release];
    return failures != 0;
}
