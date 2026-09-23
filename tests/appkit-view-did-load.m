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

@interface LoadingController : NSViewController
@property NSInteger loads;
@property NSInteger didLoads;
@property BOOL viewSetWhenDidLoad;
@end

@implementation LoadingController
- (void)loadView
{
    self.loads++;
    self.view = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)] autorelease];
}
- (void)viewDidLoad
{
    [super viewDidLoad];
    self.didLoads++;
    self.viewSetWhenDidLoad = self.viewLoaded;
}
@end

int main(void)
{
    @autoreleasepool
    {
        LoadingController *controller = [[LoadingController alloc] initWithNibName:nil bundle:nil];
        expect(!controller.viewLoaded, @"no view before -view");
        expect(controller.didLoads == 0, @"viewDidLoad waits for the view");

        NSView *view = controller.view;
        expect(view != nil && controller.viewLoaded, @"-view loads the view");
        expect(controller.loads == 1 && controller.didLoads == 1, @"loadView then viewDidLoad, once each");
        expect(controller.viewSetWhenDidLoad, @"viewDidLoad runs after the view is set");

        expect(controller.view == view, @"view stays loaded");
        expect(controller.loads == 1 && controller.didLoads == 1, @"no reload on later -view calls");

        LoadingController *assigned = [[LoadingController alloc] initWithNibName:nil bundle:nil];
        assigned.view = [[[NSView alloc] initWithFrame:NSZeroRect] autorelease];
        (void)assigned.view;
        expect(assigned.loads == 0 && assigned.didLoads == 0, @"an assigned view is not loaded again");

        [assigned release];
        [controller release];
        NSLog(@"PASS: NSViewController viewDidLoad and isViewLoaded");
    }
    return 0;
}
