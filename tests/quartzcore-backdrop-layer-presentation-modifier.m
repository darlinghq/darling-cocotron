// Copyright (C) 2026 Darling Developers
//
// Private QuartzCore SPI that WebKit uses: the blend mode filter names,
// CABackdropLayer and CAPresentationModifier(Group). The classes keep their
// state; Darling does not render backdrops or apply modifiers yet.
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>
#include <stdlib.h>

// Declared by the client, as WebKit does: these classes are not public.
@interface CAFilter : NSObject
+ (instancetype)filterWithType:(NSString *)type;
@end

@interface CABackdropLayer : CALayer
@property BOOL windowServerAware;
@end

@interface CAPresentationModifierGroup : NSObject
+ (instancetype)groupWithCapacity:(NSUInteger)capacity;
- (void)flush;
- (void)flushWithTransaction;
@end

@interface CAPresentationModifier : NSObject
- (instancetype)initWithKeyPath:(NSString *)keyPath initialValue:(id)value additive:(BOOL)additive group:(CAPresentationModifierGroup *)group;
@property (retain) id value;
@end

@interface CAPresentationModifier (DarlingTestAccessors)
@property (readonly, copy) NSString *keyPath;
@property (readonly) BOOL additive;
@property (readonly, retain) CAPresentationModifierGroup *group;
@end

extern NSString *const kCAFilterMultiplyBlendMode, *const kCAFilterScreenBlendMode,
    *const kCAFilterOverlayBlendMode, *const kCAFilterDarkenBlendMode, *const kCAFilterLightenBlendMode,
    *const kCAFilterColorDodgeBlendMode, *const kCAFilterColorBurnBlendMode, *const kCAFilterSoftLightBlendMode,
    *const kCAFilterHardLightBlendMode, *const kCAFilterDifferenceBlendMode, *const kCAFilterExclusionBlendMode,
    *const kCAFilterHueBlendMode, *const kCAFilterSaturationBlendMode, *const kCAFilterColorBlendMode,
    *const kCAFilterLuminosityBlendMode, *const kCAFilterPlusD, *const kCAFilterPlusL;

static void expect(BOOL condition, const char *message)
{
    if (!condition)
    {
        printf("FAIL: %s\n", message);
        exit(1);
    }
}

int main(void)
{
    @autoreleasepool
    {
        // The compositingFilter string seen in public code.
        expect([kCAFilterScreenBlendMode isEqualToString:@"screenBlendMode"], "screen blend mode name");
        NSString *const all[] = { kCAFilterMultiplyBlendMode, kCAFilterScreenBlendMode, kCAFilterOverlayBlendMode,
            kCAFilterDarkenBlendMode, kCAFilterLightenBlendMode, kCAFilterColorDodgeBlendMode,
            kCAFilterColorBurnBlendMode, kCAFilterSoftLightBlendMode, kCAFilterHardLightBlendMode,
            kCAFilterDifferenceBlendMode, kCAFilterExclusionBlendMode, kCAFilterHueBlendMode,
            kCAFilterSaturationBlendMode, kCAFilterColorBlendMode, kCAFilterLuminosityBlendMode,
            kCAFilterPlusD, kCAFilterPlusL };
        NSUInteger count = sizeof(all) / sizeof(all[0]);
        expect([[NSSet setWithObjects:all count:count] count] == count, "filter names are distinct");
        for (NSUInteger i = 0; i < count; i++)
        {
            CAFilter *filter = [CAFilter filterWithType:all[i]];
            expect([[filter valueForKey:@"type"] isEqualToString:all[i]], "a filter made from a blend mode name keeps it");
        }
        CALayer *composited = [CALayer layer];
        composited.compositingFilter = kCAFilterPlusL;
        expect([composited.compositingFilter isEqual:kCAFilterPlusL], "a name works as a compositing filter string");

        // CABackdropLayer
        CABackdropLayer *backdrop = [CABackdropLayer layer];
        expect([backdrop isKindOfClass:[CALayer class]], "backdrop layer is a layer");
        // as on macOS 26.7.3 and 10.14.4
        expect(!backdrop.windowServerAware, "not window server aware by default");
        backdrop.windowServerAware = YES;
        expect(backdrop.windowServerAware, "window server awareness is kept");
        [backdrop setValue:@NO forKey:@"windowServerAware"];
        expect(!backdrop.windowServerAware, "window server awareness through KVC");
        backdrop.windowServerAware = YES;
        backdrop.filters = @[ [CAFilter filterWithType:@"gaussianBlur"] ];
        expect(backdrop.filters.count == 1, "filters are kept");
        CABackdropLayer *copy = [[[CABackdropLayer alloc] initWithLayer:backdrop] autorelease];
        expect(!copy.windowServerAware, "initWithLayer: does not copy window server awareness");
        CABackdropLayer *fromPlain = [[[CABackdropLayer alloc] initWithLayer:[CALayer layer]] autorelease];
        expect(!fromPlain.windowServerAware, "initWithLayer: of a plain layer uses the default");

        // CAPresentationModifier
        CAPresentationModifierGroup *group = [CAPresentationModifierGroup groupWithCapacity:2];
        expect(group != nil, "group");
        CAPresentationModifier *opacity = [[[CAPresentationModifier alloc] initWithKeyPath:@"opacity"
            initialValue:@0.5 additive:NO group:group] autorelease];
        expect([opacity.value isEqual:@0.5], "initial value");
        expect([opacity.keyPath isEqualToString:@"opacity"], "key path");
        expect(!opacity.additive, "not additive");
        expect(opacity.group == group, "group is kept");
        opacity.value = @1;
        expect([opacity.value isEqual:@1], "value is updated");
        // (macOS 26.7.3 raises an exception for a nil initial value)
        CAPresentationModifier *offset = [[[CAPresentationModifier alloc] initWithKeyPath:@"shadowRadius"
            initialValue:@2 additive:YES group:nil] autorelease];
        expect([offset.value isEqual:@2] && offset.additive && offset.group == nil, "no group, additive");
        [group flush];
        [group flushWithTransaction];
        expect([opacity.value isEqual:@1], "flushing keeps the value");
    }
    printf("PASS\n");
    return 0;
}
