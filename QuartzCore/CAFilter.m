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

@implementation CAFilter

@synthesize type = _type;
@synthesize name = _name;
@synthesize enabled = _enabled;

+ (instancetype) filterWithType: (NSString *) type {
    return [[[self alloc] initWithType: type] autorelease];
}

- (instancetype) init {
    return [self initWithType: nil];
}

- (instancetype) initWithType: (NSString *) type {
    if (type == nil) {
        [self release];
        return nil;
    }
    self = [super init];
    _type = [type copy];
    _name = [type copy];
    _enabled = YES;
    _inputs = [[NSMutableDictionary alloc] init];
    return self;
}

- (void) dealloc {
    [_type release];
    [_name release];
    [_inputs release];
    [super dealloc];
}

- (id) copyWithZone: (NSZone *) zone {
    CAFilter *copy = [[[self class] allocWithZone: zone] initWithType: _type];
    [copy setName: _name];
    [copy setEnabled: _enabled];
    [copy->_inputs setDictionary: _inputs];
    return copy;
}

- (id) valueForUndefinedKey: (NSString *) key {
    return [_inputs objectForKey: key];
}

- (void) setValue: (id) value forUndefinedKey: (NSString *) key {
    if (value == nil) {
        [_inputs removeObjectForKey: key];
    } else {
        [_inputs setObject: value forKey: key];
    }
}

- (NSString *) description {
    return [NSString stringWithFormat: @"<%@: %p; type = %@; name = %@; inputs = %@>",
                                       [self class], self, _type, _name, _inputs];
}

@end
