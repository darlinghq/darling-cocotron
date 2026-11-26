/*
 This file is part of Darling.

 Copyright (C) 2019 Lubos Dolezel

 Darling is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Darling is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with Darling.  If not, see <http://www.gnu.org/licenses/>.
*/

#import "CAFilter.h"

NSString *const kCAFilterAlphaThreshold = @"alphaThreshold";
NSString *const kCAFilterAverageColor = @"averageColor";
NSString *const kCAFilterColorBrightness = @"colorBrightness";
NSString *const kCAFilterColorContrast = @"colorContrast";
NSString *const kCAFilterColorHueRotate = @"colorHueRotate";
NSString *const kCAFilterColorInvert = @"colorInvert";
NSString *const kCAFilterColorMatrix = @"colorMatrix";
NSString *const kCAFilterColorMonochrome = @"colorMonochrome";
NSString *const kCAFilterColorSaturate = @"colorSaturate";
NSString *const kCAFilterCurves = @"curves";
NSString *const kCAFilterGaussianBlur = @"gaussianBlur";
NSString *const kCAFilterLuminanceCurveMap = @"luminanceCurveMap";
NSString *const kCAFilterLuminanceToAlpha = @"luminanceToAlpha";
NSString *const kCAFilterMultiplyBlendMode = @"multiplyBlendMode";
NSString *const kCAFilterMultiplyColor = @"multiplyColor";
NSString *const kCAFilterVariableBlur = @"variableBlur";
NSString *const kCAFilterVibrantColorMatrix = @"vibrantColorMatrix";

// Blend mode filter names. They are also accepted as CALayer compositingFilter
// strings. The strings were read from the exported constants on macOS 26.7.3
// (black-box observation); 10.14.4 exports the same ones, except the color,
// hue, luminosity and saturation modes.
NSString *const kCAFilterColorBlendMode = @"colorBlendMode";
NSString *const kCAFilterColorBurnBlendMode = @"colorBurnBlendMode";
NSString *const kCAFilterColorDodgeBlendMode = @"colorDodgeBlendMode";
NSString *const kCAFilterDarkenBlendMode = @"darkenBlendMode";
NSString *const kCAFilterDifferenceBlendMode = @"differenceBlendMode";
NSString *const kCAFilterExclusionBlendMode = @"exclusionBlendMode";
NSString *const kCAFilterHardLightBlendMode = @"hardLightBlendMode";
NSString *const kCAFilterHueBlendMode = @"hueBlendMode";
NSString *const kCAFilterLightenBlendMode = @"lightenBlendMode";
NSString *const kCAFilterLuminosityBlendMode = @"luminosityBlendMode";
NSString *const kCAFilterOverlayBlendMode = @"overlayBlendMode";
NSString *const kCAFilterSaturationBlendMode = @"saturationBlendMode";
NSString *const kCAFilterScreenBlendMode = @"screenBlendMode";
NSString *const kCAFilterSoftLightBlendMode = @"softLightBlendMode";
// Read from the exported constants on macOS 26.7.3 and 10.14.4, as above.
NSString *const kCAFilterPlusD = @"plusD";
NSString *const kCAFilterPlusL = @"plusL";

NSString *const kCAFilterInputAlphaValues = @"inputAlphaValues";
NSString *const kCAFilterInputAmount = @"inputAmount";
NSString *const kCAFilterInputAngle = @"inputAngle";
NSString *const kCAFilterInputBias = @"inputBias";
NSString *const kCAFilterInputBlueValues = @"inputBlueValues";
NSString *const kCAFilterInputColor = @"inputColor";
NSString *const kCAFilterInputColorMatrix = @"inputColorMatrix";
NSString *const kCAFilterInputDither = @"inputDither";
NSString *const kCAFilterInputGreenValues = @"inputGreenValues";
NSString *const kCAFilterInputHardEdges = @"inputHardEdges";
NSString *const kCAFilterInputNormalizeEdges = @"inputNormalizeEdges";
NSString *const kCAFilterInputPremultipliedValues = @"inputPremultipliedValues";
NSString *const kCAFilterInputRadius = @"inputRadius";
NSString *const kCAFilterInputRedValues = @"inputRedValues";
NSString *const kCAFilterInputValues = @"inputValues";

// The inputs are archived inside this wrapper, as on macOS.
@interface LKNSDictionaryCodingProxy : NSObject <NSSecureCoding> {
@public
    NSDictionary *dict;
}
@end

@implementation LKNSDictionaryCodingProxy
+ (BOOL) supportsSecureCoding {
    return YES;
}

- (void) encodeWithCoder: (NSCoder *) coder {
    [coder encodeObject: dict forKey: @"dict"];
}

- (instancetype) initWithCoder: (NSCoder *) coder {
    self = [super init];
    if (self != nil) {
        NSSet *classes = [NSSet setWithObjects: [NSDictionary class], [NSMutableDictionary class], [NSString class],
                                                [NSNumber class], [NSValue class], [NSData class], [NSArray class],
                                                [NSNull class], nil];
        dict = [[coder decodeObjectOfClasses: classes forKey: @"dict"] retain];
    }
    return self;
}

- (void) dealloc {
    [dict release];
    [super dealloc];
}
@end

@implementation CAFilter

NS_EXTRA_SYNTHESIZE_COPY(CAFilter, name, _name, NSString *, name, setName:)
NS_EXTRA_SYNTHESIZE_ASSIGN(CAFilter, enabled, _enabled, BOOL, isEnabled, setEnabled:)

