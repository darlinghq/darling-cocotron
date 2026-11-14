#import <AppKit/AppKit.h>
#include <stdio.h>

#define EXPECT(cond, msg) do { if (!(cond)) { printf("FAIL: %s\n", msg); return 1; } } while (0)

// NSAccessibility.h (macOS 10.13) puts switchControlEnabled, getter isSwitchControlEnabled, on NSWorkspace. Phone
// sends it to the shared workspace, which is a MacWorkspace here. Darling has no assistive-technology client, so
// Switch Control is never running.
int main(void) {
    @autoreleasepool {
        NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
        EXPECT([workspace respondsToSelector: @selector(isSwitchControlEnabled)], "the shared workspace answers isSwitchControlEnabled");
        BOOL enabled = YES;
        @try {
            enabled = [workspace isSwitchControlEnabled];
        } @catch (NSException *exception) {
            printf("FAIL: isSwitchControlEnabled raised %s\n", [[exception reason] UTF8String]);
            return 1;
        }
        EXPECT(!enabled, "Switch Control is not running");
        EXPECT([[workspace valueForKey: @"switchControlEnabled"] isEqual: @NO], "the property reads as NO through key-value coding");
        EXPECT([workspace isVoiceOverEnabled] == NO, "VoiceOver is unchanged");
        printf("PASS: workspace switch control\n");
        return 0;
    }
}
