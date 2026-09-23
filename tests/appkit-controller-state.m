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

@interface ProgrammaticController : NSWindowController
@property BOOL loaded, didLoad;
@end

@implementation ProgrammaticController
- (NSString *)windowNibName { return @""; }
- (void)loadWindow
{
    self.loaded = YES;
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 50, 50)
                                              styleMask:NSTitledWindowMask
                                                backing:NSBackingStoreBuffered
                                                  defer:YES];
}
- (void)windowDidLoad { self.didLoad = YES; }
@end

int main(void)
{
    @autoreleasepool
    {
        [NSApplication sharedApplication];
        NSViewController *controller = [[NSViewController alloc] initWithNibName:nil bundle:nil];
        expect(NSEqualSizes(controller.preferredContentSize, NSZeroSize), @"preferredContentSize starts at zero");
        controller.preferredContentSize = NSMakeSize(300, 200);
        expect(NSEqualSizes(controller.preferredContentSize, NSMakeSize(300, 200)), @"preferredContentSize is stored");
        controller.identifier = @"main";
        expect([controller.identifier isEqual:@"main"], @"identifier is stored");

        NSUserActivity *activity = [NSUserActivity new];
        controller.userActivity = activity;
        expect(controller.userActivity == activity, @"responders keep their user activity");
        controller.userActivity = nil;
        expect(controller.userActivity == nil, @"user activity can be cleared");

        controller.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 120, 80)];
        controller.title = @"Hello";
        controller.preferredContentSize = NSZeroSize;
        NSWindow *window = [NSWindow windowWithContentViewController:controller];
        expect(window.contentViewController == controller && window.contentView == controller.view,
               @"the controller's view becomes the content view");
        NSRect content = [window contentRectForFrameRect:window.frame];
        expect(NSEqualSizes(content.size, NSMakeSize(120, 80)) && [window.title isEqual:@"Hello"],
               @"the window is sized to the view and titled after the controller");
        expect(window.styleMask & NSResizableWindowMask, @"the window is resizable");

        controller.preferredContentSize = NSMakeSize(200, 150);
        NSWindow *sized = [NSWindow windowWithContentViewController:controller];
        expect(NSEqualSizes([sized contentRectForFrameRect:sized.frame].size, NSMakeSize(200, 150)),
               @"a preferred content size wins over the view's size");

        window.contentViewController = nil;
        expect(window.contentViewController == nil, @"contentViewController can be cleared");

        ProgrammaticController *windowController = [[ProgrammaticController alloc] initWithWindow:nil];
        NSWindow *loaded = windowController.window;
        expect(windowController.loaded && windowController.didLoad && loaded != nil && windowController.window == loaded,
               @"a controller with a nib name loads its window through loadWindow");
        NSLog(@"PASS: view controller, responder, window and window controller state");
    }
    return 0;
}
