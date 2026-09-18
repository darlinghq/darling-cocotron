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

APPKIT_EXPORT NSFontDescriptorAttributeName NSFontFamilyAttribute;
APPKIT_EXPORT NSFontDescriptorAttributeName NSFontNameAttribute;
APPKIT_EXPORT NSFontDescriptorAttributeName NSFontFaceAttribute;
APPKIT_EXPORT NSFontDescriptorAttributeName NSFontSizeAttribute;
APPKIT_EXPORT NSFontDescriptorAttributeName NSFontVisibleNameAttribute;
APPKIT_EXPORT NSFontDescriptorAttributeName NSFontMatrixAttribute;
APPKIT_EXPORT NSFontDescriptorAttributeName NSFontVariationAttribute;
APPKIT_EXPORT NSFontDescriptorAttributeName NSFontCharacterSetAttribute;
APPKIT_EXPORT NSFontDescriptorAttributeName NSFontCascadeListAttribute;
APPKIT_EXPORT NSFontDescriptorAttributeName NSFontTraitsAttribute;
APPKIT_EXPORT NSFontDescriptorAttributeName NSFontFixedAdvanceAttribute;
APPKIT_EXPORT NSFontDescriptorAttributeName NSFontFeatureSettingsAttribute;

typedef NSString *NSFontDescriptorFeatureKey;

APPKIT_EXPORT NSFontDescriptorFeatureKey NSFontFeatureTypeIdentifierKey;
APPKIT_EXPORT NSFontDescriptorFeatureKey NSFontFeatureSelectorIdentifierKey;

typedef unsigned NSFontSymbolicTraits;

enum {
    NSFontUnknownClass = 0 << 28,
    NSFontOldStyleSerifsClass = 1 << 28,
    NSFontTransitionalSerifsClass = 2 << 28,
    NSFontModernSerifsClass = 3 << 28,
    NSFontClarendonSerifsClass = 4 << 28,
    NSFontSlabSerifsClass = 5 << 28,
    NSFontFreeformSerifsClass = 7 << 28,
    NSFontSansSerifClass = 8 << 28,
    NSFontOrnamentalsClass = 9 << 28,
    NSFontScriptsClass = 10 << 28,
    NSFontSymbolicClass = 12 << 28,
    NSFontFamilyClassMask = 0xF0000000
};

enum {
    NSFontItalicTrait = (1 << 0),
    NSFontBoldTrait = (1 << 1),
    NSFontExpandedTrait = (1 << 5),
    NSFontCondensedTrait = (1 << 6),
    NSFontMonoSpaceTrait = (1 << 10),
    NSFontVerticalTrait = (1 << 11),
    NSFontUIOptimizedTrait = (1 << 12)
};

typedef NSString *NSFontDescriptorTraitKey;

APPKIT_EXPORT NSFontDescriptorTraitKey NSFontSymbolicTrait;
APPKIT_EXPORT NSFontDescriptorTraitKey NSFontWeightTrait;
APPKIT_EXPORT NSFontDescriptorTraitKey NSFontWidthTrait;
APPKIT_EXPORT NSFontDescriptorTraitKey NSFontSlantTrait;

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
