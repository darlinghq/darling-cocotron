// Copyright (C) 2026 Lubos Dolezel
// SPDX-License-Identifier: MIT
// NSOutlineView draws the selected row with the same highlight as NSTableView,
// without a dotted focus frame around the outline column cell.
//
// The window is rendered with -cacheDisplayInRect:toBitmapImageRep: while the
// outline view is first responder in the key window ("focused") and while
// another window is key ("unfocused"). For the selected row the test scans the
// topmost and bottom scanlines of the row's rectangle (a selection highlight
// is a flat fill, so neighbouring pixels along those lines are equal apart
// from where the highlight begins and ends) and counts how often the colour
// changes between adjacent pixels. A dotted frame alternates between two
// colours on every other pixel.
// The images are written as PNG to the directory given as argv[1], if any.
//
// Build: clang -fobjc-arc -o t appkit-outline-view-selection-highlight.m -framework AppKit
#import <AppKit/AppKit.h>

@interface Src : NSObject <NSOutlineViewDataSource> {
  @public
    NSArray *roots;
    NSDictionary *children;
}
@end
@implementation Src
- (NSInteger)outlineView:(NSOutlineView *)ov numberOfChildrenOfItem:(id)item {
    return item ? [children[item] count] : (NSInteger)roots.count;
}
- (id)outlineView:(NSOutlineView *)ov child:(NSInteger)i ofItem:(id)item {
    return item ? children[item][i] : roots[i];
}
- (BOOL)outlineView:(NSOutlineView *)ov isItemExpandable:(id)item {
    return children[item] != nil;
}
- (id)outlineView:(NSOutlineView *)ov objectValueForTableColumn:(NSTableColumn *)c byItem:(id)item {
    return item;
}
@end

static void spin(void) {
    for (int i = 0; i < 20; i++) {
        NSEvent *e;
        while ((e = [NSApp nextEventMatchingMask:NSEventMaskAny
                                       untilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]
                                          inMode:NSDefaultRunLoopMode
                                         dequeue:YES]))
            [NSApp sendEvent:e];
    }
}

static unsigned pixel(NSBitmapImageRep *rep, NSInteger x, NSInteger y) {
    NSUInteger p[4] = {0, 0, 0, 0};
    [rep getPixel:p atX:x y:y];
    return (unsigned)((p[0] << 24) ^ (p[1] << 16) ^ (p[2] << 8) ^ p[3]);
}

static int changes(NSBitmapImageRep *rep, NSInteger x0, NSInteger y0, NSInteger dx, NSInteger dy, NSInteger n) {
    int c = 0;
    for (NSInteger i = 1; i < n; i++)
        if (pixel(rep, x0 + dx * i, y0 + dy * i) != pixel(rep, x0 + dx * (i - 1), y0 + dy * (i - 1))) c++;
    return c;
}

static int measure(NSOutlineView *ov, NSInteger row, const char *label, NSString *dir) {
    NSRect bounds = ov.bounds;
    NSBitmapImageRep *rep = [ov bitmapImageRepForCachingDisplayInRect:bounds];
    [ov cacheDisplayInRect:bounds toBitmapImageRep:rep];
    double scale = (double)rep.pixelsWide / bounds.size.width;
    NSRect r = [ov rectOfRow:row];
    NSInteger x0 = (NSInteger)(r.origin.x * scale), y0 = (NSInteger)(r.origin.y * scale);
    NSInteger w = (NSInteger)(r.size.width * scale), h = (NSInteger)(r.size.height * scale);
    int top = changes(rep, x0, y0, 1, 0, w);
    int bottom = changes(rep, x0, y0 + h - 1, 1, 0, w);
    printf("%s: scale %.0f row rect %ldx%ld, colour changes: top %d bottom %d\n", label, scale,
           (long)w, (long)h, top, bottom);
    if (dir) {
        NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        [png writeToFile:[dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%s.png", label]] atomically:YES];
    }
    // flat highlight: a few changes where it starts and ends, none inside
    return top <= 4 && bottom <= 4;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        NSString *dir = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : nil;
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        Src *src = [Src new];
        src->roots = @[ @"Alpha", @"Beta", @"Gamma" ];
        src->children = @{ @"Alpha" : @[ @"Alpha one", @"Alpha two" ] };
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 300, 320, 200)
                                                  styleMask:NSWindowStyleMaskTitled
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
        NSScrollView *sv = [[NSScrollView alloc] initWithFrame:[w.contentView bounds]];
        NSOutlineView *ov = [[NSOutlineView alloc] initWithFrame:sv.bounds];
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"c"];
        col.width = 280;
        [ov addTableColumn:col];
        ov.outlineTableColumn = col;
        ov.headerView = nil;
        if ([ov respondsToSelector:@selector(setStyle:)]) [ov setValue:@(4) forKey:@"style"]; // plain
        ov.dataSource = src;
        sv.documentView = ov;
        [w.contentView addSubview:sv];
        [ov reloadData];
        [ov expandItem:@"Alpha"];
        NSWindow *other = [[NSWindow alloc] initWithContentRect:NSMakeRect(500, 300, 200, 100)
                                                      styleMask:NSWindowStyleMaskTitled
                                                        backing:NSBackingStoreBuffered
                                                          defer:NO];
        [NSApp activateIgnoringOtherApps:YES];
        [w makeKeyAndOrderFront:nil];
        [w makeFirstResponder:ov];
        NSInteger row = 3; // "Beta", a leaf at the root; Alpha, Alpha one, Alpha two come first
        [ov selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
        spin();
        int ok = measure(ov, row, "focused", dir);
        [other makeKeyAndOrderFront:nil];
        spin();
        ok &= measure(ov, row, "unfocused", dir);
        printf(ok ? "PASS\n" : "FAIL: selection highlight is not flat\n");
        return ok ? 0 : 1;
    }
}
