// CFLAGS: -framework AppKit -fobjc-arc
// Copyright (C) 2026 Lubos Dolezel
//
// Clicking a row of a table makes the table the first responder of its window, so that the selection is drawn
// emphasized and the arrow keys move it. Observed on macOS 26.7.3, where it passes unchanged. Needs a display.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(BOOL ok, NSString *what)
{
    printf("%s: %s\n", ok ? "PASS" : "FAIL", [what UTF8String]);
    failures += !ok;
}

@interface Source : NSObject <NSTableViewDataSource>
@end
@implementation Source
- (NSInteger)numberOfRowsInTableView:(NSTableView *)table { return 4; }
- (id)tableView:(NSTableView *)table objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row { return @"row"; }
@end

static void Click(NSWindow *window, NSPoint point)
{
    for (NSNumber *type in @[ @(NSEventTypeLeftMouseDown), @(NSEventTypeLeftMouseUp) ]) {
        NSEvent *event = [NSEvent mouseEventWithType:[type unsignedIntegerValue] location:point modifierFlags:0 timestamp:0
                                        windowNumber:[window windowNumber] context:nil eventNumber:0 clickCount:1 pressure:1];
        [window sendEvent:event];
    }
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        Source *source = [[Source alloc] init];
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 300, 200) styleMask:NSWindowStyleMaskTitled
                                                         backing:NSBackingStoreBuffered defer:NO];
        NSTableView *table = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"c"];
        [column setWidth:196];
        [table addTableColumn:column];
        [table setHeaderView:nil];
        [table setRowHeight:24];
        [table setDataSource:source];
        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 200, 200)];
        [scroll setDocumentView:table];
        [[window contentView] addSubview:scroll];
        [window makeKeyAndOrderFront:nil];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
        [window makeFirstResponder:window];

        NSRect row = [table convertRect:[table rectOfRow:2] toView:nil];
        Click(window, NSMakePoint(NSMidX(row), NSMidY(row)));
        expect([window firstResponder] == table, @"the click makes the table the first responder");
    }
    printf(failures ? "FAILED: %d\n" : "ALL PASSED\n", failures);
    return failures != 0;
}
