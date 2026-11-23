// CAEAGLLayer is a CALayer with the EAGLDrawable properties drawableProperties (copied) and
// presentsWithTransaction (NO by default). Unlike CALayer it starts opaque (the public QuartzCore
// header says so; macOS 26.7.3: -init, +layer and -initWithLayer: give YES).
// The class does not exist on Mojave, which is why nothing here is compared with it.
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { failures++; fprintf(stderr, "FAIL line %d: ", __LINE__); fprintf(stderr, __VA_ARGS__); fputc('\n', stderr); } } while (0)

int main(void) {
    @autoreleasepool {
        CAEAGLLayer *layer = [CAEAGLLayer layer];
        CHECK([layer isKindOfClass: [CALayer class]], "CAEAGLLayer is a CALayer");
        CHECK([layer conformsToProtocol: @protocol(EAGLDrawable)], "conforms to EAGLDrawable");
        CHECK(layer.isOpaque, "-layer starts opaque");
        CHECK([[[CAEAGLLayer alloc] init] isOpaque], "-init starts opaque");
        CHECK(![(CALayer *)[CALayer layer] isOpaque], "a plain CALayer does not");
        CAEAGLLayer *source = [CAEAGLLayer layer];
        source.opaque = NO;
        CHECK([[[CAEAGLLayer alloc] initWithLayer: source] isOpaque], "-initWithLayer: starts opaque");
        layer.opaque = NO;
        CHECK(!layer.isOpaque, "opaque can be cleared");
        CHECK(!layer.presentsWithTransaction, "presentsWithTransaction defaults to NO");
        CHECK(layer.drawableProperties == nil, "no drawable properties by default");

        NSMutableDictionary *props = [NSMutableDictionary dictionaryWithObject: @NO forKey: @"someKey"];
        layer.drawableProperties = props;
        [props setObject: @YES forKey: @"someKey"];
        CHECK([[layer.drawableProperties objectForKey: @"someKey"] isEqual: @NO],
              "drawableProperties is a copy");
        layer.drawableProperties = nil;
        CHECK(layer.drawableProperties == nil, "drawableProperties can be cleared");

        layer.presentsWithTransaction = YES;
        CHECK(layer.presentsWithTransaction, "presentsWithTransaction set");
        layer.presentsWithTransaction = NO;
        CHECK(!layer.presentsWithTransaction, "presentsWithTransaction cleared");

        // the subclass keeps CALayer's key-value coding of undefined keys
        [layer setValue: @"v" forKey: @"someUndeclaredKey"];
        CHECK([[layer valueForKey: @"someUndeclaredKey"] isEqual: @"v"], "undefined key kept");

        if (failures == 0) puts("PASS: CAEAGLLayer");
        return failures != 0;
    }
}
