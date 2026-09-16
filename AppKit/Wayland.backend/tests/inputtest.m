#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

// Plain-arm64 native-compositor fixture. Host driver injects timed clicks and
// modifier transitions; log records actual AppKit events before dispatch.
@interface InputApplication : NSApplication
@end
@implementation InputApplication
- (void)sendEvent:(NSEvent *)event {
    switch ([event type]) {
    case NSLeftMouseDown: case NSLeftMouseUp:
    case NSRightMouseDown: case NSRightMouseUp:
        printf("MOUSE type=%lu count=%ld\n", (unsigned long)[event type],
               (long)[event clickCount]); break;
    case NSFlagsChanged: case NSKeyDown: case NSKeyUp:
        printf("KEY type=%lu code=%u flags=%lu\n", (unsigned long)[event type],
               [event keyCode], (unsigned long)[event modifierFlags]); break;
    default: [super sendEvent:event]; return;
    }
    fflush(stdout);
}
- (void)done:(id)sender { puts("DONE"); fflush(stdout); exit(0); }
@end
int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [InputApplication sharedApplication];
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,500,400)
            styleMask:NSTitledWindowMask backing:NSBackingStoreBuffered defer:NO];
    [window setTitle:@"Wayland input test"];
    [window makeKeyAndOrderFront:nil];
    [NSTimer scheduledTimerWithTimeInterval:18 target:NSApp selector:@selector(done:)
                                  userInfo:nil repeats:NO];
    puts("READY"); fflush(stdout);
    [NSApp run]; [pool drain]; return 0;
}
