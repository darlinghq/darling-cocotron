// Copyright (C) 2026 Lubos Dolezel
//
// CATiledLayer defaults and storage, and CATransform3DGetAffineTransform.
// Defaults (256 x 256 tiles, one level of detail, bias 0, fadeDuration 0.25,
// superclass CALayer, archive keys tileSize/levelsOfDetail/levelsOfDetailBias)
// and the affine extraction were observed on macOS 26.7.3.
#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation.h>
#include <stdio.h>

static int failures;

#define CHECK(cond, msg) \
    do { \
        if (!(cond)) { \
            fprintf(stderr, "FAIL line %d: %s\n", __LINE__, msg); \
            failures++; \
        } \
    } while (0)

int main(void) {
    @autoreleasepool {
        CATransform3D t = CATransform3DMakeAffineTransform(CGAffineTransformMake(1, 2, 3, 4, 5, 6));
        t.m13 = 9;
        t.m33 = 7;
        CGAffineTransform a = CATransform3DGetAffineTransform(t);
        CHECK(a.a == 1 && a.b == 2 && a.c == 3 && a.d == 4 && a.tx == 5 && a.ty == 6, "affine part");
        CATransform3D u = CATransform3DIdentity;
        u.m11 = 2; u.m12 = 3; u.m21 = 4; u.m22 = 5; u.m41 = 6; u.m42 = 7; u.m14 = 1;
        a = CATransform3DGetAffineTransform(u);
        CHECK(a.a == 2 && a.b == 3 && a.c == 4 && a.d == 5 && a.tx == 6 && a.ty == 7, "m14 ignored");

        CATiledLayer *layer = [CATiledLayer layer];
        CHECK([layer isKindOfClass: [CALayer class]], "is a CALayer");
        CHECK(layer.tileSize.width == 256 && layer.tileSize.height == 256, "default tile size");
        CHECK(layer.levelsOfDetail == 1 && layer.levelsOfDetailBias == 0, "default levels of detail");
        CHECK([CATiledLayer fadeDuration] == 0.25, "fadeDuration");
        layer.tileSize = CGSizeMake(64, 32);
        layer.levelsOfDetail = 3;
        layer.levelsOfDetailBias = 2;
        CHECK(layer.tileSize.width == 64 && layer.tileSize.height == 32, "tile size stored");
        CHECK(layer.levelsOfDetail == 3 && layer.levelsOfDetailBias == 2, "levels stored");

        NSData *data = [NSKeyedArchiver archivedDataWithRootObject: layer requiringSecureCoding: NO error: NULL];
        CATiledLayer *copy = [NSKeyedUnarchiver unarchivedObjectOfClass: [CALayer class] fromData: data error: NULL];
        CHECK([copy isKindOfClass: [CATiledLayer class]], "archive round trip class");
        CHECK(copy.tileSize.width == 64 && copy.tileSize.height == 32 && copy.levelsOfDetail == 3 &&
              copy.levelsOfDetailBias == 2, "archive round trip values");
    }
    if (failures == 0)
        printf("PASS: CATiledLayer and CATransform3DGetAffineTransform\n");
    return failures ? 1 : 0;
}
