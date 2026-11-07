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

@interface Catcher : NSResponder
@property NSInteger downs, ups, drags;
@end

@implementation Catcher
- (void)otherMouseDown:(NSEvent *)event { self.downs++; }
- (void)otherMouseUp:(NSEvent *)event { self.ups++; }
- (void)otherMouseDragged:(NSEvent *)event { self.drags++; }
@end

int main(void)
{
    @autoreleasepool
    {
        [NSApplication sharedApplication];
        Catcher *catcher = [Catcher new];
        NSView *outer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
        NSView *inner = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 5, 5)];
        [outer addSubview:inner];
        outer.nextResponder = catcher;
        NSEvent *event = [NSEvent mouseEventWithType:NSEventTypeOtherMouseDown location:NSZeroPoint modifierFlags:0
                                           timestamp:0 windowNumber:0 context:nil eventNumber:0 clickCount:1 pressure:1];
        [inner otherMouseDown:event];
        [inner otherMouseUp:event];
        [inner otherMouseDragged:event];
        expect(catcher.downs == 1 && catcher.ups == 1 && catcher.drags == 1,
               @"other-button events travel up the responder chain");
        [[NSResponder new] otherMouseDown:event];
        NSLog(@"PASS: NSResponder passes other-button mouse events to its next responder");
    }
    return 0;
}
