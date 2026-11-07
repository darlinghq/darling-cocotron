#import <AppKit/AppKit.h>
#include <stdio.h>

int main(void) {
    @autoreleasepool {
        NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
        BOOL passed = ![workspace accessibilityDisplayShouldDifferentiateWithoutColor]
                   && ![workspace accessibilityDisplayShouldIncreaseContrast]
                   && ![workspace accessibilityDisplayShouldReduceTransparency]
                   && ![workspace accessibilityDisplayShouldInvertColors]
                   && ![workspace accessibilityDisplayShouldReduceMotion];
        printf("workspace accessibility display: %s\n", passed ? "PASS" : "FAIL");
        return passed ? 0 : 1;
    }
}
