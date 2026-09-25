#import <AppKit/AppKit.h>
#include <stdio.h>

int main(void) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        BOOL passed = ![app isAutomaticCustomizeTouchBarMenuItemEnabled];
        [app setAutomaticCustomizeTouchBarMenuItemEnabled: YES];
        passed &= [app isAutomaticCustomizeTouchBarMenuItemEnabled];
        [app setAutomaticCustomizeTouchBarMenuItemEnabled: NO];
        passed &= ![app isAutomaticCustomizeTouchBarMenuItemEnabled];
        printf("application Touch Bar customization: %s\n", passed ? "PASS" : "FAIL");
        return passed ? 0 : 1;
    }
}
