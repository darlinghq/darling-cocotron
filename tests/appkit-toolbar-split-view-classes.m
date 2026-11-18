// NSTrackingSeparatorToolbarItem keeps the split view and divider index it is
// made with; NSSplitViewItemAccessoryViewController keeps its two flags and
// starts with automaticallyAppliesContentInsets YES and hidden NO.
#import <AppKit/AppKit.h>
#include <stdlib.h>

// Archives no keys; the unarchiver maps it to the accessory, as a nib load does.
@interface ArchivedAccessory : NSObject <NSCoding>
@end

@implementation ArchivedAccessory
- (void)encodeWithCoder:(NSCoder *)coder {
}
- (id)initWithCoder:(NSCoder *)coder { return nil; }
@end

static void expect(BOOL condition, NSString *message)
{
    if (!condition)
    {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

int main(void)
{
    @autoreleasepool
    {
        NSSplitView *split = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
        NSUInteger base = [split retainCount];
        NSTrackingSeparatorToolbarItem *item =
            [NSTrackingSeparatorToolbarItem trackingSeparatorToolbarItemWithIdentifier:@"sep"
                                                                             splitView:split
                                                                          dividerIndex:2];
        // Retain counts are read straight from the object: going through the
        // atomic getter would add an autoreleased retain and hide a miss.
        expect([split retainCount] == base + 1, @"the item retains the split view");
        NSTrackingSeparatorToolbarItem *dup = [item copy];
        expect([split retainCount] == base + 2, @"a copy retains the split view");
        [dup release];
        expect([split retainCount] == base + 1, @"releasing the copy gives the retain back");
        [split release];
        expect(item != nil, @"factory returns an item");
        expect([item isKindOfClass:[NSToolbarItem class]], @"item is an NSToolbarItem");
        expect([[item itemIdentifier] isEqual:@"sep"], @"identifier is kept");
        expect(item.splitView != nil && [item.splitView isKindOfClass:[NSSplitView class]],
               @"split view outlives the caller's reference");
        expect(item.dividerIndex == 2, @"divider index is kept");
        item.dividerIndex = 5;
        expect(item.dividerIndex == 5, @"divider index is settable");

        NSSplitViewItemAccessoryViewController *accessory =
            [[[NSSplitViewItemAccessoryViewController alloc] init] autorelease];
        expect([accessory isKindOfClass:[NSViewController class]], @"accessory is a view controller");
        expect(accessory.automaticallyAppliesContentInsets, @"insets default to YES");
        expect(!accessory.hidden, @"hidden defaults to NO");
        accessory.hidden = YES;
        accessory.automaticallyAppliesContentInsets = NO;
        expect(accessory.hidden && !accessory.automaticallyAppliesContentInsets, @"flags are settable");
        NSMutableData *data = [NSMutableData data];
        NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];
        [archiver encodeObject:[[[ArchivedAccessory alloc] init] autorelease] forKey:@"root"];
        [archiver finishEncoding];
        [archiver release];
        NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
        [unarchiver setClass:[NSSplitViewItemAccessoryViewController class]
                forClassName:@"ArchivedAccessory"];
        NSSplitViewItemAccessoryViewController *decoded = [unarchiver decodeObjectForKey:@"root"];
        [unarchiver release];
        expect([decoded isKindOfClass:[NSSplitViewItemAccessoryViewController class]],
               @"the archive decodes to an accessory");
        expect(decoded.automaticallyAppliesContentInsets, @"a decoded accessory defaults to YES");
        expect(!decoded.hidden, @"a decoded accessory is not hidden");
        NSLog(@"PASS: toolbar and split view classes");
    }
    return 0;
}
