#import <AppKit/AppKit.h>
#include <stdlib.h>

static void expect(BOOL condition, NSString *message)
{
    if (!condition)
    {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

// Stand-ins that archive under the AppKit class names, the way a nib stores them.
@interface ArchivedController : NSObject <NSCoding>
@property(copy) NSString *title;
@end
@implementation ArchivedController
- (Class)classForKeyedArchiver
{
    return [NSViewController class];
}
- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:self.title forKey:@"NSTitle"];
}
- (id)initWithCoder:(NSCoder *)coder
{
    return [super init];
}
@end

@interface ArchivedItem : NSObject <NSCoding>
@property(retain) ArchivedController *controller;
@property NSInteger behavior;
@property BOOL collapsed;
@end
@implementation ArchivedItem
- (Class)classForKeyedArchiver
{
    return [NSSplitViewItem class];
}
- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:self.controller forKey:@"NSSplitViewItemViewController"];
    [coder encodeDouble:260 forKey:@"NSHoldingPriority"];
    [coder encodeBool:self.collapsed forKey:@"NSCollapsed"];
    [coder encodeInteger:self.behavior forKey:@"NSBehavior"];
}
- (id)initWithCoder:(NSCoder *)coder
{
    return [super init];
}
@end

@interface ArchivedSplitController : NSObject <NSCoding>
@property(retain) NSArray *items;
@end
@implementation ArchivedSplitController
- (Class)classForKeyedArchiver
{
    return [NSSplitViewController class];
}
- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:self.items forKey:@"NSSplitViewItems"];
}
- (id)initWithCoder:(NSCoder *)coder
{
    return [super init];
}
@end

static ArchivedController *controllerTitled(NSString *title)
{
    ArchivedController *controller = [[[ArchivedController alloc] init] autorelease];
    controller.title = title;
    return controller;
}

int main(void)
{
    @autoreleasepool
    {
        ArchivedItem *sidebar = [[[ArchivedItem alloc] init] autorelease];
        sidebar.controller = controllerTitled(@"Sources");
        sidebar.behavior = NSSplitViewItemBehaviorSidebar;
        sidebar.collapsed = YES;
        ArchivedItem *content = [[[ArchivedItem alloc] init] autorelease];
        content.controller = controllerTitled(@"Messages");
        ArchivedSplitController *split = [[[ArchivedSplitController alloc] init] autorelease];
        split.items = @[ sidebar, content ];

        NSMutableData *data = [NSMutableData data];
        NSKeyedArchiver *archiver = [[[NSKeyedArchiver alloc] initForWritingWithMutableData:data] autorelease];
        [archiver encodeObject:split forKey:@"root"];
        [archiver finishEncoding];

        NSKeyedUnarchiver *unarchiver = [[[NSKeyedUnarchiver alloc] initForReadingWithData:data] autorelease];
        NSSplitViewController *decoded = [unarchiver decodeObjectForKey:@"root"];
        expect([decoded isKindOfClass:[NSSplitViewController class]], @"decodes a split view controller");
        expect(decoded.splitViewItems.count == 2, @"decodes its items");

        NSSplitViewItem *first = decoded.splitViewItems[0];
        expect([first isKindOfClass:[NSSplitViewItem class]], @"items are split view items");
        expect([first.viewController.title isEqual:@"Sources"], @"item view controller");
        expect(first.behavior == NSSplitViewItemBehaviorSidebar, @"item behavior");
        expect(first.collapsed, @"item collapsed state");
        expect(first.holdingPriority == 260, @"item holding priority");
        NSSplitViewItem *second = decoded.splitViewItems[1];
        expect(second.behavior == NSSplitViewItemBehaviorDefault && !second.collapsed, @"second item");

        expect([decoded.childViewControllers isEqual:(@[ first.viewController, second.viewController ])],
               @"decoded items' controllers are the children");
        NSLog(@"PASS: NSSplitViewItem and NSSplitViewController keyed decoding");
    }
    return 0;
}
