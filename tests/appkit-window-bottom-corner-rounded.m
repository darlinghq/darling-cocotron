#import <AppKit/AppKit.h>
#include <stdio.h>

@interface TerminalWindowProbe : NSWindow
@end
@implementation TerminalWindowProbe
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        TerminalWindowProbe *window = [[TerminalWindowProbe alloc]
                initWithContentRect: NSMakeRect(0, 0, 100, 100)
                         styleMask: NSWindowStyleMaskTitled
                           backing: NSBackingStoreBuffered defer: NO];
        BOOL passed = [window bottomCornerRounded];
        [window setBottomCornerRounded: NO];
        passed &= ![window bottomCornerRounded];
        [window setBottomCornerRounded: YES];
        passed &= [window bottomCornerRounded];
        [window release];
        printf("window bottom corners: %s\n", passed ? "PASS" : "FAIL");
        return passed ? 0 : 1;
    }
}
