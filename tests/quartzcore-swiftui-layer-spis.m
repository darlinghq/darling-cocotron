// Copyright (C) 2026 Lubos Dolezel
//
// QuartzCore classes, properties and constants that SwiftUI imports. Expected values are from macOS 26.7.3
// (black-box):
//  - CAChameleonLayer exists and is a CALayer; the constants kCAFilterBox "box", kCAContentsFormatA8 "A8",
//    kCAContentsScalingRepeat "repeat", kCAContentsScalingStretch "stretch", kCALayerContentsSwizzleAAAA
//    "AAAA", kCALayerContentsSwizzleRGBA "RGBA";
//  - a new CALayer has contentsSwizzle "RGBA", contentsScaling "stretch", a white contentsMultiplyColor,
//    wantsExtendedDynamicRangeContent NO, contentsMaximumDesiredEDR 0 and no presentation modifiers;
//    setting the swizzle to nil gives nil, the multiply colour to NULL gives NULL;
//  - a new CABackdropLayer has scale 1, allowsInPlaceFiltering NO and no groupName;
//  - a CAPresentationModifierGroup of capacity 4 has count 0 and updatesAsynchronously YES; a modifier made
//    with a group is enabled and raises the group's count to 1; -setValue:velocity: is accepted.
// Build: clang -framework QuartzCore -framework Foundation quartzcore-swiftui-layer-spis.m (no ARC)
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#include <dlfcn.h>
#include <stdio.h>

@interface CABackdropLayer : CALayer
@property CGFloat scale;
@property BOOL allowsInPlaceFiltering;
@property (copy) NSString *groupName;
@end
@interface CAPresentationModifierGroup : NSObject
+ (instancetype) groupWithCapacity: (NSUInteger) capacity;
@property BOOL updatesAsynchronously;
@property (readonly) NSUInteger count;
@property (readonly) NSUInteger capacity;
- (void) flush;
- (void) flushWithTargetTime: (double) targetTime;
- (void) flushLocally;
- (void) flushLocallyWithTargetTime: (double) targetTime;
- (void) flushWithTransactionAndTargetTime: (double) targetTime;
@end
@interface CAPresentationModifier : NSObject
- (instancetype) initWithKeyPath: (NSString *) keyPath initialValue: (id) value additive: (BOOL) additive;
- (instancetype) initWithKeyPath: (NSString *) keyPath initialValue: (id) value additive: (BOOL) additive
                           group: (CAPresentationModifierGroup *) group;
- (instancetype) initWithKeyPath: (NSString *) keyPath initialValue: (id) value initialVelocity: (id) velocity
                        additive: (BOOL) additive preferredFrameRateRangeMaximum: (NSInteger) maximum
                           group: (CAPresentationModifierGroup *) group;
@property (getter = isEnabled) BOOL enabled;
@property (retain) id value;
- (void) setValue: (id) value velocity: (id) velocity;
@end
@interface CALayer (Q3SPI)
@property (copy) NSString *contentsSwizzle;
@property (copy) NSString *contentsScaling;
@property CGColorRef contentsMultiplyColor;
@property BOOL wantsExtendedDynamicRangeContent;
@property CGFloat contentsMaximumDesiredEDR;
@property (copy) NSArray *presentationModifiers;
- (void) addPresentationModifier: (CAPresentationModifier *) modifier;
- (void) removePresentationModifier: (CAPresentationModifier *) modifier;
@end

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static void constant(const char *symbol, NSString *value) {
    NSString **p = dlsym(RTLD_DEFAULT, symbol);
    if (p == NULL || ![*p isEqualToString: value]) {
        fprintf(stderr, "FAIL %s is %s, expected %s\n", symbol, p ? [*p UTF8String] : "(missing)", [value UTF8String]);
        failures++;
    }
}

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    constant("kCAFilterBox", @"box");
    constant("kCAContentsFormatA8", @"A8");
    constant("kCAContentsScalingRepeat", @"repeat");
    constant("kCAContentsScalingStretch", @"stretch");
    constant("kCALayerContentsSwizzleAAAA", @"AAAA");
    constant("kCALayerContentsSwizzleRGBA", @"RGBA");

    Class chameleon = NSClassFromString(@"CAChameleonLayer");
    CHECK(chameleon != Nil && [chameleon isSubclassOfClass: [CALayer class]]);

    CALayer *layer = [CALayer layer];
    CHECK([[layer contentsSwizzle] isEqualToString: @"RGBA"]);
    CHECK([[layer contentsScaling] isEqualToString: @"stretch"]);
    CGColorRef multiply = [layer contentsMultiplyColor];
    CHECK(multiply != NULL);
    if (multiply != NULL && CGColorGetNumberOfComponents(multiply) == 4) {
        const CGFloat *c = CGColorGetComponents(multiply);
        CHECK(c[0] == 1 && c[1] == 1 && c[2] == 1 && c[3] == 1);
    }
    CHECK([layer wantsExtendedDynamicRangeContent] == NO);
    CHECK([layer contentsMaximumDesiredEDR] == 0);
    CHECK([layer presentationModifiers] == nil);
    [layer setContentsSwizzle: @"AAAA"];
    CHECK([[layer contentsSwizzle] isEqualToString: @"AAAA"]);
    [layer setContentsSwizzle: nil];
    CHECK([layer contentsSwizzle] == nil);
    [layer setContentsMultiplyColor: NULL];
    CHECK([layer contentsMultiplyColor] == NULL);
    [layer setWantsExtendedDynamicRangeContent: YES];
    CHECK([layer wantsExtendedDynamicRangeContent] == YES);

    CABackdropLayer *backdrop = [CABackdropLayer layer];
    CHECK([backdrop scale] == 1 && [backdrop allowsInPlaceFiltering] == NO && [backdrop groupName] == nil);
    [backdrop setGroupName: @"group"];
    CHECK([[backdrop groupName] isEqualToString: @"group"]);

    CAPresentationModifierGroup *group = [CAPresentationModifierGroup groupWithCapacity: 4];
    CHECK([group capacity] == 4 && [group count] == 0 && [group updatesAsynchronously] == YES);
    CAPresentationModifier *modifier = [[[CAPresentationModifier alloc] initWithKeyPath: @"opacity"
            initialValue: [NSNumber numberWithInt: 1] additive: NO group: group] autorelease];
    CHECK([modifier isEnabled] == YES && [group count] == 1);
    [modifier setValue: [NSNumber numberWithInt: 2] velocity: [NSNumber numberWithInt: 3]];
    CHECK([[modifier value] isEqual: [NSNumber numberWithInt: 2]]);
    CAPresentationModifier *plain = [[[CAPresentationModifier alloc] initWithKeyPath: @"opacity"
            initialValue: [NSNumber numberWithInt: 1] additive: NO] autorelease];
    CHECK(plain != nil);
    [layer addPresentationModifier: modifier];
    CHECK([[layer presentationModifiers] count] == 1);
    [layer removePresentationModifier: modifier];
    CHECK([[layer presentationModifiers] count] == 0);
    [group flush];
    [group flushWithTargetTime: 0];
    [group flushLocally];
    [group flushLocallyWithTargetTime: 0];
    [group flushWithTransactionAndTargetTime: 0];

    if (failures == 0)
        printf("PASS quartzcore-swiftui-layer-spis\n");
    [pool release];
    return failures != 0;
}
