#import <CoreText/CoreTextExport.h>
#import <CoreFoundation/CoreFoundation.h>
#import <CoreGraphics/CoreGraphics.h>

CF_IMPLICIT_BRIDGING_ENABLED

typedef struct __CTFrame* CTFrameRef;

CFTypeID CTFrameGetTypeID(void);

typedef CF_ENUM(uint32_t, CTFrameProgression)
{
    kCTFrameProgressionTopToBottom  = 0,
    kCTFrameProgressionRightToLeft  = 1,
    kCTFrameProgressionLeftToRight  = 2
};

typedef CF_ENUM(uint32_t, CTFramePathFillRule)
{
    kCTFramePathFillEvenOdd         = 0,
    kCTFramePathFillWindingNumber   = 1
};

CORETEXT_EXPORT const CFStringRef kCTFrameProgressionAttributeName;
CORETEXT_EXPORT const CFStringRef kCTFramePathFillRuleAttributeName;
CORETEXT_EXPORT const CFStringRef kCTFramePathWidthAttributeName;
CORETEXT_EXPORT const CFStringRef kCTFrameClippingPathsAttributeName;
CORETEXT_EXPORT const CFStringRef kCTFramePathClippingPathAttributeName;

CORETEXT_EXPORT CFRange CTFrameGetStringRange(CTFrameRef frame);
CORETEXT_EXPORT CFRange CTFrameGetVisibleStringRange(CTFrameRef frame);
CORETEXT_EXPORT CGPathRef CTFrameGetPath(CTFrameRef frame);
CORETEXT_EXPORT CFDictionaryRef CTFrameGetFrameAttributes(CTFrameRef frame);
CORETEXT_EXPORT CFArrayRef CTFrameGetLines(CTFrameRef frame);
CORETEXT_EXPORT void CTFrameGetLineOrigins(CTFrameRef frame, CFRange range, CGPoint *origins);
CORETEXT_EXPORT void CTFrameDraw(CTFrameRef frame, CGContextRef context);

CF_IMPLICIT_BRIDGING_DISABLED
