#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>
#include <stdlib.h>

static void expect(BOOL condition, const char *message)
{
    if (!condition)
    {
        fprintf(stderr, "FAIL: %s\n", message);
        exit(1);
    }
}

int main(void)
{
    @autoreleasepool
    {
        NSArray *ranges = @[CADynamicRangeAutomatic, CADynamicRangeStandard,
                            CADynamicRangeConstrainedHigh, CADynamicRangeHigh];
        NSArray *modes = @[CAToneMapModeAutomatic, CAToneMapModeNever, CAToneMapModeIfSupported];
        expect([NSSet setWithArray: ranges].count == ranges.count, "dynamic ranges are distinct");
        expect([NSSet setWithArray: modes].count == modes.count, "tone map modes are distinct");

        CALayer *layer = [CALayer layer];
        expect([layer.preferredDynamicRange isEqualToString: CADynamicRangeStandard], "default dynamic range");
        expect([layer.toneMapMode isEqualToString: CAToneMapModeAutomatic], "default tone map mode");

        NSMutableString *range = [NSMutableString stringWithString: CADynamicRangeHigh];
        layer.preferredDynamicRange = range;
        [range setString: @"changed"];
        expect([layer.preferredDynamicRange isEqualToString: CADynamicRangeHigh], "dynamic range is copied");

        layer.toneMapMode = CAToneMapModeNever;
        expect([layer.toneMapMode isEqualToString: CAToneMapModeNever], "tone map mode is stored");

        // Key-value setters are what apps reach through layer-backed views.
        [layer setValue: CADynamicRangeConstrainedHigh forKey: @"preferredDynamicRange"];
        expect([layer.preferredDynamicRange isEqualToString: CADynamicRangeConstrainedHigh], "KVC dynamic range");
    }
    printf("PASS\n");
    return 0;
}
