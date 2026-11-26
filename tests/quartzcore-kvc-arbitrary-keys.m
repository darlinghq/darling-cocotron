// Copyright (C) 2026 Lubos Dolezel
//
// Guest test: CALayer and CAAnimation as key-value coding containers, which
// hold values for keys they have no property for (Core Animation Programming
// Guide, "Key-Value Coding Extensions"). WebKit keeps its layer tree node on
// each layer this way. Expected values were observed on macOS 26.7.3
// (x86_64): an unset key reads as nil without raising, a set value reads back,
// setting nil removes it, +defaultValueForKey: is not consulted for such keys,
// and -initWithLayer: does not carry them over. The default values checked
// below are the ones macOS gives for the same keys.
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#include <math.h>
#include <stdio.h>

@interface TestDefaultLayer : CALayer
@end
@implementation TestDefaultLayer
+ (id)defaultValueForKey:(NSString *)key
{
    return [key isEqualToString: @"withDefault"] ? @"D" : [super defaultValueForKey: key];
}
@end

static int failures;

static void report(const char *name, BOOL ok)
{
    printf("%s: %s\n", ok ? "PASS" : "FAIL", name);
    if (!ok)
        failures++;
}

int main(void)
{
    @autoreleasepool {
        CALayer *layer = [CALayer layer];
        id value = @"raised";
        @try {
            value = [layer valueForKey: @"someArbitraryKey"];
        } @catch (NSException *exception) {
        }
        report("layer: an unset key reads as nil", value == nil);

        [layer setValue: @42 forKey: @"someArbitraryKey"];
        report("layer: a set value reads back", [[layer valueForKey: @"someArbitraryKey"] isEqual: @42]);
        [layer setValue: nil forKey: @"someArbitraryKey"];
        report("layer: setting nil removes it", [layer valueForKey: @"someArbitraryKey"] == nil);

        [layer setValue: [NSValue valueWithPointer: (void *)0x1234] forKey: @"pointerKey"];
        report("layer: a pointer value reads back", [[layer valueForKey: @"pointerKey"] pointerValue] == (void *)0x1234);

        report("layer: +defaultValueForKey: is nil for an arbitrary key", [CALayer defaultValueForKey: @"someArbitraryKey"] == nil);
        TestDefaultLayer *subclassed = [TestDefaultLayer layer];
        report("layer: +defaultValueForKey: is not consulted for an arbitrary key", [subclassed valueForKey: @"withDefault"] == nil);

        [layer setValue: @"v" forKey: @"copied"];
        CALayer *copy = [[[CALayer alloc] initWithLayer: layer] autorelease];
        report("layer: -initWithLayer: does not carry arbitrary keys", [copy valueForKey: @"copied"] == nil);

        report("layer: -valueForKeyPath: with one component", [[layer valueForKeyPath: @"copied"] isEqual: @"v"]);
        [layer setValue: @"q" forKeyPath: @"viaPath"];
        report("layer: -setValue:forKeyPath: with one component", [[layer valueForKey: @"viaPath"] isEqual: @"q"]);

        [layer setValue: @0.5 forKey: @"opacity"];
        report("layer: a real property still goes to its accessor", layer.opacity == 0.5f);

        report("defaults: opacity 1", [[CALayer defaultValueForKey: @"opacity"] isEqual: @1]);
        report("defaults: hidden NO", [[CALayer defaultValueForKey: @"hidden"] isEqual: @NO]);
        report("defaults: doubleSided YES", [[CALayer defaultValueForKey: @"doubleSided"] isEqual: @YES]);
        report("defaults: bounds nil", [CALayer defaultValueForKey: @"bounds"] == nil);
        report("defaults: cornerRadius nil", [CALayer defaultValueForKey: @"cornerRadius"] == nil);
        report("defaults: shadowOpacity nil", [CALayer defaultValueForKey: @"shadowOpacity"] == nil);
        report("defaults: anchorPoint (0.5, 0.5)", NSEqualPoints([[CALayer defaultValueForKey: @"anchorPoint"] pointValue], NSMakePoint(0.5, 0.5)));
        report("defaults: shadowOffset (0, -3)", NSEqualSizes([[CALayer defaultValueForKey: @"shadowOffset"] sizeValue], NSMakeSize(0, -3)));
        report("defaults: shadowRadius 3", [[CALayer defaultValueForKey: @"shadowRadius"] isEqual: @3]);
        report("defaults: contentsRect unit rectangle", NSEqualRects([[CALayer defaultValueForKey: @"contentsRect"] rectValue], NSMakeRect(0, 0, 1, 1)));
        report("defaults: contentsGravity resize", [[CALayer defaultValueForKey: @"contentsGravity"] isEqual: @"resize"]);
        report("defaults: minificationFilter linear", [[CALayer defaultValueForKey: @"minificationFilter"] isEqual: @"linear"]);
        report("defaults: edgeAntialiasingMask 15", [[CALayer defaultValueForKey: @"edgeAntialiasingMask"] isEqual: @15]);
        report("defaults: fillMode removed", [[CALayer defaultValueForKey: @"fillMode"] isEqual: @"removed"]);
        report("defaults: duration infinite", isinf([[CALayer defaultValueForKey: @"duration"] doubleValue]));
        CGColorRef shadowColor = (CGColorRef) [CALayer defaultValueForKey: @"shadowColor"];
        report("defaults: shadowColor opaque black", shadowColor != NULL && CGColorGetNumberOfComponents(shadowColor) == 4
                                                         && CGColorGetComponents(shadowColor)[0] == 0 && CGColorGetComponents(shadowColor)[3] == 1);
        report("needsDisplayForKey: NO for opacity", ![CALayer needsDisplayForKey: @"opacity"]);
        report("animation defaults: speed 1", [[CABasicAnimation defaultValueForKey: @"speed"] isEqual: @1]);
        report("animation defaults: removedOnCompletion YES", [[CABasicAnimation defaultValueForKey: @"removedOnCompletion"] isEqual: @YES]);
        report("animation defaults: duration nil", [CABasicAnimation defaultValueForKey: @"duration"] == nil);

        CABasicAnimation *animation = [CABasicAnimation animation];
        report("animation: an unset key reads as nil", [animation valueForKey: @"anyKey"] == nil);
        [animation setValue: @"A" forKey: @"anyKey"];
        report("animation: a set value reads back", [[animation valueForKey: @"anyKey"] isEqual: @"A"]);
        [animation setValue: nil forKey: @"anyKey"];
        report("animation: setting nil removes it", [animation valueForKey: @"anyKey"] == nil);
    }
    return failures != 0;
}
