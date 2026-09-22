#import <CoreText/CoreTextExport.h>
#import <CoreGraphics/CoreGraphics.h>

CF_IMPLICIT_BRIDGING_ENABLED

typedef struct __CTLine* CTLineRef;

typedef CF_OPTIONS(CFOptionFlags, CTLineBoundsOptions)
{
    kCTLineBoundsExcludeTypographicLeading  = 1 << 0,
    kCTLineBoundsExcludeTypographicShifts   = 1 << 1,
    kCTLineBoundsUseHangingPunctuation      = 1 << 2,
    kCTLineBoundsUseGlyphPathBounds         = 1 << 3,
    kCTLineBoundsUseOpticalBounds           = 1 << 4,
    kCTLineBoundsIncludeLanguageExtents     = 1 << 5,
};

typedef CF_ENUM(uint32_t, CTLineTruncationType)
{
    kCTLineTruncationStart  = 0,
    kCTLineTruncationEnd    = 1,
    kCTLineTruncationMiddle = 2
};

CORETEXT_EXPORT CFTypeID CTLineGetTypeID(void);
CORETEXT_EXPORT CTLineRef CTLineCreateWithAttributedString(CFAttributedStringRef attrString);

CORETEXT_EXPORT CTLineRef CTLineCreateTruncatedLine(CTLineRef line, double width,
                                                    CTLineTruncationType truncationType,
                                                    CTLineRef truncationToken);

CORETEXT_EXPORT CTLineRef _Nullable CTLineCreateJustifiedLine(CTLineRef line, CGFloat justificationFactor, double justificationWidth);

CORETEXT_EXPORT CFIndex CTLineGetGlyphCount(CTLineRef line);
CORETEXT_EXPORT CFArrayRef CTLineGetGlyphRuns(CTLineRef line);
CORETEXT_EXPORT CFRange CTLineGetStringRange(CTLineRef line);
CORETEXT_EXPORT double CTLineGetPenOffsetForFlush(CTLineRef line, CGFloat flushFactor, double flushWidth);

CORETEXT_EXPORT void CTLineDraw(CTLineRef line, CGContextRef context);

CORETEXT_EXPORT double CTLineGetTypographicBounds(CTLineRef line, CGFloat * ascent, CGFloat * descent, CGFloat * leading);

CORETEXT_EXPORT CGRect CTLineGetBoundsWithOptions(CTLineRef line, CTLineBoundsOptions options);
CORETEXT_EXPORT double CTLineGetTrailingWhitespaceWidth(CTLineRef line);
CORETEXT_EXPORT CGRect CTLineGetImageBounds(CTLineRef line, CGContextRef context);

CORETEXT_EXPORT CFIndex CTLineGetStringIndexForPosition(CTLineRef line, CGPoint position);
CORETEXT_EXPORT CGFloat CTLineGetOffsetForStringIndex(CTLineRef line, CFIndex charIndex, CGFloat *secondaryOffset);

CF_IMPLICIT_BRIDGING_DISABLED
