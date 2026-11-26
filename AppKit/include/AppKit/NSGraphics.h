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

#import <AppKit/AppKitExport.h>
#import <ApplicationServices/ApplicationServices.h>
#import <Foundation/Foundation.h>

@class NSColor;

typedef NSString *NSColorSpaceName NS_TYPED_ENUM;

typedef NS_ENUM(NSUInteger, NSCompositingOperation) {
    NSCompositingOperationClear = 0,
    NSCompositingOperationCopy = 1,
    NSCompositingOperationSourceOver = 2,
    NSCompositingOperationSourceIn = 3,
    NSCompositingOperationSourceOut = 4,
    NSCompositingOperationSourceAtop = 5,
    NSCompositingOperationDestinationOver = 6,
    NSCompositingOperationDestinationIn = 7,
    NSCompositingOperationDestinationOut = 8,
    NSCompositingOperationDestinationAtop = 9,
    NSCompositingOperationXOR = 10,
    NSCompositingOperationPlusDarker = 11,
    NSCompositingOperationHighlight = 12,
    NSCompositingOperationPlusLighter = 13,
    NSCompositingOperationMultiply = 14,
    NSCompositingOperationScreen = 15,
    NSCompositingOperationOverlay = 16,
    NSCompositingOperationDarken = 17,
    NSCompositingOperationLighten = 18,
    NSCompositingOperationColorDodge = 19,
    NSCompositingOperationColorBurn = 20,
    NSCompositingOperationSoftLight = 21,
    NSCompositingOperationHardLight = 22,
    NSCompositingOperationDifference = 23,
    NSCompositingOperationExclusion = 24,
    NSCompositingOperationHue = 25,
    NSCompositingOperationSaturation = 26,
    NSCompositingOperationColor = 27,
    NSCompositingOperationLuminosity = 28
};

// The pre-10.12 names of the first fourteen operations, kept for source
// compatibility. As in the macOS SDK they are typed constants, not enumerators,
// so they convert to NSCompositingOperation without a cast.
static const NSCompositingOperation NSCompositeClear = NSCompositingOperationClear;
static const NSCompositingOperation NSCompositeCopy = NSCompositingOperationCopy;
static const NSCompositingOperation NSCompositeSourceOver = NSCompositingOperationSourceOver;
static const NSCompositingOperation NSCompositeSourceIn = NSCompositingOperationSourceIn;
static const NSCompositingOperation NSCompositeSourceOut = NSCompositingOperationSourceOut;
static const NSCompositingOperation NSCompositeSourceAtop = NSCompositingOperationSourceAtop;
static const NSCompositingOperation NSCompositeDestinationOver = NSCompositingOperationDestinationOver;
static const NSCompositingOperation NSCompositeDestinationIn = NSCompositingOperationDestinationIn;
static const NSCompositingOperation NSCompositeDestinationOut = NSCompositingOperationDestinationOut;
static const NSCompositingOperation NSCompositeDestinationAtop = NSCompositingOperationDestinationAtop;
static const NSCompositingOperation NSCompositeXOR = NSCompositingOperationXOR;
static const NSCompositingOperation NSCompositePlusDarker = NSCompositingOperationPlusDarker;
static const NSCompositingOperation NSCompositeHighlight = NSCompositingOperationHighlight;
static const NSCompositingOperation NSCompositePlusLighter = NSCompositingOperationPlusLighter;

typedef NS_ENUM(NSInteger, NSWindowOrderingMode) {
    NSWindowBelow = -1,
    NSWindowOut = 0,
    NSWindowAbove = 1
} NS_SWIFT_NAME(NSWindow.OrderingMode);

typedef enum {
    NSFocusRingOnly,
    NSFocusRingBelow,
    NSFocusRingAbove
} NSFocusRingPlacement;

typedef NS_ENUM(NSUInteger, NSFocusRingType) {
    NSFocusRingTypeDefault = 0,
    NSFocusRingTypeNone = 1,
    NSFocusRingTypeExterior = 2
};

typedef NS_ENUM(int32_t, NSWindowDepth) {
    NSWindowDepthTwentyfourBitRGB = 0x208,
    NSWindowDepthSixtyfourBitRGB = 0x210,
    NSWindowDepthOnehundredtwentyeightBitRGB = 0x220
};

typedef NS_ENUM(NSUInteger, NSAnimationEffect) {
    NSAnimationEffectDisappearingItemDefault = 0,
    NSAnimationEffectPoof = 10
};

// Depth negotiation. NSAvailableWindowDepths returns a pointer to a static,
// zero-terminated array.
APPKIT_EXPORT NSWindowDepth NSBestDepth(NSColorSpaceName colorSpace,
                                        NSInteger bitsPerSample,
                                        NSInteger bitsPerPixel, BOOL planar,
                                        BOOL *_Nullable exactMatch);
APPKIT_EXPORT BOOL NSPlanarFromDepth(NSWindowDepth depth);
APPKIT_EXPORT NSColorSpaceName _Nullable NSColorSpaceFromDepth(
        NSWindowDepth depth);
