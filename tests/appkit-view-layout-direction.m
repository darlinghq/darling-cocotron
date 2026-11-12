#import <AppKit/AppKit.h>
#include <stdio.h>

int main(void) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        NSView *view = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 40, 20)];
        BOOL passed = [view userInterfaceLayoutDirection] ==
                [app userInterfaceLayoutDirection];
        [view setUserInterfaceLayoutDirection:
                NSUserInterfaceLayoutDirectionRightToLeft];
        passed &= [view userInterfaceLayoutDirection] ==
                NSUserInterfaceLayoutDirectionRightToLeft;
        [view setUserInterfaceLayoutDirection:
                NSUserInterfaceLayoutDirectionLeftToRight];
        passed &= [view userInterfaceLayoutDirection] ==
                NSUserInterfaceLayoutDirectionLeftToRight;
        [view release];
        printf("view layout direction: %s\n", passed ? "PASS" : "FAIL");
        return passed ? 0 : 1;
    }
}
