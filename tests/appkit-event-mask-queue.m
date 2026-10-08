#import <AppKit/AppKit.h>
#import <AppKit/NSDisplay.h>
#include <signal.h>
#include <stdio.h>
#include <unistd.h>

@interface EventQueueDisplay : NSDisplay
@end
@implementation EventQueueDisplay
@end

static void stalled(int signal) {
    const char message[] = "FAIL: event queue spins when no queued event matches\n";
    write(STDERR_FILENO, message, sizeof(message) - 1);
    _exit(1);
}
static NSEvent *key(NSEventType type) {
    return [NSEvent keyEventWithType:type location:NSZeroPoint modifierFlags:NSShiftKeyMask
            timestamp:0 windowNumber:0 context:nil characters:@"x"
            charactersIgnoringModifiers:@"x" isARepeat:NO keyCode:0];
}
static NSEvent *take(NSDisplay *display, NSEventMask mask, BOOL dequeue) {
    return [display nextEventMatchingMask:mask untilDate:[NSDate distantPast]
            inMode:NSDefaultRunLoopMode dequeue:dequeue];
}
int main(void) {
    @autoreleasepool {
        NSDisplay *display = [[EventQueueDisplay alloc] init];
        NSEvent *flags = key(NSFlagsChanged), *press = key(NSKeyDown);
        [display postEvent:flags atStart:NO];
        [display postEvent:press atStart:NO];
        if (take(display, NSKeyDownMask, NO) != press ||
                take(display, NSKeyDownMask, YES) != press) return 1;
        signal(SIGALRM, stalled); alarm(3);
        NSEvent *idle = take(display, NSKeyDownMask, YES);
        alarm(0);
        if ([idle type] != NSAppKitSystem || take(display, NSFlagsChangedMask, YES) != flags)
            return 1;
        puts("PASS: unmatched events remain queued without spinning; peek/dequeue preserve order");
    }
    return 0;
}
