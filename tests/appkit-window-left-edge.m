// Copyright (C) 2026 Lubos Dolezel
//
// Guest side of tests/x11-window-left-edge.sh: a window without a frame of its own (a titled window with a
// full-size content view and a transparent title bar, which Darling outlines itself) holding labels, a
// progress bar that is redrawn all the time, and layer-backed views of several classes below it. The window
// is kept on screen for the number of seconds given as the first argument, while the harness reads its pixels.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    @autoreleasepool {
        int hold = argc > 1 ? atoi(argv[1]) : 10;
        [NSApplication sharedApplication];
        NSWindow *w = [[NSWindow alloc]
            initWithContentRect:NSMakeRect(100, 300, 420, 160)
                      styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskFullSizeContentView
                        backing:NSBackingStoreBuffered
                          defer:NO];
        [w setTitle:@"Left edge test"];
        [w setTitlebarAppearsTransparent:YES];
        NSView *c = [w contentView];
        NSTextField *label = [NSTextField labelWithString:@"Extracting"];
        [label setFrame:NSMakeRect(20, 120, 200, 20)];
        [c addSubview:label];
        NSProgressIndicator *bar =
            [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(20, 100, 380, 15)];
        [bar setStyle:NSProgressIndicatorStyleBar];
        [bar setIndeterminate:NO];
        [c addSubview:bar];

        // Bands spanning the whole width, one below the other: two layer-backed ones (their
        // native windows start at the left edge) and one drawn into the window.
        NSTabView *tabs = [[NSTabView alloc] initWithFrame:NSMakeRect(0, 0, 420, 40)];
        [tabs setTabViewType:NSNoTabsNoBorder];
        [tabs setWantsLayer:YES];
        [c addSubview:tabs];
        NSVisualEffectView *effect =
            [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(0, 40, 420, 20)];
        [c addSubview:effect];
        NSView *layered = [[NSView alloc] initWithFrame:NSMakeRect(0, 60, 420, 30)];
        [layered setWantsLayer:YES];
        [c addSubview:layered];

        [w makeKeyAndOrderFront:nil];
        // The window is flushed on every pass; only the label and the bar are redrawn.
        for (int i = 0; i < hold * 10; i++) {
            [bar setDoubleValue:(i % 100)];
            [label setStringValue:[NSString stringWithFormat:@"Extracting %d", i]];
            [w displayIfNeeded];
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        }
    }
    return 0;
}
