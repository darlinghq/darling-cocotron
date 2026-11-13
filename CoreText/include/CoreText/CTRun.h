#import <CoreText/CoreTextExport.h>
#import <CoreGraphics/CoreGraphics.h>

CF_IMPLICIT_BRIDGING_ENABLED

typedef struct __CTRun* CTRunRef;

typedef CF_OPTIONS(uint32_t, CTRunStatus)
{
    kCTRunStatusNoStatus = 0,
    kCTRunStatusRightToLeft = (1 << 0),
    kCTRunStatusNonMonotonic = (1 << 1),
    kCTRunStatusHasNonIdentityMatrix = (1 << 2)
};

CORETEXT_EXPORT CFTypeID CTRunGetTypeID(void);
CORETEXT_EXPORT CFIndex CTRunGetGlyphCount(CTRunRef run);
CORETEXT_EXPORT CFDictionaryRef CTRunGetAttributes(CTRunRef run);
CORETEXT_EXPORT CTRunStatus CTRunGetStatus(CTRunRef run);

CORETEXT_EXPORT const CGGlyph * CTRunGetGlyphsPtr(CTRunRef run);
CORETEXT_EXPORT void CTRunGetGlyphs(CTRunRef run, CFRange range, CGGlyph *buffer);

CORETEXT_EXPORT const CGPoint * CTRunGetPositionsPtr(CTRunRef run);
CORETEXT_EXPORT void CTRunGetPositions(CTRunRef run, CFRange range, CGPoint *buffer);

CORETEXT_EXPORT const CGSize * CTRunGetAdvancesPtr(CTRunRef run);

CORETEXT_EXPORT void CTRunGetAdvances(CTRunRef run, CFRange range, CGSize *buffer);

CORETEXT_EXPORT const CFIndex * CTRunGetStringIndicesPtr(CTRunRef run);

CORETEXT_EXPORT void CTRunGetStringIndices(CTRunRef run, CFRange range, CFIndex *buffer);

CORETEXT_EXPORT CFRange CTRunGetStringRange(CTRunRef run);

CORETEXT_EXPORT double CTRunGetTypographicBounds(CTRunRef run, CFRange range, CGFloat *ascent, CGFloat *descent, CGFloat *leading);

CORETEXT_EXPORT CGRect CTRunGetImageBounds(CTRunRef run, CGContextRef context, CFRange range);

CORETEXT_EXPORT CGAffineTransform CTRunGetTextMatrix(CTRunRef run);

CORETEXT_EXPORT void CTRunGetBaseAdvancesAndOrigins(CTRunRef runRef, CFRange range, CGSize *advancesBuffer, CGPoint *originsBuffer);

CORETEXT_EXPORT void CTRunDraw(CTRunRef run, CGContextRef context, CFRange range);

CF_IMPLICIT_BRIDGING_DISABLED
