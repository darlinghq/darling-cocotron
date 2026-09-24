// Archiving and -initWithLayer: keep layer names, constraints, layout managers and geometryFlipped.
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>

#define CHECK(cond, code)                                   \
    do {                                                    \
        if (!(cond)) {                                      \
            fprintf(stderr, "FAIL %d: %s\n", code, #cond);  \
            return code;                                    \
        }                                                   \
    } while (0)

@interface PlainLayoutManager : NSObject <CALayoutManager>
@end

@implementation PlainLayoutManager
@end

// Archives as a CALayer whose "constraints" entry is replaced, to feed the decoder malformed data.
@interface MalformedLayer : NSObject <NSSecureCoding> {
    CALayer *_layer;
    id _constraints;
}
@end

@implementation MalformedLayer
+ (BOOL) supportsSecureCoding {
    return YES;
}

- (instancetype) initWithConstraints: (id) constraints {
    self = [super init];
    _layer = [[CALayer alloc] init];
    _constraints = [constraints retain];
    return self;
}

- (void) dealloc {
    [_layer release];
    [_constraints release];
    [super dealloc];
}

- (Class) classForKeyedArchiver {
    return [CALayer class];
}

- (void) encodeWithCoder: (NSCoder *) coder {
    [_layer encodeWithCoder: coder];
    [coder encodeObject: _constraints forKey: @"constraints"];
}

- (instancetype) initWithCoder: (NSCoder *) coder {
    [self release];
    return nil;
}
@end

static NSString *decodeFailure(id constraints) {
    MalformedLayer *layer = [[[MalformedLayer alloc] initWithConstraints: constraints] autorelease];
    NSError *error = nil;
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject: layer requiringSecureCoding: YES error: &error];
    if (data == nil)
        return @"archiving failed";
    id decoded = [NSKeyedUnarchiver unarchivedObjectOfClass: [CALayer class] fromData: data error: &error];
    return decoded == nil ? [error description] : nil;
}

static id roundTrip(id root, NSError **error) {
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject: root requiringSecureCoding: YES error: error];
    if (data == nil)
        return nil;
    return [NSKeyedUnarchiver unarchivedObjectOfClass: [CALayer class] fromData: data error: error];
}

static NSString *archiveException(id root) {
    @try {
        [NSKeyedArchiver archivedDataWithRootObject: root];
    } @catch (NSException *e) {
        return [e name];
    }
    return nil;
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
        root.sublayers = @[left, right];

        NSError *error = nil;
        CALayer *copy = roundTrip(root, &error);
        CHECK(copy != nil && error == nil, 2);
        CHECK([copy.name isEqualToString: @"root"] && copy.geometryFlipped, 3);
        CHECK([copy.layoutManager isKindOfClass: [CAConstraintLayoutManager class]], 4);
        CALayer *copyLeft = copy.sublayers[0], *copyRight = copy.sublayers[1];
        CHECK([copyLeft.name isEqualToString: @"left"] && [copyRight.name isEqualToString: @"right"], 5);
        CHECK(!copyLeft.geometryFlipped && copyLeft.contentsAreFlipped, 6);
        CHECK(copyLeft.constraints.count == 2 && copyRight.constraints.count == 3, 7);
        for (NSUInteger i = 0; i < 3; i++)
            CHECK(sameConstraint(copyRight.constraints[i], right.constraints[i]), 8);

        // The decoded constraints drive the decoded layout manager.
        [copy layoutIfNeeded];
        CHECK(CGRectEqualToRect(copyLeft.frame, CGRectMake(10, 40, 50, 20)), 9);
        CHECK(CGRectEqualToRect(copyRight.frame, CGRectMake(65, 0, 50, 20)), 10);

        CALayer *presentation = [[[CALayer alloc] initWithLayer: root] autorelease];
        CHECK([presentation.name isEqualToString: @"root"] && presentation.geometryFlipped, 11);
        CHECK(presentation.layoutManager == root.layoutManager, 12);
        CALayer *leftCopy = [[[CALayer alloc] initWithLayer: left] autorelease];
        CHECK([leftCopy.constraints isEqualToArray: left.constraints], 13);

        // A layout manager without archiving support is refused, not dropped.
        CALayer *custom = [CALayer layer];
        custom.layoutManager = [[[PlainLayoutManager alloc] init] autorelease];
        CHECK([archiveException(custom) isEqualToString: NSInvalidArchiveOperationException], 14);

        NSString *failure = decodeFailure(@[@[]]);
        CHECK([failure rangeOfString: @"is not a CAConstraint"].location != NSNotFound, 15);
        failure = decodeFailure([CAConstraint constraintWithAttribute: kCAConstraintMinX
                                                            relativeTo: @"superlayer"
                                                             attribute: kCAConstraintMinX]);
        CHECK([failure rangeOfString: @"are not an array"].location != NSNotFound, 16);

        CALayer *plain = roundTrip([CALayer layer], &error);
        CHECK(plain != nil && plain.name == nil && plain.layoutManager == nil && plain.constraints == nil &&
                  !plain.geometryFlipped, 17);
    }
    puts("ALL PASSED");
    return 0;
}
