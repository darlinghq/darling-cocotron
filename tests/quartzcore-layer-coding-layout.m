// Layer names, constraints, layout managers and geometryFlipped survive keyed
// archiving, and the decoded constraints drive the decoded layout manager.
// The same program passes on macOS.
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>

#define CHECK(cond, code)                                   \
    do {                                                    \
        if (!(cond)) {                                      \
            fprintf(stderr, "FAIL %d: %s\n", code, #cond);  \
            return code;                                    \
        }                                                   \
    } while (0)

static id roundTrip(id root, NSError **error) {
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject: root requiringSecureCoding: YES error: error];
    if (data == nil)
        return nil;
    return [NSKeyedUnarchiver unarchivedObjectOfClass: [CALayer class] fromData: data error: error];
}

static BOOL sameConstraint(CAConstraint *a, CAConstraint *b) {
    return a.attribute == b.attribute && [a.sourceName isEqualToString: b.sourceName] &&
           a.sourceAttribute == b.sourceAttribute && a.scale == b.scale && a.offset == b.offset;
}

int main(void) {
    @autoreleasepool {
        CHECK([CAConstraint supportsSecureCoding] && [CAConstraintLayoutManager supportsSecureCoding], 1);

        CALayer *root = [CALayer layer];
        root.name = @"root";
        root.bounds = CGRectMake(0, 0, 200, 100);
        root.geometryFlipped = YES;
        root.layoutManager = [CAConstraintLayoutManager layoutManager];

        CALayer *left = [CALayer layer];
        left.name = @"left";
        left.bounds = CGRectMake(0, 0, 50, 20);
        [left addConstraint: [CAConstraint constraintWithAttribute: kCAConstraintMinX
                                                        relativeTo: @"superlayer"
                                                         attribute: kCAConstraintMinX
                                                            offset: 10]];
        [left addConstraint: [CAConstraint constraintWithAttribute: kCAConstraintMidY
                                                        relativeTo: @"superlayer"
                                                         attribute: kCAConstraintMidY]];
        CALayer *right = [CALayer layer];
        right.name = @"right";
        [right addConstraint: [CAConstraint constraintWithAttribute: kCAConstraintMinX
                                                         relativeTo: @"left"
                                                          attribute: kCAConstraintMaxX
                                                              scale: 1
                                                             offset: 5]];
        [right addConstraint: [CAConstraint constraintWithAttribute: kCAConstraintWidth
                                                         relativeTo: @"superlayer"
                                                          attribute: kCAConstraintWidth
                                                              scale: 0.25
                                                             offset: 0]];
        [right addConstraint: [CAConstraint constraintWithAttribute: kCAConstraintHeight
                                                         relativeTo: @"left"
                                                          attribute: kCAConstraintHeight]];
        root.sublayers = @[ left, right ];

        NSError *error = nil;
        CALayer *copy = roundTrip(root, &error);
        CHECK(copy != nil && error == nil, 2);
        CHECK([copy.name isEqualToString: @"root"] && copy.geometryFlipped, 3);
        CHECK([copy.layoutManager isKindOfClass: [CAConstraintLayoutManager class]], 4);
        CALayer *copyLeft = copy.sublayers[0], *copyRight = copy.sublayers[1];
        CHECK([copyLeft.name isEqualToString: @"left"] && [copyRight.name isEqualToString: @"right"], 5);
        CHECK(!copyLeft.geometryFlipped, 6);
        CHECK(copyLeft.constraints.count == 2 && copyRight.constraints.count == 3, 7);
        for (NSUInteger i = 0; i < 3; i++)
            CHECK(sameConstraint(copyRight.constraints[i], right.constraints[i]), 8);

        // The decoded constraints drive the decoded layout manager like the originals.
        [root layoutIfNeeded];
        [copy layoutIfNeeded];
        CHECK(CGRectEqualToRect(copyLeft.frame, left.frame), 9);
        CHECK(CGRectEqualToRect(copyRight.frame, right.frame), 10);

        CALayer *plain = roundTrip([CALayer layer], &error);
        CHECK(plain != nil && plain.name == nil && plain.layoutManager == nil && plain.constraints == nil &&
                  !plain.geometryFlipped, 11);
    }
    puts("ALL PASSED");
    return 0;
}
