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

static NSViewController *controllerWithView(void)
{
    NSViewController *controller = [[[NSViewController alloc] initWithNibName:nil bundle:nil] autorelease];
    controller.view = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)] autorelease];
    return controller;
}

static BOOL childrenMatchItems(NSSplitViewController *split)
{
    NSMutableArray *expected = [NSMutableArray array];
    for (NSSplitViewItem *item in split.splitViewItems)
        [expected addObject:item.viewController];
    return [split.childViewControllers isEqual:expected];
}

int main(void)
{
    @autoreleasepool
    {
        NSViewController *sidebarController = controllerWithView();
        NSViewController *listController = controllerWithView();
        NSViewController *detailController = controllerWithView();

        NSSplitViewItem *sidebar = [NSSplitViewItem sidebarWithViewController:sidebarController];
        expect(sidebar.behavior == NSSplitViewItemBehaviorSidebar, @"sidebar behavior");
        expect(sidebar.canCollapse, @"sidebars collapse");
        expect(sidebar.holdingPriority == NSLayoutPriorityDefaultLow + 10, @"sidebar holding priority");
        NSSplitViewItem *list = [NSSplitViewItem contentListWithViewController:listController];
        expect(list.behavior == NSSplitViewItemBehaviorContentList, @"content list behavior");
        NSSplitViewItem *detail = [NSSplitViewItem splitViewItemWithViewController:detailController];
        expect(detail.behavior == NSSplitViewItemBehaviorDefault && !detail.canCollapse, @"default item");

        NSSplitViewController *split = [[NSSplitViewController alloc] initWithNibName:nil bundle:nil];
        [split addSplitViewItem:sidebar];
        [split addSplitViewItem:detail];
        [split insertSplitViewItem:list atIndex:1];
        expect([split.splitViewItems isEqual:(@[ sidebar, list, detail ])], @"items keep insertion order");
        expect(childrenMatchItems(split), @"items' controllers are the children");
        expect(listController.parentViewController == split, @"item controller parent");

        NSSplitView *splitView = (NSSplitView *)split.view;
        expect(splitView == split.splitView, @"the view is the split view");
        expect([splitView.subviews isEqual:(@[ sidebarController.view, listController.view, detailController.view ])],
               @"loading the view adds item views in order");

        [split removeSplitViewItem:list];
        expect([split.splitViewItems isEqual:(@[ sidebar, detail ])], @"removeSplitViewItem:");
        expect(childrenMatchItems(split) && listController.parentViewController == nil, @"removal detaches the child");
        expect(listController.view.superview == nil, @"removal removes the view");

        NSViewController *extra = controllerWithView();
        [split insertChildViewController:extra atIndex:1];
        NSSplitViewItem *extraItem = [split splitViewItemForViewController:extra];
        expect(extraItem != nil && [split.splitViewItems indexOfObject:extraItem] == 1, @"adding a child creates an item");
        expect([splitView.subviews isEqual:(@[ sidebarController.view, extra.view, detailController.view ])],
               @"a child added after loading is inserted in place");

        [extra removeFromParentViewController];
        expect([split.splitViewItems isEqual:(@[ sidebar, detail ])], @"removing a child removes its item");

        split.splitViewItems = @[ detail ];
        expect(childrenMatchItems(split) && sidebarController.parentViewController == nil, @"setSplitViewItems: syncs children");
        expect([splitView.subviews isEqual:(@[ detailController.view ])], @"setSplitViewItems: syncs subviews");

        BOOL raised = NO;
        @try
        {
            [split removeSplitViewItem:list];
        }
        @catch (NSException *e)
        {
            raised = [e.name isEqual:NSInvalidArgumentException];
        }
        expect(raised, @"removing a foreign item raises");

        [split release];
        NSLog(@"PASS: NSSplitViewItem behaviors and NSSplitViewController items");
    }
    return 0;
}
