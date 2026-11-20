// Copyright (C) 2026 Lubos Dolezel
//
// How an open panel is presented. Run with "sheet <seconds>" (beginSheetModalForWindow:), "modal <seconds>" (runModal)
// or "modeless <seconds>" (begin) it opens the panel over a titled window, prints what AppKit reports about it and
// keeps it up for the given time, so that a script can ask the window system about the window (the .sh drivers do):
//   READY <kind>
//   WIN doc <x> <y> <w> <h>        the document window's frame (Cocoa coordinates)
//   WIN panel <x> <y> <w> <h>      the panel's frame
//   SCREEN <w> <h>
// A sheet is a document-modal panel attached to the window (-isSheet, -sheetParent, -attachedSheet); a panel run modally
// or modelessly is a titled window that is not a sheet. These are checked here from AppKit's side; what the window
// system does with the window is checked by the drivers. After the panel is dismissed the document window must be
// visible again, with its content drawn (the driver compares pixels). Behaviour observed on macOS 26.7.3 (style masks,
// sheet attachment, sheet centred horizontally on the window and below its title bar; vd-upstream/mac-probes/
// open-panel-presentation.m).
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>

static int failures;
#define CHECK(...) do { if (!(__VA_ARGS__)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #__VA_ARGS__); failures++; } } while (0)

static NSWindow *doc;
static NSOpenPanel *panel;
static NSString *kind;
static NSTimeInterval seconds = 3;
static BOOL windowSystemPlaces; // the compositor decides where a window goes (Wayland): the position is not checked

static void spin(NSTimeInterval s) {
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: s]];
}

// A view that paints one colour, so that stale pixels of the panel on the window are told from its content.
@interface Fill : NSView
@end
@implementation Fill
- (void) drawRect: (NSRect) r {
    [[NSColor colorWithCalibratedRed: 0.1 green: 0.6 blue: 0.2 alpha: 1] setFill];
    NSRectFill([self bounds]);
}
@end

@interface D : NSObject <NSApplicationDelegate>
@end
@implementation D
- (void) applicationDidFinishLaunching: (NSNotification *) n {
    NSScreen *screen = [NSScreen mainScreen];
    doc = [[NSWindow alloc] initWithContentRect: NSMakeRect(200, NSHeight([screen frame]) - 700, 640, 420)
                                      styleMask: NSTitledWindowMask | NSClosableWindowMask | NSResizableWindowMask
                                        backing: NSBackingStoreBuffered defer: NO];
    [doc setTitle: @"opp-doc"];
    [doc setContentView: [[[Fill alloc] initWithFrame: NSMakeRect(0, 0, 640, 420)] autorelease]];
    [doc makeKeyAndOrderFront: nil];
    [NSApp activateIgnoringOtherApps: YES];
    [self performSelector: @selector(open) withObject: nil afterDelay: 1.0];
}
- (void) report {
    NSRect f = [panel frame], d = [doc frame];
    printf("SCREEN %.0f %.0f\n", NSWidth([[NSScreen mainScreen] frame]), NSHeight([[NSScreen mainScreen] frame]));
    printf("WIN doc %.0f %.0f %.0f %.0f\n", d.origin.x, d.origin.y, d.size.width, d.size.height);
    printf("WIN panel %.0f %.0f %.0f %.0f\n", f.origin.x, f.origin.y, f.size.width, f.size.height);
    printf("INFO styleMask=0x%lx isSheet=%d sheetParent=%s attachedSheet=%s title='%s'\n", (unsigned long) [panel styleMask],
           [panel isSheet], [panel sheetParent] == doc ? "doc" : "nil", [doc attachedSheet] == panel ? "panel" : "nil",
           [[panel title] UTF8String]);
    fflush(stdout);
}
- (void) open {
    panel = [NSOpenPanel openPanel];
    if ([kind isEqual: @"sheet"]) {
        [panel beginSheetModalForWindow: doc completionHandler: ^(NSModalResponse r) {
            printf("ENDED %ld\n", (long) r);
            fflush(stdout);
        }];
        spin(0.7);
        CHECK([panel isSheet]);
        CHECK([panel styleMask] & NSDocModalWindowMask);
        CHECK([panel sheetParent] == doc);
        CHECK([doc attachedSheet] == panel);
        // centred on the window horizontally, below its title bar (the top of the content area)
        NSRect f = [panel frame], c = [doc convertRectToScreen: [[doc contentView] frame]];
        if (!windowSystemPlaces) {
            CHECK(fabs(NSMidX(f) - NSMidX([doc frame])) < 2);
            CHECK(fabs(NSMaxY(f) - NSMaxY(c)) < 2);
        }
        [self report];
        printf("READY sheet\n");
        fflush(stdout);
        [self performSelector: @selector(finish) withObject: nil afterDelay: seconds];
    } else if ([kind isEqual: @"modeless"]) {
        [panel beginWithCompletionHandler: ^(NSModalResponse r) {
            printf("ENDED %ld\n", (long) r);
            fflush(stdout);
            [self done];
        }];
        spin(0.7);
        CHECK(![panel isSheet]);
        CHECK([panel styleMask] & NSTitledWindowMask);
        [self report];
        printf("READY modeless\n");
        fflush(stdout);
        [self performSelector: @selector(finish) withObject: nil afterDelay: seconds];
    } else {
        [self performSelector: @selector(modalReady) withObject: nil afterDelay: 0.7 inModes: @[NSRunLoopCommonModes]];
        [self performSelector: @selector(finish) withObject: nil afterDelay: seconds inModes: @[NSRunLoopCommonModes]];
        NSModalResponse r = [panel runModal];
        printf("ENDED %ld\n", (long) r);
        fflush(stdout);
        [self done];
    }
}
- (void) modalReady {
    CHECK(![panel isSheet]);
    CHECK([panel styleMask] & NSTitledWindowMask);
    CHECK([NSApp modalWindow] == panel);
    [self report];
    printf("READY modal\n");
    fflush(stdout);
}
- (void) finish {
    if ([kind isEqual: @"sheet"]) {
        [panel cancel: nil];
        spin(0.7);
        CHECK([doc attachedSheet] == nil);
        CHECK(![panel isVisible]);
        [self done];
    } else if ([kind isEqual: @"modeless"]) {
        [panel cancel: nil];
    } else {
        [panel cancel: nil];
    }
}
- (void) done {
    // the panel is gone; the document window stays up for the driver's pixel check
    spin(0.7);
    CHECK(![panel isVisible]);
    CHECK([doc isVisible]);
    printf("DISMISSED\n");
    fflush(stdout);
    spin(2.0);
    printf(failures ? "FAIL\n" : "PASS\n");
    fflush(stdout);
    exit(failures ? 1 : 0);
}
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        kind = argc > 1 ? [NSString stringWithUTF8String: argv[1]] : @"sheet";
        if (argc > 2)
            seconds = atof(argv[2]);
        windowSystemPlaces = argc > 3 && strcmp(argv[3], "free") == 0;
        [NSApplication sharedApplication];
        D *d = [D new];
        [NSApp setDelegate: d];
        [NSApp run];
    }
    return 0;
}
