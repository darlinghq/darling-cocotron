// CAEAGLLayer is a CALayer with the EAGLDrawable properties drawableProperties (copied) and
// presentsWithTransaction (NO by default). It starts with CALayer's defaults, opaque included.
// Not compiled or run when written.
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { failures++; fprintf(stderr, "FAIL line %d: ", __LINE__); fprintf(stderr, __VA_ARGS__); fputc('\n', stderr); } } while (0)

int main(void) {
    @autoreleasepool {
        CAEAGLLayer *layer = [CAEAGLLayer layer];
        CHECK([layer isKindOfClass: [CALayer class]], "CAEAGLLayer is a CALayer");
        CHECK([layer conformsToProtocol: @protocol(EAGLDrawable)], "conforms to EAGLDrawable");
        CHECK(layer.isOpaque == [CALayer layer].isOpaque, "opaque starts as CALayer's default");
        CHECK(!layer.presentsWithTransaction, "presentsWithTransaction defaults to NO");
        CHECK(layer.drawableProperties == nil, "no drawable properties by default");

        NSMutableDictionary *props = [NSMutableDictionary dictionaryWithObject: @NO forKey: @"someKey"];
        layer.drawableProperties = props;
        [props setObject: @YES forKey: @"someKey"];
        CHECK([[layer.drawableProperties objectForKey: @"someKey"] isEqual: @NO],
              "drawableProperties is a copy");

        layer.presentsWithTransaction = YES;
        CHECK(layer.presentsWithTransaction, "presentsWithTransaction set");

        if (failures == 0) puts("PASS: CAEAGLLayer");
        return failures != 0;
    }
}
