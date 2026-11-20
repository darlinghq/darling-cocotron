// CFLAGS: -framework Foundation -framework AppKit
// Copyright (C) 2026 Lubos Dolezel
//
// Drags between two collection views, for the harnesses
// appkit-collection-view-drag-x11.sh and appkit-collection-view-drag-wayland.sh:
//   cv-source  six items, 1 and 4 selected; each item is the file URL
//              /private/var/tmp/cv-item-<n> (collectionView:pasteboardWriterForItemAtIndexPath:).
//              Prints SOURCE willBegin items=<n>,<n> and SOURCE ended op=<n>.
//   cv-target  six items, takes file URLs and copies them where the collection view proposes. Prints
//                TARGET accept item=<n> op=<on|before> urls=<path>,<path>
//              from collectionView:acceptDrop:indexPath:dropOperation:, then what the dragging pasteboard
//              gives for public.file-url as a string:
//                TARGET string <string>
//              and half a second later
//                TARGET after highlight=<item's highlight state> gap=<views in the gap>
// The source keeps the default masks (every operation within the application, none outside it): every drag here
// stays in this application.
// The documented contract: the collection view drags the selected items with one pasteboard item each, in index
// path order, and calls the delegate's dragging session methods with them; a drop goes on an item or before the
// item after a gap, and its drop target shows until the drag ends.
// Prints, before READY, where to press and release:
//   AT <window> <item> <x> <y>    the middle of an item
//   GAP <window> <item> <x> <y>   the middle of the gap before an item
// in points from the top left corner of the window's content, and the size of that content:
//   CONTENT <width> <height>
// then exits after <seconds> (the first argument, default 30).
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

static void say(NSString *line)
{
    printf("%s\n", [line UTF8String]);
    fflush(stdout);
}

static NSString *items(NSSet *paths)
{
    NSMutableArray *numbers = [NSMutableArray array];
    for (NSIndexPath *path in paths)
        [numbers addObject: [NSNumber numberWithInteger: path.item]];
    [numbers sortUsingSelector: @selector(compare:)];
    return [numbers componentsJoinedByString: @","];
}

@interface ItemView : NSView
@end
@implementation ItemView
- (void) drawRect: (NSRect) rect {
    [[NSColor colorWithCalibratedRed: 0.8 green: 0.85 blue: 0.95 alpha: 1] setFill];
    NSRectFill([self bounds]);
}
@end

@interface Item : NSCollectionViewItem
@end
@implementation Item
- (void) loadView {
    self.view = [[[ItemView alloc] initWithFrame: NSMakeRect(0, 0, 80, 30)] autorelease];
}
@end

