// Copyright (C) 2026 Lubos Dolezel
//
// The mask parameter of nextEventMatchingMask:untilDate:inMode:dequeue: and
// discardEventsMatchingMask:beforeEvent: is NSUInteger-sized: 32 bits on i386, where code built for
// old SDKs pushes a 32-bit word before the other arguments. The type encodings are those of macOS
// 10.14.4 (observed on an i386 and an x86_64 binary); NSEvent's monitors and
// trackEventsMatchingMask:... take the 64-bit NSEventMask on both. The caller below pushes a
// pointer-sized mask the way such code does and checks the following arguments arrive intact.
#import <AppKit/AppKit.h>
#import <AppKit/NSDisplay.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <string.h>

@interface MaskWidthDisplay : NSDisplay
@end
@implementation MaskWidthDisplay
@end

static int failures;

static void expectEncoding(Class cls, SEL sel, BOOL meta, const char *enc32, const char *enc64) {
    Method m = meta ? class_getClassMethod(cls, sel) : class_getInstanceMethod(cls, sel);
    const char *got = m ? method_getTypeEncoding(m) : "(missing)";
#if __LP64__
    const char *want = enc64;
#else
    const char *want = enc32;
#endif
    if (strcmp(got, want) != 0) {
        printf("FAIL: %s %c%s is %s, expected %s\n", class_getName(cls), meta ? '+' : '-',
               sel_getName(sel), got, want);
        failures++;
    }
}

int main(void) {
    @autoreleasepool {
        Class app = [NSApplication class], win = [NSWindow class], ev = [NSEvent class];
        expectEncoding(app, @selector(nextEventMatchingMask:untilDate:inMode:dequeue:), NO,
                       "@24@0:4I8@12@16c20", "@44@0:8Q16@24@32c40");
        expectEncoding(app, @selector(discardEventsMatchingMask:beforeEvent:), NO,
                       "v16@0:4I8@12", "v32@0:8Q16@24");
        expectEncoding(win, @selector(nextEventMatchingMask:), NO, "@12@0:4I8", "@24@0:8Q16");
        expectEncoding(win, @selector(nextEventMatchingMask:untilDate:inMode:dequeue:), NO,
                       "@24@0:4I8@12@16c20", "@44@0:8Q16@24@32c40");
        expectEncoding(win, @selector(discardEventsMatchingMask:beforeEvent:), NO,
                       "v16@0:4I8@12", "v32@0:8Q16@24");
        expectEncoding(ev, @selector(addLocalMonitorForEventsMatchingMask:handler:), YES,
                       "@20@0:4Q8@?16", "@32@0:8Q16@?24");

        // A caller built for the NSUInteger-sized signature.
        NSDisplay *display = [[MaskWidthDisplay alloc] init];
        NSEvent *press = [NSEvent keyEventWithType:NSKeyDown location:NSZeroPoint
                modifierFlags:0 timestamp:0 windowNumber:0 context:nil characters:@"x"
                charactersIgnoringModifiers:@"x" isARepeat:NO keyCode:0];
        [display postEvent:press atStart:NO];
        NSEvent *(*next)(id, SEL, NSUInteger, NSDate *, NSString *, BOOL) =
                (NSEvent *(*)(id, SEL, NSUInteger, NSDate *, NSString *, BOOL)) objc_msgSend;
        SEL sel = @selector(nextEventMatchingMask:untilDate:inMode:dequeue:);

        // No queued event of the wanted type: returns after the (short) date, with an event that
        // is not the queued key press.
        NSEvent *other = next(display, sel, NSKeyUpMask, [NSDate dateWithTimeIntervalSinceNow:0.05],
                              NSDefaultRunLoopMode, YES);
        if (other == press) {
            printf("FAIL: a key-up mask returned the queued key press\n");
            failures++;
        }
        // The key press is returned only when asked for, and dequeue is honoured.
        NSEvent *peek = next(display, sel, NSKeyDownMask, [NSDate distantPast], NSDefaultRunLoopMode, NO);
        NSEvent *taken = next(display, sel, NSKeyDownMask, [NSDate distantPast], NSDefaultRunLoopMode, YES);
        NSEvent *gone = next(display, sel, NSKeyDownMask, [NSDate distantPast], NSDefaultRunLoopMode, YES);
        if (peek != press || taken != press || gone == press) {
            printf("FAIL: mask/dequeue arguments not delivered (peek %d taken %d gone %d)\n",
                   peek == press, taken == press, gone == press);
            failures++;
        }
    }
    printf(failures ? "FAIL\n" : "PASS\n");
    return failures != 0;
}
