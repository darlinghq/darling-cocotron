/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// QUIRK test: Control-arrow line and page key bindings, Control-Y yank: and
// Control-Z noop: (observed on macOS 26.7.3, MC26.4). Only public API is used,
// so it also runs on macOS.
#import <AppKit/AppKit.h>
#include <stdio.h>

@interface LogTextView : NSTextView {
    NSString *_last;
}
@property(copy) NSString *last;
@end
@implementation LogTextView
@synthesize last = _last;
- (void)doCommandBySelector:(SEL)sel { self.last = NSStringFromSelector(sel); }
@end

static int failures;

static void checkKey(LogTextView *tv, NSString *chars, NSString *plain, unsigned short code,
                  NSEventModifierFlags flags, NSString *expect) {
    tv.last = nil;
    NSEvent *e = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
                             modifierFlags:flags timestamp:0 windowNumber:0 context:nil
                                characters:chars charactersIgnoringModifiers:plain
                                 isARepeat:NO keyCode:code];
    [tv interpretKeyEvents:@[ e ]];
    if (![tv.last isEqualToString:expect]) {
        fprintf(stderr, "FAIL: key code %u flags 0x%lx gave %s, expected %s\n", code,
                (unsigned long) flags, tv.last.UTF8String ?: "(none)", expect.UTF8String);
        failures++;
    }
}

int main(void) {
    @autoreleasepool {
        LogTextView *tv = [[LogTextView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
        NSString *left = [NSString stringWithFormat:@"%C", (unichar) NSLeftArrowFunctionKey];
        NSString *right = [NSString stringWithFormat:@"%C", (unichar) NSRightArrowFunctionKey];
        NSString *up = [NSString stringWithFormat:@"%C", (unichar) NSUpArrowFunctionKey];
        NSString *down = [NSString stringWithFormat:@"%C", (unichar) NSDownArrowFunctionKey];
        NSEventModifierFlags fn = NSEventModifierFlagFunction | NSEventModifierFlagNumericPad;
        NSEventModifierFlags ctl = NSEventModifierFlagControl | fn;
        checkKey(tv, left, left, 123, ctl, @"moveToLeftEndOfLine:");
        checkKey(tv, right, right, 124, ctl, @"moveToRightEndOfLine:");
        checkKey(tv, up, up, 126, ctl, @"scrollPageUp:");
        checkKey(tv, down, down, 125, ctl, @"scrollPageDown:");
        checkKey(tv, left, left, 123, ctl | NSEventModifierFlagShift, @"moveToLeftEndOfLineAndModifySelection:");
        checkKey(tv, right, right, 124, ctl | NSEventModifierFlagShift, @"moveToRightEndOfLineAndModifySelection:");
        checkKey(tv, left, left, 123, ctl | NSEventModifierFlagOption, @"noop:");
        checkKey(tv, right, right, 124, ctl | NSEventModifierFlagOption, @"noop:");
        checkKey(tv, @"\x19", @"y", 16, NSEventModifierFlagControl, @"yank:");
        checkKey(tv, @"\x1a", @"z", 6, NSEventModifierFlagControl, @"noop:");
        [tv release];
    }
    printf("control arrow bindings: %s\n", failures ? "FAIL" : "PASS");
    return failures ? 1 : 0;
}
