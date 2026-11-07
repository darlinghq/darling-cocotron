#import <AppKit/AppKit.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

// -[NSApplication stop:] takes effect once an event is dispatched, so the
// documented practice outside event handling is to post a dummy event after it.
static void stopAndPost(void) {
    [NSApp stop: nil];
    [NSApp postEvent: [NSEvent otherEventWithType: NSApplicationDefined location: NSZeroPoint
                                     modifierFlags: 0 timestamp: 0 windowNumber: 0
                                           context: nil subtype: 0 data1: 0 data2: 0]
             atStart: YES];
}

@interface Stopper : NSObject
@end
@implementation Stopper
- (void) fire: (NSTimer *) timer {
    stopAndPost();
}
- (void) detach: (NSTimer *) timer {
    [NSThread detachNewThreadSelector: @selector(fireFromThread:) toTarget: self withObject: nil];
}
- (void) fireFromThread: (id) unused {
    @autoreleasepool {
        usleep(200000);
        stopAndPost();
    }
}
@end

static const char *volatile stalledMessage;

static void stalled(int signal) {
    write(STDERR_FILENO, stalledMessage, strlen(stalledMessage));
    _exit(1);
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        Stopper *stopper = [[Stopper new] autorelease];
        signal(SIGALRM, stalled);

        stalledMessage = "FAIL: -[NSApplication run] did not return after stop: and a posted event (from a timer)\n";
        [NSTimer scheduledTimerWithTimeInterval: 0.2 target: stopper selector: @selector(fire:)
                                       userInfo: nil repeats: NO];
        alarm(10);
        [NSApp run];
        alarm(0);

        stalledMessage = "FAIL: -[NSApplication run] did not return after stop: and a posted event (from another thread)\n";
        [NSTimer scheduledTimerWithTimeInterval: 0 target: stopper selector: @selector(detach:)
                                       userInfo: nil repeats: NO];
        alarm(10);
        [NSApp run];
        alarm(0);

        puts("PASS: -[NSApplication run] returned after stop: and a posted event from a timer and from another thread");
    }
    return 0;
}
