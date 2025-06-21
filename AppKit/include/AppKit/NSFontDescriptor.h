/* Copyright (c) 2007 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <AppKit/AppKitExport.h>
#import <Foundation/NSObject.h>

@class NSDictionary, NSAffineTransform, NSArray, NSSet;

typedef NSString *NSFontDescriptorAttributeName;

APPKIT_EXPORT NSFontDescriptorAttributeName const NSFontFamilyAttribute;
APPKIT_EXPORT NSFontDescriptorAttributeName const NSFontNameAttribute;
APPKIT_EXPORT NSFontDescriptorAttributeName const NSFontFaceAttribute;
APPKIT_EXPORT NSFontDescriptorAttributeName const NSFontSizeAttribute;
APPKIT_EXPORT NSFontDescriptorAttributeName const NSFontVisibleNameAttribute;
APPKIT_EXPORT NSFontDescriptorAttributeName const NSFontMatrixAttribute;
APPKIT_EXPORT NSFontDescriptorAttributeName const NSFontVariationAttribute;
APPKIT_EXPORT NSFontDescriptorAttributeName const NSFontCharacterSetAttribute;
APPKIT_EXPORT NSFontDescriptorAttributeName const NSFontCascadeListAttribute;
APPKIT_EXPORT NSFontDescriptorAttributeName const NSFontTraitsAttribute;
APPKIT_EXPORT NSFontDescriptorAttributeName const NSFontFixedAdvanceAttribute;
APPKIT_EXPORT NSFontDescriptorAttributeName const NSFontFeatureSettingsAttribute;

typedef NSString *NSFontDescriptorFeatureKey;

APPKIT_EXPORT NSFontDescriptorFeatureKey const NSFontFeatureTypeIdentifierKey;
APPKIT_EXPORT NSFontDescriptorFeatureKey const NSFontFeatureSelectorIdentifierKey;

typedef unsigned NSFontSymbolicTraits;
typedef NSString *NSFontDescriptorTraitKey;

APPKIT_EXPORT NSFontDescriptorTraitKey const NSFontSymbolicTrait;
APPKIT_EXPORT NSFontDescriptorTraitKey const NSFontWeightTrait;
APPKIT_EXPORT NSFontDescriptorTraitKey const NSFontWidthTrait;
APPKIT_EXPORT NSFontDescriptorTraitKey const NSFontSlantTrait;

typedef CGFloat NSFontWeight;

APPKIT_EXPORT const NSFontWeight NSFontWeightThin;
APPKIT_EXPORT const NSFontWeight NSFontWeightLight;
APPKIT_EXPORT const NSFontWeight NSFontWeightUltraLight;
APPKIT_EXPORT const NSFontWeight NSFontWeightBlack;
APPKIT_EXPORT const NSFontWeight NSFontWeightHeavy;
APPKIT_EXPORT const NSFontWeight NSFontWeightSemibold;
APPKIT_EXPORT const NSFontWeight NSFontWeightBold;
APPKIT_EXPORT const NSFontWeight NSFontWeightMedium;
APPKIT_EXPORT const NSFontWeight NSFontWeightRegular;

@interface NSFontDescriptor : NSObject <NSCopying> {
    NSDictionary *_attributes;
}

- initWithFontAttributes: (NSDictionary *) attributes;

+ fontDescriptorWithFontAttributes: (NSDictionary *) attributes;
+ fontDescriptorWithName: (NSString *) name
                  matrix: (NSAffineTransform *) matrix;
+ fontDescriptorWithName: (NSString *) name size: (CGFloat) pointSize;

- (NSDictionary *) fontAttributes;

- objectForKey: (NSString *) attributeKey;

- (CGFloat) pointSize;
- (NSAffineTransform *) matrix;
- (NSFontSymbolicTraits) symbolicTraits;

- (NSFontDescriptor *) fontDescriptorByAddingAttributes:
        (NSDictionary *) attributes;
- (NSFontDescriptor *) fontDescriptorWithFace: (NSString *) face;
- (NSFontDescriptor *) fontDescriptorWithFamily: (NSString *) family;
- (NSFontDescriptor *) fontDescriptorWithMatrix: (NSAffineTransform *) matrix;
- (NSFontDescriptor *) fontDescriptorWithSize: (CGFloat) pointSize;
- (NSFontDescriptor *) fontDescriptorWithSymbolicTraits:
        (NSFontSymbolicTraits) traits;

- (NSArray *) matchingFontDescriptorsWithMandatoryKeys: (NSSet *) keys;
- (NSFontDescriptor *) matchingFontDescriptorWithMandatoryKeys: (NSSet *) keys;

@end
