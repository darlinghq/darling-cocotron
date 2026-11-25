// CALayer is a key-value coding container: a value set for a key the layer has no property for is
// kept and read back, setting nil removes it, an unset key reads as nil, the values are per layer,
// a key path through a missing value stores nothing,
// and the values are not archived. CABackdropLayer is a plain CALayer subclass that can be created
// by name and accepts such keys too. The same program gives the same results on macOS 26.7.3 and
// Mojave (observations in vd-upstream cristim-mac-evidence.md, batch 11d).
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
        CHECK([layer valueForKey: @"neverSetKey"] == nil, "an unset key reads as nil");

        CALayer *other = [CALayer layer];
        [layer setValue: @1 forKey: @"k1"];
        CHECK([other valueForKey: @"k1"] == nil, "values are per layer");

        NSValue *rect = [NSValue valueWithRect: NSMakeRect(1, 2, 3, 4)];
        [layer setValue: rect forKey: @"kv"];
        [layer setValue: @[@1, @2] forKey: @"ka"];
        CHECK([[layer valueForKey: @"kv"] isEqual: rect], "an NSValue is kept");
        CHECK([[layer valueForKey: @"ka"] isEqual: (@[@1, @2])], "an array is kept");

        layer.opacity = 0.5;
        CHECK([[layer valueForKey: @"opacity"] floatValue] == 0.5f, "a declared key still reaches its property");

        [layer setValue: @"d" forUndefinedKey: @"direct"];
        CHECK([[layer valueForKey: @"direct"] isEqual: @"d"], "-setValue:forUndefinedKey: stores");
        CHECK([layer valueForUndefinedKey: @"zzz"] == nil, "-valueForUndefinedKey: gives nil, no exception");

        // a key path through a value that is not there stores nothing and does not raise
        CALayer *path = [CALayer layer];
        [path setValue: @3 forKeyPath: @"foo.bar"];
        CHECK([path valueForKey: @"foo"] == nil, "key path: no value for foo");
        CHECK([path valueForKeyPath: @"foo.bar"] == nil, "key path: no value for foo.bar");

        // the values are not part of an archive
        [layer setValue: @"keepme" forKey: @"archivedKey"];
        NSError *error = nil;
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject: layer requiringSecureCoding: YES error: &error];
        CHECK(data != nil, "layer archives (%s)", error ? [[error description] UTF8String] : "");
        CALayer *copy = data ? [NSKeyedUnarchiver unarchivedObjectOfClass: [CALayer class] fromData: data error: &error] : nil;
        CHECK(copy != nil, "layer unarchives");
        CHECK([copy valueForKey: @"archivedKey"] == nil, "undefined keys are not archived");
        CHECK(copy.opacity == 0.5f, "declared state is archived");
        NSString *text = [[NSString alloc] initWithData: data encoding: NSISOLatin1StringEncoding];
        CHECK([text rangeOfString: @"archivedKey"].location == NSNotFound, "the key name is not in the archive");

        Class backdrop = NSClassFromString(@"CABackdropLayer");
        CHECK(backdrop != Nil, "CABackdropLayer exists");
        CHECK([backdrop isSubclassOfClass: [CALayer class]], "CABackdropLayer is a CALayer");
        CALayer *b = [[backdrop alloc] init];
        CHECK(!b.isOpaque && b.opacity == 1.0f, "CABackdropLayer starts with CALayer's defaults");
        [b setValue: @(1) forKey: @"someUndeclaredKey"];
        CHECK([[b valueForKey: @"someUndeclaredKey"] isEqual: @(1)], "backdrop layer keeps undefined keys");
        CAShapeLayer *shape = [CAShapeLayer layer];
        [shape setValue: @"x" forKey: @"zz"];
        CHECK([[shape valueForKey: @"zz"] isEqual: @"x"], "a CALayer subclass keeps undefined keys");

        if (failures == 0) puts("PASS: CALayer undefined keys, CABackdropLayer");
        return failures != 0;
    }
}