APPKIT_EXPORT NSInteger NSBitsPerSampleFromDepth(NSWindowDepth depth);
APPKIT_EXPORT NSInteger NSBitsPerPixelFromDepth(NSWindowDepth depth);
APPKIT_EXPORT const NSWindowDepth *_Nonnull NSAvailableWindowDepths(void);

APPKIT_EXPORT const CGFloat NSBlack;
APPKIT_EXPORT const CGFloat NSDarkGray;
APPKIT_EXPORT const CGFloat NSLightGray;
APPKIT_EXPORT const CGFloat NSWhite;

APPKIT_EXPORT NSColorSpaceName const NSDeviceBlackColorSpace;
APPKIT_EXPORT NSColorSpaceName const NSDeviceWhiteColorSpace;
APPKIT_EXPORT NSColorSpaceName const NSDeviceRGBColorSpace;
APPKIT_EXPORT NSColorSpaceName const NSDeviceCMYKColorSpace;
APPKIT_EXPORT NSColorSpaceName const NSCalibratedBlackColorSpace;
APPKIT_EXPORT NSColorSpaceName const NSCalibratedWhiteColorSpace;
APPKIT_EXPORT NSColorSpaceName const NSCalibratedRGBColorSpace;
APPKIT_EXPORT NSColorSpaceName const NSNamedColorSpace;
APPKIT_EXPORT NSColorSpaceName const NSPatternColorSpace;
APPKIT_EXPORT NSColorSpaceName const NSCustomColorSpace;

APPKIT_EXPORT NSString *const NSDeviceIsScreen;
APPKIT_EXPORT NSString *const NSDeviceIsPrinter;
APPKIT_EXPORT NSString *const NSDeviceSize;
APPKIT_EXPORT NSString *const NSDeviceResolution;
APPKIT_EXPORT NSString *const NSDeviceColorSpaceName;
APPKIT_EXPORT NSString *const NSDeviceBitsPerSample;

APPKIT_EXPORT void NSRectClipList(const NSRect *rects, NSInteger count);
APPKIT_EXPORT void NSRectClip(NSRect rect);

APPKIT_EXPORT void NSRectFillListWithColors(
        const NSRect *rects, NSColor *const _Nonnull *_Nonnull colors,
        NSInteger count);
APPKIT_EXPORT void NSRectFillListWithGrays(const NSRect *rects,
                                           const CGFloat *grays,
                                           NSInteger count);
APPKIT_EXPORT void NSRectFillList(const NSRect *rects, NSInteger count);
APPKIT_EXPORT void NSRectFill(NSRect rect);

APPKIT_EXPORT void NSEraseRect(NSRect rect);

APPKIT_EXPORT void
NSRectFillListUsingOperation(const NSRect *rects, NSInteger count,
                             NSCompositingOperation operation);
APPKIT_EXPORT void NSRectFillListWithColorsUsingOperation(
        const NSRect *rects, NSColor *const _Nonnull *_Nonnull colors,
        NSInteger count, NSCompositingOperation operation);
APPKIT_EXPORT void NSRectFillUsingOperation(NSRect rect,
                                            NSCompositingOperation operation);

APPKIT_EXPORT void NSFrameRectWithWidth(NSRect rect, CGFloat width);
APPKIT_EXPORT void
NSFrameRectWithWidthUsingOperation(NSRect rect, CGFloat width,
                                   NSCompositingOperation operation);
APPKIT_EXPORT void NSFrameRect(NSRect rect);
APPKIT_EXPORT void NSDottedFrameRect(NSRect rect);

APPKIT_EXPORT void NSDrawButton(NSRect rect, NSRect clipRect);
APPKIT_EXPORT void NSDrawGrayBezel(NSRect rect, NSRect clipRect);
APPKIT_EXPORT void NSDrawWhiteBezel(NSRect rect, NSRect clipRect);
APPKIT_EXPORT void NSDrawDarkBezel(NSRect rect, NSRect clipRect);
APPKIT_EXPORT void NSDrawLightBezel(NSRect rect, NSRect clipRect);
APPKIT_EXPORT void NSDrawGroove(NSRect rect, NSRect clipRect);

APPKIT_EXPORT void NSDrawWindowBackground(NSRect rect);

APPKIT_EXPORT NSRect NSDrawTiledRects(NSRect bounds, NSRect clip,
                                      const NSRectEdge *sides,
                                      const CGFloat *grays, int count);

APPKIT_EXPORT void NSHighlightRect(NSRect rect);
APPKIT_EXPORT void NSCopyBits(int gState, NSRect rect, NSPoint point);

APPKIT_EXPORT void NSBeep(void);

APPKIT_EXPORT void NSEnableScreenUpdates(void);
APPKIT_EXPORT void NSDisableScreenUpdates(void);

APPKIT_EXPORT void NSShowAnimationEffect(NSAnimationEffect effect,
                                         NSPoint center, NSSize size,
                                         id delegate, SEL didEndSelector,
                                         void *context);
typedef NS_ENUM(NSInteger, NSDisplayGamut) {
    NSDisplayGamutSRGB = 1,
    NSDisplayGamutP3,
};

