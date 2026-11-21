// Copyright (C) 2026 Lubos Dolezel
//
// -[NSCollectionView scrollToItemsAtIndexPaths:scrollPosition:] with NSCollectionViewScrollPositionNone does not
// scroll, even when the item is out of view; NSCollectionViewScrollPositionNearestHorizontalEdge scrolls it into view.
// Black-box: the same checks pass on macOS 10.14.4 and 26.7.3. Needs a display.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(BOOL ok, const char *what)
{
    printf("%s: %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        failures++;
}

@interface Source : NSObject <NSCollectionViewDataSource>
@end

@implementation Source
- (NSInteger) collectionView: (NSCollectionView *) view numberOfItemsInSection: (NSInteger) section
{
    return 2000;
}

- (NSCollectionViewItem *) collectionView: (NSCollectionView *) view itemForRepresentedObjectAtIndexPath: (NSIndexPath *) path
{
    return [view makeItemWithIdentifier: @"item" forIndexPath: path];
}
@end

@interface Item : NSCollectionViewItem
@end

@implementation Item
- (void) loadView
{
    self.view = [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)] autorelease];
}
@end

static void spin(void)
{
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.3]];
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 600, 500)
                                                       styleMask: NSWindowStyleMaskTitled
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame: [[window contentView] bounds]] autorelease];
        NSCollectionView *view = [[[NSCollectionView alloc] initWithFrame: [scroll bounds]] autorelease];
        NSCollectionViewFlowLayout *layout = [[[NSCollectionViewFlowLayout alloc] init] autorelease];
        layout.itemSize = NSMakeSize(100, 100);
        view.collectionViewLayout = layout;
        [view registerClass: [Item class] forItemWithIdentifier: @"item"];
        Source *source = [[[Source alloc] init] autorelease];
        view.dataSource = source;
        scroll.documentView = view;
        window.contentView = scroll;
        [window orderFront: nil];
        spin();

        NSSet *last = [NSSet setWithObject: [NSIndexPath indexPathForItem: 1999 inSection: 0]];
        expect(NSMinY([view visibleRect]) == 0, "the view starts at the top");
        [view scrollToItemsAtIndexPaths: last scrollPosition: NSCollectionViewScrollPositionNone];
        spin();
        expect(NSMinY([view visibleRect]) == 0, "NSCollectionViewScrollPositionNone does not scroll");
        [view scrollToItemsAtIndexPaths: last scrollPosition: NSCollectionViewScrollPositionNearestHorizontalEdge];
        spin();
        expect(NSIntersectsRect([view frameForItemAtIndex: 1999], [view visibleRect]),
               "NSCollectionViewScrollPositionNearestHorizontalEdge scrolls the item into view");
        printf(failures ? "FAILED %d\n" : "ALL PASSED\n", failures);
    }
    return failures != 0;
}
