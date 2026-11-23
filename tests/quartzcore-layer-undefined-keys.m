// CALayer is a key-value coding container: a value set for a key the layer has no property for is
// kept and read back, and setting nil removes it. CABackdropLayer is a plain CALayer subclass that
// can be created by name and accepts such keys too. Not compiled or run when written.
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { failures++; fprintf(stderr, "FAIL line %d: ", __LINE__); fprintf(stderr, __VA_ARGS__); fputc('\n', stderr); } } while (0)

int main(void) {
    @autoreleasepool {
        CALayer *layer = [CALayer layer];
        [layer setValue: @"blur" forKey: @"someUndeclaredKey"];
        CHECK([[layer valueForKey: @"someUndeclaredKey"] isEqual: @"blur"], "value kept for an undefined key");
        [layer setValue: nil forKey: @"someUndeclaredKey"];
        CHECK([layer valueForKey: @"someUndeclaredKey"] == nil, "nil removes the value");

        CALayer *other = [CALayer layer];
        CHECK([other valueForKey: @"someUndeclaredKey"] == nil, "values are per layer");

        Class backdrop = NSClassFromString(@"CABackdropLayer");
        CHECK(backdrop != Nil, "CABackdropLayer exists");
        CHECK([backdrop isSubclassOfClass: [CALayer class]], "CABackdropLayer is a CALayer");
        CALayer *b = [[backdrop alloc] init];
        [b setValue: @(1) forKey: @"someUndeclaredKey"];
        CHECK([[b valueForKey: @"someUndeclaredKey"] isEqual: @(1)], "backdrop layer keeps undefined keys");

        if (failures == 0) puts("PASS: CALayer undefined keys, CABackdropLayer");
        return failures != 0;
    }
}