+ (instancetype) filterWithType: (NSString *) type {
    return [[[self alloc] initWithType: type] autorelease];
}

+ (instancetype) filterWithName: (NSString *) name {
    return [[[self alloc] initWithName: name] autorelease];
}

// QUIRK: a filter made with a nil type is still an object and enabled; its type
// reads as the string "<nil>", and so does its name when made with
// -initWithType:nil. Plain -init gives a disabled filter whose type reads
// "<nil>" and whose name is nil. Not documented (the class is private SPI).
// Evidence: black-box observation on macOS 26.7.3 (tier 2), vd-upstream
// mac-probes/v317-cafilter-more.m and v317-cafilter-nil-type.m.
// Test: tests/quartzcore-cafilter.m (quirk_nil_type_makes_an_object)
- (instancetype) init {
    self = [super init];
    if (self != nil)
        NS_EXTRA(CAFilter, self)->_inputs = [[NSMutableDictionary alloc] init];
    return self;
}

- (instancetype) initWithType: (NSString *) type {
    self = [self init];
    if (self != nil) {
        NS_EXTRA(CAFilter, self)->_type = [type copy];
        NS_EXTRA(CAFilter, self)->_name = [(type != nil ? type : @"<nil>") copy];
        NS_EXTRA(CAFilter, self)->_enabled = YES;
    }
    return self;
}

// The older, name-based initialiser: the name is the type.
- (instancetype) initWithName: (NSString *) name {
    return [self initWithType: name];
}

- (void) dealloc {
    [NS_EXTRA(CAFilter, self)->_type release];
    [NS_EXTRA(CAFilter, self)->_name release];
    [NS_EXTRA(CAFilter, self)->_inputs release];
    NS_EXTRA_FREE(CAFilter, self);
    [super dealloc];
}

- (NSString *) type {
    return NS_EXTRA(CAFilter, self)->_type != nil ? NS_EXTRA(CAFilter, self)->_type : @"<nil>";
}

+ (BOOL) supportsSecureCoding {
    return YES;
}

// Keys as on macOS; the inputs are written only when there are any.
- (void) encodeWithCoder: (NSCoder *) coder {
    if (![coder allowsKeyedCoding])
        [NSException raise: NSInvalidArgumentException format: @"CAFilter needs a keyed coder"];
    [coder encodeObject: NS_EXTRA(CAFilter, self)->_type forKey: @"CAFilterType"];
    [coder encodeObject: NS_EXTRA(CAFilter, self)->_name forKey: @"CAFilterName"];
    [coder encodeBool: NS_EXTRA(CAFilter, self)->_enabled forKey: @"CAFilterEnabled"];
    if ([NS_EXTRA(CAFilter, self)->_inputs count] > 0) {
        LKNSDictionaryCodingProxy *proxy = [[LKNSDictionaryCodingProxy alloc] init];
        proxy->dict = [[NSMutableDictionary alloc] initWithDictionary: NS_EXTRA(CAFilter, self)->_inputs];
        [coder encodeObject: proxy forKey: @"CAFilterInputs"];
        [proxy release];
    }
}

- (instancetype) initWithCoder: (NSCoder *) coder {
    if (![coder allowsKeyedCoding]) {
        [self release];
        [NSException raise: NSInvalidArgumentException format: @"CAFilter needs a keyed coder"];
    }
    self = [self init];
    if (self == nil)
        return nil;
    NS_EXTRA(CAFilter, self)->_type = [[coder decodeObjectOfClass: [NSString class] forKey: @"CAFilterType"] copy];
    NS_EXTRA(CAFilter, self)->_name = [[coder decodeObjectOfClass: [NSString class] forKey: @"CAFilterName"] copy];
    NS_EXTRA(CAFilter, self)->_enabled = [coder decodeBoolForKey: @"CAFilterEnabled"];
    LKNSDictionaryCodingProxy *proxy = [coder decodeObjectOfClass: [LKNSDictionaryCodingProxy class] forKey: @"CAFilterInputs"];
    if (proxy != nil && proxy->dict != nil)
        [NS_EXTRA(CAFilter, self)->_inputs setDictionary: proxy->dict];
    return self;
}

- (id) copyWithZone: (NSZone *) zone {
    CAFilter *copy = [[[self class] allocWithZone: zone] initWithType: NS_EXTRA(CAFilter, self)->_type];
    [copy setName: NS_EXTRA(CAFilter, self)->_name];
    [copy setEnabled: NS_EXTRA(CAFilter, self)->_enabled];
    [NS_EXTRA(CAFilter, copy)->_inputs setDictionary: NS_EXTRA(CAFilter, self)->_inputs];
    return copy;
}

- (id) valueForUndefinedKey: (NSString *) key {
    return [NS_EXTRA(CAFilter, self)->_inputs objectForKey: key];
}

- (void) setValue: (id) value forUndefinedKey: (NSString *) key {
    if (value == nil) {
        [NS_EXTRA(CAFilter, self)->_inputs removeObjectForKey: key];
    } else {
        [NS_EXTRA(CAFilter, self)->_inputs setObject: value forKey: key];
    }
}

- (NSString *) description {
    return [NSString stringWithFormat: @"<%@: %p; type = %@; name = %@; inputs = %@>",
                                       [self class], self, NS_EXTRA(CAFilter, self)->_type, NS_EXTRA(CAFilter, self)->_name, NS_EXTRA(CAFilter, self)->_inputs];
}

@end
