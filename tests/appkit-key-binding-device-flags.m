/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Key binding lookup ignores device-dependent modifier bits: some backends
// report the physical left or right Shift bit together with the aggregate one,
// and the binding for the aggregate bit must still be found.
#import <AppKit/AppKit.h>
#import "../AppKit/NSKeyboardBinding/NSKeyboardBinding.h"
#import "../AppKit/NSKeyboardBinding/NSKeyboardBindingManager.h"
#include <stdio.h>

int main(void) {
    int failures = 0;
    @autoreleasepool {
        NSDictionary *bindings = @{ @"shift,keypad,0xF703" : @"moveForwardAndModifySelection:" };
        NSKeyboardBindingManager *manager = [[NSKeyboardBindingManager alloc] initWithDictionary: bindings];
        NSUInteger flags[] = { NSShiftKeyMask, NSShiftKeyMask | 2, NSShiftKeyMask | 4, NSShiftKeyMask | 6 };
        for (NSUInteger i = 0; i < sizeof(flags) / sizeof(flags[0]); i++) {
            NSKeyboardBinding *binding = [manager keyBindingWithString: @"" modifierFlags: flags[i]];
            if (![[binding selectorNames] isEqual: @[ @"moveForwardAndModifySelection:" ]]) {
                fprintf(stderr, "FAIL: Shift+Right with flags 0x%lx finds no binding\n",
                        (unsigned long) flags[i]);
                failures++;
            }
        }
        // A different aggregate flag must still not match.
        NSKeyboardBinding *other = [manager keyBindingWithString: @"" modifierFlags: NSControlKeyMask | 2];
        if (other != nil) {
            fprintf(stderr, "FAIL: Control+Right matched a Shift binding\n");
            failures++;
        }
        [manager release];
    }
    printf("key binding device flags: %s\n", failures ? "FAIL" : "PASS");
    return failures ? 1 : 0;
}
