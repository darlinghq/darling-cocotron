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

// Implements one optional method only.
@interface Delegate : NSObject <NSApplicationDelegate>
@property BOOL finished;
@end

@implementation Delegate
- (void)applicationWillFinishLaunching:(NSNotification *)note { self.finished = YES; }
@end

@interface Owner : NSObject <NSViewToolTipOwner>
@end

@implementation Owner
- (NSString *)view:(NSView *)view stringForToolTip:(NSToolTipTag)tag point:(NSPoint)point userData:(void *)data
{
    return [NSString stringWithFormat:@"%@", (NSString *)data];
}
@end

int main(void)
{
    @autoreleasepool
    {
        NSApplication *app = [NSApplication sharedApplication];
        Delegate *delegate = [Delegate new];
        app.delegate = delegate;
        expect(app.delegate == delegate, @"delegate property");
        expect([delegate conformsToProtocol:@protocol(NSApplicationDelegate)] &&
                   [delegate respondsToSelector:@selector(applicationWillFinishLaunching:)] &&
                   ![delegate respondsToSelector:@selector(applicationShouldTerminate:)],
               @"a delegate implements only the optional methods it wants");
        [[NSNotificationCenter defaultCenter] postNotificationName:NSApplicationWillFinishLaunchingNotification
                                                            object:app];
        expect(delegate.finished, @"the application registers its delegate for its notifications");
        expect(![[NSObject new] respondsToSelector:@selector(applicationWillFinishLaunching:)],
               @"NSObject itself does not implement delegate methods");

        Owner *owner = [Owner new];
        NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
        NSToolTipTag tag = [view addToolTipRect:NSMakeRect(0, 0, 5, 5) owner:owner userData:@"tip"];
        expect(tag != 0 && [[owner view:view stringForToolTip:tag point:NSZeroPoint userData:@"tip"] isEqual:@"tip"],
               @"tool-tip owners adopt NSViewToolTipOwner");
        app.delegate = nil;
        NSLog(@"PASS: NSApplicationDelegate and NSViewToolTipOwner are protocols");
    }
    return 0;
}
