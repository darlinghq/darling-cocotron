/* Copyright (c) 2006-2007 Christopher J. W. Lloyd

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

#import <ApplicationServices/ApplicationServices.h>
#import <AppKit/AppKitIvarLayout.h>
#import <Foundation/NSObject.h>

typedef NS_ENUM(NSInteger, NSColorSpaceModel) {
    NSColorSpaceModelUnknown = -1,
    NSColorSpaceModelGray,
    NSColorSpaceModelRGB,
    NSColorSpaceModelCMYK,
    NSColorSpaceModelLAB,
    NSColorSpaceModelDeviceN,
    NSColorSpaceModelIndexed,
    NSColorSpaceModelPatterned,
};

@interface NSColorSpace : NSObject {
    CGColorSpaceRef _cgColorSpace;
    NS_LEGACY_IVAR_PAD(_NSColorSpaceReserved, 28)
}

@property(class, strong, readonly) NSColorSpace *deviceRGBColorSpace;
@property(class, strong, readonly) NSColorSpace *sRGBColorSpace;
@property(class, strong, readonly) NSColorSpace *displayP3ColorSpace;
@property(class, strong, readonly) NSColorSpace *genericRGBColorSpace;
@property(class, strong, readonly) NSColorSpace *genericGrayColorSpace;
@property(class, strong, readonly) NSColorSpace *genericGamma22GrayColorSpace;
@property(class, strong, readonly) NSColorSpace *extendedSRGBColorSpace;
@property(class, strong, readonly) NSColorSpace *deviceGrayColorSpace;
@property(class, strong, readonly) NSColorSpace *deviceCMYKColorSpace;
@property(class, strong, readonly) NSColorSpace *genericCMYKColorSpace;
@property(class, strong, readonly) NSColorSpace *adobeRGB1998ColorSpace;

+ (NSColorSpace *) deviceRGBColorSpace;

- initWithCGColorSpace: (CGColorSpaceRef) cgColorSpace;
- (nullable instancetype) initWithICCProfileData: (NSData *) iccData;

- (CGColorSpaceRef) CGColorSpace;

@property(nullable, readonly, copy) NSString *localizedName;
@property(readonly) NSColorSpaceModel colorSpaceModel;
@property(readonly) NSInteger numberOfColorComponents;
@property(nullable, readonly, copy) NSData *ICCProfileData;

@end
