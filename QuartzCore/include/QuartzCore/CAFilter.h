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

#import <Foundation/Foundation.h>
#import <QuartzCore/CABase.h>

CA_EXPORT NSString *const kCAFilterAlphaThreshold;
CA_EXPORT NSString *const kCAFilterAverageColor;
CA_EXPORT NSString *const kCAFilterColorBrightness;
CA_EXPORT NSString *const kCAFilterColorContrast;
CA_EXPORT NSString *const kCAFilterColorHueRotate;
CA_EXPORT NSString *const kCAFilterColorInvert;
CA_EXPORT NSString *const kCAFilterColorMatrix;
CA_EXPORT NSString *const kCAFilterColorMonochrome;
CA_EXPORT NSString *const kCAFilterColorSaturate;
CA_EXPORT NSString *const kCAFilterCurves;
CA_EXPORT NSString *const kCAFilterGaussianBlur;
CA_EXPORT NSString *const kCAFilterLuminanceCurveMap;
CA_EXPORT NSString *const kCAFilterLuminanceToAlpha;
CA_EXPORT NSString *const kCAFilterMultiplyBlendMode;
CA_EXPORT NSString *const kCAFilterMultiplyColor;
CA_EXPORT NSString *const kCAFilterVariableBlur;
CA_EXPORT NSString *const kCAFilterVibrantColorMatrix;

CA_EXPORT NSString *const kCAFilterInputAlphaValues;
CA_EXPORT NSString *const kCAFilterInputAmount;
CA_EXPORT NSString *const kCAFilterInputAngle;
CA_EXPORT NSString *const kCAFilterInputBias;
CA_EXPORT NSString *const kCAFilterInputBlueValues;
CA_EXPORT NSString *const kCAFilterInputColor;
CA_EXPORT NSString *const kCAFilterInputColorMatrix;
CA_EXPORT NSString *const kCAFilterInputDither;
CA_EXPORT NSString *const kCAFilterInputGreenValues;
CA_EXPORT NSString *const kCAFilterInputHardEdges;
CA_EXPORT NSString *const kCAFilterInputNormalizeEdges;
CA_EXPORT NSString *const kCAFilterInputPremultipliedValues;
CA_EXPORT NSString *const kCAFilterInputRadius;
CA_EXPORT NSString *const kCAFilterInputRedValues;
CA_EXPORT NSString *const kCAFilterInputValues;

// Private Core Animation filter. Input values are stored with key-value coding
// under their input keys; CARenderer does not apply filters yet.
@interface CAFilter : NSObject <NSCopying> {
    NSString *_type;
    NSString *_name;
    BOOL _enabled;
    NSMutableDictionary *_inputs;
}

+ (instancetype) filterWithType: (NSString *) type;
- (instancetype) initWithType: (NSString *) type;

@property(readonly, copy) NSString *type;
@property(copy) NSString *name;
@property(getter=isEnabled) BOOL enabled;

@end
