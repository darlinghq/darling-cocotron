#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#include <stdlib.h>

static void expect(BOOL condition, NSString *message)
{
    if (!condition)
    {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

static void expectOrder(CALayer *parent, CALayer *first, CALayer *second, CALayer *third)
{
    NSArray *children = parent.sublayers;
    NSUInteger expectedCount = (first != nil) + (second != nil) + (third != nil);
    expect(children.count == expectedCount, @"sublayer count");
    if (first != nil) expect(children[0] == first, @"first sublayer");
    if (second != nil) expect(children[1] == second, @"second sublayer");
    if (third != nil) expect(children[2] == third, @"third sublayer");
}

int main(void)
{
    @autoreleasepool
    {
        CALayer *parent = [CALayer layer];
        CALayer *other = [CALayer layer];
        CALayer *a = [CALayer layer];
        CALayer *b = [CALayer layer];
        CALayer *c = [CALayer layer];

        [parent insertSublayer:a atIndex:0];
        [parent insertSublayer:b atIndex:1];
        [parent insertSublayer:c atIndex:1];
        expectOrder(parent, a, c, b);
        expect(a.superlayer == parent && b.superlayer == parent && c.superlayer == parent,
               @"initial parent links");

        [parent insertSublayer:a atIndex:3]; // SwiftUI moves a child to the end this way.
        expectOrder(parent, c, b, a);
        [parent insertSublayer:a atIndex:0];
        expectOrder(parent, a, c, b);

        [other insertSublayer:b atIndex:0];
        expectOrder(parent, a, c, nil);
        expectOrder(other, b, nil, nil);
        expect(b.superlayer == other, @"reparented child link");
        [b removeFromSuperlayer];
        expectOrder(other, nil, nil, nil);
        expect(b.superlayer == nil, @"removed child link");

        // The old parent is the only owner of this child when it is moved.
        CALayer *transient = [[CALayer alloc] init];
        [parent addSublayer:transient];
        [transient release];
        [other insertSublayer:transient atIndex:0];
        expect(transient.superlayer == other, @"reparenting retains child during removal");
        expectOrder(parent, a, c, nil);

        BOOL rejected = NO;
        @try { [parent insertSublayer:parent atIndex:0]; }
        @catch (NSException *exception) { rejected = YES; }
        expect(rejected, @"cycle rejection");
        rejected = NO;
        @try { [parent insertSublayer:b atIndex:99]; }
        @catch (NSException *exception) { rejected = YES; }
        expect(rejected, @"invalid index rejection");
        expectOrder(parent, a, c, nil);
        NSLog(@"PASS: indexed insertion, moves, reparenting, and validation");
    }
    return 0;
}
