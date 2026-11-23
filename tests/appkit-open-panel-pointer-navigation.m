// Copyright (C) 2026 Lubos Dolezel
//
// Fixture for driving an open panel with a real pointer (xdotool on X11, a virtual pointer or libei on Wayland): it
// opens the panel (as a sheet or run modally) on a tree whose every level has a folder "a" first, then files, so that
// a double-click at the same position of every listing enters the next level. It prints what a user would observe:
//   READY <mode>
//   DIR <path>                  each time the panel shows a folder (panel:didChangeToDirectoryURL:)
//   CLICK <n> <title> <x> <y>   each left mouse-down the application receives: clickCount, window title, location
//   SEL <rows> <first row's name or ->   the selection of the panel's list after each change
//   ROW <i> <screen x> <screen y>  where row i of the list is on screen (Cocoa coordinates, as AppKit knows them)
//   SCREEN <w> <h>
//   ENDED <code> <path or ->    the panel accepted or cancelled
// A single-argument form for the driver: opp-nav <dir> sheet|modal [seconds]. The driver asserts which folders were
// entered: a double-click enters exactly one level, a folder is never accepted as a file, and what is selected in
// a listing reached by double-click is nothing.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>

static NSOpenPanel *panel;
static NSWindow *doc;
static NSString *root;
static BOOL sheet;

@interface FixtureApp : NSApplication
@end
@implementation FixtureApp
- (void) sendEvent: (NSEvent *) event {
    if ([event type] == NSLeftMouseDown) {
        NSPoint p = [event locationInWindow];
        printf("CLICK %ld %s %.0f %.0f\n", (long) [event clickCount], [[[event window] title] UTF8String], p.x, p.y);
        fflush(stdout);
    }
    [super sendEvent: event];
}
@end

static NSTableView *findTable(NSView *view) {
    if ([view isKindOfClass: [NSTableView class]] && [(NSTableView *) view numberOfColumns] > 1)
        return (NSTableView *) view;
    for (NSView *sub in [view subviews]) {
        NSTableView *t = findTable(sub);
        if (t != nil)
            return t;
    }
    return nil;
}

@interface D : NSObject <NSApplicationDelegate, NSOpenSavePanelDelegate>
@end
@implementation D
- (void) report {
    NSTableView *list = findTable([panel contentView]);
    if (list == nil)
        return;
    NSInteger n = [list numberOfSelectedRows];
    id item = n > 0 ? [list itemAtRow: [list selectedRow]] : nil;
    printf("SEL %ld %s\n", (long) n, item ? [[[item path] lastPathComponent] UTF8String] : "-");
    NSRect screen = [[NSScreen mainScreen] frame];
    for (NSInteger i = 0; i < 3; i++) {
        NSRect r = [list rectOfRow: i];
        NSPoint w = [list convertPoint: NSMakePoint(NSMinX(r) + 40, NSMidY(r)) toView: nil];
        NSPoint s = [panel convertBaseToScreen: w];
        printf("ROW %ld %.0f %.0f\n", (long) i, s.x, NSHeight(screen) - s.y);
    }
    NSRect f = [panel frame];
    printf("PANEL %.0f %.0f %.0f %.0f\n", f.origin.x, NSHeight(screen) - NSMaxY(f), f.size.width, f.size.height);
    fflush(stdout);
}
- (void) panel: (id) sender didChangeToDirectoryURL: (NSURL *) url {
    printf("DIR %s\n", [[url path] UTF8String]);
    fflush(stdout);
    [self performSelector: @selector(report) withObject: nil afterDelay: 0.15];
}
- (void) panelSelectionDidChange: (id) sender {
    [self performSelector: @selector(report) withObject: nil afterDelay: 0.15];
}
- (void) applicationDidFinishLaunching: (NSNotification *) n {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dir = root;
    for (int level = 0; level < 6; level++) {
        [fm createDirectoryAtPath: [dir stringByAppendingPathComponent: @"a"] withIntermediateDirectories: YES attributes: nil error: nil];
        for (NSString *f in @[ @"b.txt", @"c.txt", @"d.txt" ])
            [@"x" writeToFile: [dir stringByAppendingPathComponent: f] atomically: NO encoding: NSUTF8StringEncoding error: nil];
        dir = [dir stringByAppendingPathComponent: @"a"];
    }
    doc = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 300, 700, 500)
                                      styleMask: NSTitledWindowMask | NSClosableWindowMask | NSResizableWindowMask
                                        backing: NSBackingStoreBuffered defer: NO];
    [doc setTitle: @"opn-doc"];
    [doc makeKeyAndOrderFront: nil];
    [NSApp activateIgnoringOtherApps: YES];
    [self performSelector: @selector(open) withObject: nil afterDelay: 0.5];
}
- (void) open {
    panel = [NSOpenPanel openPanel];
    [panel setDelegate: self];
    [panel setDirectoryURL: [NSURL fileURLWithPath: root]];
    [panel setCanChooseFiles: YES];
    [panel setCanChooseDirectories: NO];
    printf("SCREEN %.0f %.0f\n", NSWidth([[NSScreen mainScreen] frame]), NSHeight([[NSScreen mainScreen] frame]));
    void (^done)(NSModalResponse) = ^(NSModalResponse r) {
        printf("ENDED %ld %s\n", (long) r, [panel URL] ? [[[panel URL] path] UTF8String] : "-");
        fflush(stdout);
        exit(0);
    };
    printf("READY %s\n", sheet ? "sheet" : "modal");
    fflush(stdout);
    if (sheet) {
        [panel beginSheetModalForWindow: doc completionHandler: done];
    } else {
        [self performSelector: @selector(report) withObject: nil afterDelay: 0.8 inModes: @[NSRunLoopCommonModes]];
        done([panel runModal]);
    }
}
+ (void) setSheet: (BOOL) s {
    sheet = s;
}
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        root = [NSString stringWithUTF8String: argc > 1 ? argv[1] : "/tmp/opn"];
        [D setSheet: argc > 2 && strcmp(argv[2], "modal") != 0];
        NSTimeInterval seconds = argc > 3 ? atof(argv[3]) : 60;
        [FixtureApp sharedApplication];
        D *d = [D new];
        [NSApp setDelegate: d];
        [NSApp performSelector: @selector(terminate:) withObject: nil afterDelay: seconds];
        [NSApp run];
    }
    return 0;
}
