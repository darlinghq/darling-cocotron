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

@interface TrackingController : NSViewController
@property NSInteger inserts;
@property NSInteger removals;
@end

@implementation TrackingController
- (void)insertChildViewController:(NSViewController *)child atIndex:(NSInteger)index
{
    self.inserts++;
    [super insertChildViewController:child atIndex:index];
}
- (void)removeChildViewControllerAtIndex:(NSInteger)index
{
    self.removals++;
    [super removeChildViewControllerAtIndex:index];
}
@end

int main(void)
{
    @autoreleasepool
    {
        TrackingController *parent = [[TrackingController alloc] initWithNibName:nil bundle:nil];
        NSViewController *a = [[NSViewController alloc] initWithNibName:nil bundle:nil];
        NSViewController *b = [[NSViewController alloc] initWithNibName:nil bundle:nil];
        NSViewController *c = [[NSViewController alloc] initWithNibName:nil bundle:nil];

        expect(parent.childViewControllers.count == 0, @"no children initially");
        [parent addChildViewController:a];
        [parent addChildViewController:c];
        [parent insertChildViewController:b atIndex:1];
        expect([parent.childViewControllers isEqual:(@[ a, b, c ])], @"children keep insertion order");
        expect(a.parentViewController == parent && b.parentViewController == parent, @"parent is set");
        expect(parent.inserts == 3, @"add goes through insertChildViewController:atIndex:");

        [b removeFromParentViewController];
        expect([parent.childViewControllers isEqual:(@[ a, c ])], @"removeFromParentViewController removes the child");
        expect(b.parentViewController == nil, @"removed child has no parent");
        expect(parent.removals == 1, @"removal goes through removeChildViewControllerAtIndex:");
        [b removeFromParentViewController];
        expect(parent.removals == 1, @"removing an orphan does nothing");

        TrackingController *other = [[TrackingController alloc] initWithNibName:nil bundle:nil];
        [other addChildViewController:a];
        expect(a.parentViewController == other, @"adding to a new parent reparents");
        expect([parent.childViewControllers isEqual:(@[ c ])], @"reparenting removes from the old parent");

        parent.childViewControllers = @[ b, a ];
        expect([parent.childViewControllers isEqual:(@[ b, a ])], @"setChildViewControllers: replaces children");
        expect(c.parentViewController == nil && other.childViewControllers.count == 0, @"replaced and moved children are detached");

        BOOL raised = NO;
        @try
        {
            [parent removeChildViewControllerAtIndex:5];
        }
        @catch (NSException *e)
        {
            raised = [e.name isEqual:NSRangeException];
        }
        expect(raised, @"out-of-range removal raises NSRangeException");

        [parent release];
        expect(a.parentViewController == nil, @"deallocated parent detaches its children");
        [other release];
        [a release];
        [b release];
        [c release];
        NSLog(@"PASS: NSViewController child view controllers");
    }
    return 0;
}