@interface Side : NSObject <NSCollectionViewDataSource, NSCollectionViewDelegate> {
@public
    BOOL target;
    NSCollectionView *view;
}
@end
@implementation Side
- (NSInteger) collectionView: (NSCollectionView *) collectionView numberOfItemsInSection: (NSInteger) section {
    return 6;
}
- (NSCollectionViewItem *) collectionView: (NSCollectionView *) collectionView
      itemForRepresentedObjectAtIndexPath: (NSIndexPath *) path
{
    return [collectionView makeItemWithIdentifier: @"item" forIndexPath: path];
}
- (id<NSPasteboardWriting>) collectionView: (NSCollectionView *) collectionView
        pasteboardWriterForItemAtIndexPath: (NSIndexPath *) path
{
    return [NSURL fileURLWithPath: [NSString stringWithFormat: @"/private/var/tmp/cv-item-%ld", (long) path.item]];
}
- (void) collectionView: (NSCollectionView *) collectionView
        draggingSession: (NSDraggingSession *) session
       willBeginAtPoint: (NSPoint) point
   forItemsAtIndexPaths: (NSSet *) paths
{
    say([NSString stringWithFormat: @"SOURCE willBegin items=%@", items(paths)]);
}
- (void) collectionView: (NSCollectionView *) collectionView
        draggingSession: (NSDraggingSession *) session
           endedAtPoint: (NSPoint) point
          dragOperation: (NSDragOperation) operation
{
    say([NSString stringWithFormat: @"SOURCE ended op=%lu", (unsigned long) operation]);
}
- (NSDragOperation) collectionView: (NSCollectionView *) collectionView
                      validateDrop: (id<NSDraggingInfo>) info
                 proposedIndexPath: (NSIndexPath **) path
                     dropOperation: (NSCollectionViewDropOperation *) operation
{
    return NSDragOperationCopy;
}
- (BOOL) collectionView: (NSCollectionView *) collectionView
             acceptDrop: (id<NSDraggingInfo>) info
              indexPath: (NSIndexPath *) path
          dropOperation: (NSCollectionViewDropOperation) operation
{
    NSArray *urls = [[info draggingPasteboard] readObjectsForClasses: @[[NSURL class]]
                                                            options: @{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    NSMutableArray *paths = [NSMutableArray array];
    for (NSURL *url in urls)
        [paths addObject: [url path]];
    say([NSString stringWithFormat: @"TARGET accept item=%ld op=%s urls=%@", (long) path.item,
                                    operation == NSCollectionViewDropOn ? "on" : "before",
                                    [paths componentsJoinedByString: @","]]);
    say([NSString stringWithFormat: @"TARGET string %@",
                                    [[info draggingPasteboard] stringForType: NSPasteboardTypeFileURL]]);
    [self performSelector: @selector(reportAfter:) withObject: [path copy] afterDelay: 0.5];
    return YES;
}
- (void) quit: (NSTimer *) timer {
    exit(0);
}
// What still shows the drop: the item it went on, and views other than items in the gap before it
- (void) reportAfter: (NSIndexPath *) path {
    NSCollectionViewItem *item = [view itemAtIndexPath: path];
    NSRect gap = [view.collectionViewLayout layoutAttributesForInterItemGapBeforeIndexPath: path].frame;
    NSUInteger inGap = 0;
    for (NSView *subview in [view subviews]) {
        BOOL isItem = NO;
        for (NSCollectionViewItem *shown in [view visibleItems])
            isItem = isItem || shown.view == subview;
        if (!isItem && ![subview isHidden] && NSIntersectsRect([subview frame], gap))
            inGap++;
    }
    say([NSString stringWithFormat: @"TARGET after highlight=%ld gap=%lu", (long) item.highlightState,
                                    (unsigned long) inGap]);
    [path release];
}
@end

static NSCollectionView *makeWindow(NSString *title, NSPoint origin, Side *side)
{
    NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(origin.x, origin.y, 300, 120)
                                                   styleMask: NSWindowStyleMaskTitled
                                                     backing: NSBackingStoreBuffered
                                                       defer: NO];
    [window setTitle: title];
    NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame: NSMakeRect(0, 0, 300, 120)] autorelease];
    NSCollectionView *view = [[[NSCollectionView alloc] initWithFrame: NSMakeRect(0, 0, 300, 120)] autorelease];
    NSCollectionViewFlowLayout *layout = [[[NSCollectionViewFlowLayout alloc] init] autorelease];
    layout.itemSize = NSMakeSize(80, 30);
    view.collectionViewLayout = layout;
    [view registerClass: [Item class] forItemWithIdentifier: @"item"];
    view.dataSource = side;
    view.delegate = side;
    view.selectable = YES;
    view.allowsMultipleSelection = YES;
    side->view = view;
    scroll.documentView = view;
    [window setContentView: scroll];
    [view reloadData];
    [window makeKeyAndOrderFront: nil];
    [view layoutSubtreeIfNeeded];
    return view;
}

// Where a point of the collection view is, from the top left corner of its window's content
static void announce(const char *kind, const char *window, NSInteger item, NSCollectionView *view, NSPoint point)
{
    NSPoint inWindow = [view convertPoint: point toView: nil];
    CGFloat height = NSHeight([[[view window] contentView] frame]);
    say([NSString stringWithFormat: @"%s %s %ld %.0f %.0f", kind, window, (long) item, inWindow.x, height - inWindow.y]);
}

int main(int argc, char **argv)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy: NSApplicationActivationPolicyRegular];
    Side *source = [[Side alloc] init], *target = [[Side alloc] init];
    target->target = YES;
    NSCollectionView *from = makeWindow(@"cv-source", NSMakePoint(100, 500), source);
    NSCollectionView *to = makeWindow(@"cv-target", NSMakePoint(500, 500), target);
    [to registerForDraggedTypes: @[NSPasteboardTypeFileURL]];
    from.selectionIndexPaths = [NSSet setWithObjects: [NSIndexPath indexPathForItem: 1 inSection: 0],
                                                      [NSIndexPath indexPathForItem: 4 inSection: 0], nil];
    [NSApp activateIgnoringOtherApps: YES];
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.5]];

    for (NSInteger item = 0; item < 6; item++) {
        NSRect frame = [from layoutAttributesForItemAtIndexPath: [NSIndexPath indexPathForItem: item inSection: 0]].frame;
        announce("AT", "cv-source", item, from, NSMakePoint(NSMidX(frame), NSMidY(frame)));
        frame = [to layoutAttributesForItemAtIndexPath: [NSIndexPath indexPathForItem: item inSection: 0]].frame;
        announce("AT", "cv-target", item, to, NSMakePoint(NSMidX(frame), NSMidY(frame)));
        NSRect gap = [to.collectionViewLayout
                          layoutAttributesForInterItemGapBeforeIndexPath: [NSIndexPath indexPathForItem: item inSection: 0]]
                         .frame;
        announce("GAP", "cv-target", item, to, NSMakePoint(NSMidX(gap), NSMidY(gap)));
    }
    NSSize content = [[[from window] contentView] frame].size;
    say([NSString stringWithFormat: @"CONTENT %.0f %.0f", content.width, content.height]);
    say(@"READY");
    double seconds = argc > 1 ? atof(argv[1]) : 30;
    [NSTimer scheduledTimerWithTimeInterval: seconds target: source selector: @selector(quit:) userInfo: nil repeats: NO];
    [NSApp run];
    [source release];
    [target release];
    [pool release];
    return 0;
}
