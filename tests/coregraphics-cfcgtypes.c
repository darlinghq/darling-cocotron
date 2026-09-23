#include <CoreFoundation/CoreFoundation.h>

#ifndef CF_DEFINES_CG_TYPES
#error CoreFoundation does not define the Core Graphics geometry types
#endif

// Declared with only CoreFoundation in scope, as OpenAttributeGraph does.
static CGFloat area(CGRect rect) {
    return rect.size.width * rect.size.height;
}

#include <CoreGraphics/CoreGraphics.h>

int main(void) {
    CGRect rect = CGRectMake(1, 2, 3, 4);
    CGVector vector = { 5, 6 };
    if (area(rect) != 12 || CGRectGetMaxX(rect) != 4 || CGRectGetMaxY(rect) != 6)
        return 1;
    if (vector.dx + vector.dy != 11 || sizeof(CGFloat) != sizeof(double) || !CGFLOAT_IS_DOUBLE)
        return 2;
    if (!CGPointEqualToPoint(CGPointMake(3, 4), (CGPoint){ 3, 4 }))
        return 3;
    return 0;
}
