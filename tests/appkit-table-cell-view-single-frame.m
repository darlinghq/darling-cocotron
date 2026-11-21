/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * A view-based NSTableView gives each cell view the frame in which it is shown, in the
 * coordinates of the row view that holds it (NSTableView documents that cell views are
 * subviews of NSTableRowView), and does not move the view anywhere else while drawing.
 * Observed on macOS 10.14.4 and 26.7.3 through the public API: every frame a cell view
 * is given lies inside its row view (22 points high in the table below: a row height of
 * 20 and the default intercell spacing), and drawing the table again changes no cell
 * view's frame.
 *
 * The cell views here are layer-backed. Moving a layer-backed view through the table's
 * coordinates before its place in the row view (a frame in the table's coordinates
 * placed the view far outside its row) made the Wayland backend ask for a redraw each
 * time the frame came back inside the window, so the main thread never left its event
 * dispatch: the run loop did not run and the application stopped responding. The last
 * check keeps the main run loop running for a while and fails when it is not serviced.
 *
 * Needs a display (X11 or Wayland). No ARC. Prints PASS/FAIL lines.
 */
#import <AppKit/AppKit.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static int failures;
static volatile long mainThreadProgress;
static int cellViewsMade;
static int movedOutOfRow;
static int frameChanges;

#define CHECK(cond, ...) do { if (cond) printf("PASS: " __VA_ARGS__); else { printf("FAIL: " __VA_ARGS__); failures++; } printf("\n"); } while (0)

@interface TrackedCell : NSView
@end

@implementation TrackedCell
- (void) setFrame: (NSRect) frame {
    NSRect old = [self frame];
    if (NSMaxY(frame) > 22)
        movedOutOfRow++;
    [super setFrame: frame];
    if (!NSEqualRects(old, [self frame]))
        frameChanges++;
}
@end

@interface Source : NSObject <NSTableViewDataSource, NSTableViewDelegate>
@end

@implementation Source
- (NSInteger) numberOfRowsInTableView: (NSTableView *) table {
    return 40;
}

- (NSView *) tableView: (NSTableView *) table viewForTableColumn: (NSTableColumn *) column row: (NSInteger) row {
    TrackedCell *cell = [[[TrackedCell alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)] autorelease];
    [cell setWantsLayer: YES];
    cellViewsMade++;
    return cell;
}
@end

static void *watchdog(void *arg) {
    long last = -1;
    int stalled = 0;
    for (;;) {
        sleep(1);
        long now = mainThreadProgress;
        stalled = now == last ? stalled + 1 : 0;
        last = now;
        if (stalled >= 8) {
            printf("FAIL: the main run loop was not serviced for %d seconds\nFAILED\n", stalled);
            fflush(stdout);
            _exit(1);
        }
    }
    return NULL;
}

static void runFor(NSTimeInterval seconds) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow: seconds];
    while ([end timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.05]];
        mainThreadProgress++;
    }
}

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [NSApplication sharedApplication];

    pthread_t thread;
    pthread_create(&thread, NULL, watchdog, NULL);

    Source *source = [[Source alloc] init];
    NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 360, 300)
                                                   styleMask: NSWindowStyleMaskTitled
                                                     backing: NSBackingStoreBuffered
                                                       defer: NO];
    NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame: NSMakeRect(0, 0, 360, 300)] autorelease];
    NSTableView *table = [[[NSTableView alloc] initWithFrame: NSMakeRect(0, 0, 340, 800)] autorelease];
    NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier: @"c"] autorelease];

    [column setWidth: 320];
    [table addTableColumn: column];
    [table setRowHeight: 20];
    [table setDataSource: source];
    [table setDelegate: source];
    [scroll setDocumentView: table];
    [window setContentView: scroll];
    [window makeKeyAndOrderFront: nil];
    [table reloadData];

    [window display];
    runFor(1.0);

    CHECK(cellViewsMade > 0, "the delegate made cell views (%d)", cellViewsMade);
    CHECK(movedOutOfRow == 0, "every frame given to a cell view lies inside its row (%d frames outside)", movedOutOfRow);

    BOOL inRows = YES, insideRows = YES;
    for (NSInteger row = 0; row < 14; row++) {
        NSView *view = [table viewAtColumn: 0 row: row makeIfNecessary: NO];
        if (view == nil)
            continue;
        if (![[view superview] isKindOfClass: [NSTableRowView class]])
            inRows = NO;
        if (NSMaxY([view frame]) > 22)
            insideRows = NO;
    }
    CHECK(inRows, "the cell views are subviews of row views");
    CHECK(insideRows, "the cell views lie inside their row views");

    int changesBefore = frameChanges;
    [window display];
    [table setNeedsDisplay: YES];
    [window display];
    runFor(0.5);
    CHECK(frameChanges == changesBefore, "drawing the table again changed no cell view frame (%d changes)", frameChanges - changesBefore);

    long before = mainThreadProgress;
    runFor(1.5);
    CHECK(mainThreadProgress - before > 5, "the main run loop kept running (%ld turns)", mainThreadProgress - before);

    printf("%s\n", failures ? "FAILED" : "ALL PASSED");
    return failures != 0;
}
