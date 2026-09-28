#import <CoreText/CTRun.h>
#import "KTCoreTextInternal.h"
#include <string.h>

static CFRange normalizedRange(CTRunRef run, CFRange range)
{
    CFIndex count = CTRunGetGlyphCount(run);
    if (range.location < 0 || range.location > count || range.length < 0)
        return CFRangeMake(0, 0);
    if (range.length == 0 || range.length > count - range.location)
        range.length = count - range.location;
    return range;
}

CFTypeID CTRunGetTypeID(void)
{
    return KTCoreTextRunGetTypeID();
}

CFIndex CTRunGetGlyphCount(CTRunRef run)
{
    if (run == NULL)
        return 0;
    return KTCoreTextDictionaryGetIndex(KTCoreTextObjectDictionary(run),
                                         KTRunGlyphCountKey);
}

CFDictionaryRef CTRunGetAttributes(CTRunRef run)
{
    if (run == NULL)
        return NULL;
    return CFDictionaryGetValue(KTCoreTextObjectDictionary(run), KTRunAttributesKey);
}

CTRunStatus CTRunGetStatus(CTRunRef run)
{
    return kCTRunStatusNoStatus;
}

const CGGlyph *CTRunGetGlyphsPtr(CTRunRef run)
{
    if (run == NULL)
        return NULL;
    CFDataRef data = CFDictionaryGetValue(KTCoreTextObjectDictionary(run),
                                          KTRunGlyphsKey);
    return (const CGGlyph *)CFDataGetBytePtr(data);
}

void CTRunGetGlyphs(CTRunRef run, CFRange range, CGGlyph *buffer)
{
    if (buffer == NULL)
        return;
    range = normalizedRange(run, range);
    if (range.length == 0)
        return;
    memcpy(buffer, CTRunGetGlyphsPtr(run) + range.location,
           (size_t)range.length * sizeof(*buffer));
}

const CGPoint *CTRunGetPositionsPtr(CTRunRef run)
{
    if (run == NULL)
        return NULL;
    CFDataRef data = CFDictionaryGetValue(KTCoreTextObjectDictionary(run),
                                          KTRunPositionsKey);
    return (const CGPoint *)CFDataGetBytePtr(data);
}

void CTRunGetPositions(CTRunRef run, CFRange range, CGPoint *buffer)
{
    if (buffer == NULL)
        return;
    range = normalizedRange(run, range);
    if (range.length == 0)
        return;
    memcpy(buffer, CTRunGetPositionsPtr(run) + range.location,
           (size_t)range.length * sizeof(*buffer));
}

const CGSize *CTRunGetAdvancesPtr(CTRunRef run)
{
    if (run == NULL)
        return NULL;
    CFDataRef data = CFDictionaryGetValue(KTCoreTextObjectDictionary(run),
                                          KTRunAdvancesKey);
    return (const CGSize *)CFDataGetBytePtr(data);
}

void CTRunGetAdvances(CTRunRef run, CFRange range, CGSize *buffer)
{
    if (buffer == NULL)
        return;
    range = normalizedRange(run, range);
    if (range.length == 0)
        return;
    memcpy(buffer, CTRunGetAdvancesPtr(run) + range.location,
           (size_t)range.length * sizeof(*buffer));
}

const CFIndex *CTRunGetStringIndicesPtr(CTRunRef run)
{
    if (run == NULL)
        return NULL;
    CFDataRef data = CFDictionaryGetValue(KTCoreTextObjectDictionary(run),
                                          KTRunIndicesKey);
    return (const CFIndex *)CFDataGetBytePtr(data);
}

void CTRunGetStringIndices(CTRunRef run, CFRange range, CFIndex *buffer)
{
    if (buffer == NULL)
        return;
    range = normalizedRange(run, range);
    if (range.length == 0)
        return;
    memcpy(buffer, CTRunGetStringIndicesPtr(run) + range.location,
           (size_t)range.length * sizeof(*buffer));
}

CFRange CTRunGetStringRange(CTRunRef run)
{
    if (run == NULL)
        return CFRangeMake(kCFNotFound, 0);
    CFDictionaryRef dictionary = KTCoreTextObjectDictionary(run);
    return CFRangeMake(KTCoreTextDictionaryGetIndex(
                               dictionary, KTRunRangeLocationKey),
                       KTCoreTextDictionaryGetIndex(
                               dictionary, KTRunRangeLengthKey));
}

double CTRunGetTypographicBounds(CTRunRef run, CFRange range, CGFloat *ascent,
                                 CGFloat *descent, CGFloat *leading)
{
    if (run == NULL)
        return 0;
    CFDictionaryRef dictionary = KTCoreTextObjectDictionary(run);
    if (ascent != NULL)
        *ascent = KTCoreTextDictionaryGetFloat(dictionary, KTRunAscentKey);
    if (descent != NULL)
        *descent = KTCoreTextDictionaryGetFloat(dictionary, KTRunDescentKey);
    if (leading != NULL)
        *leading = KTCoreTextDictionaryGetFloat(dictionary, KTRunLeadingKey);

    range = normalizedRange(run, range);
    const CGSize *advances = CTRunGetAdvancesPtr(run);
    CGFloat width = 0;
    for (CFIndex index = 0; index < range.length; ++index)
        width += advances[range.location + index].width;
    return width;
}

CGRect CTRunGetImageBounds(CTRunRef run, CGContextRef context, CFRange range)
{
    CGFloat ascent = 0;
    CGFloat descent = 0;
    CGFloat leading = 0;
    CGFloat width = CTRunGetTypographicBounds(run, range, &ascent, &descent,
                                               &leading);
    return CGRectMake(0, -descent, width, ascent + descent + leading);
}

CGAffineTransform CTRunGetTextMatrix(CTRunRef run)
{
    return CGAffineTransformIdentity;
}

void CTRunGetBaseAdvancesAndOrigins(CTRunRef run, CFRange range,
                                    CGSize *advancesBuffer,
                                    CGPoint *originsBuffer)
{
    // Each accessor normalizes the original caller range exactly once.
    if (advancesBuffer != NULL)
        CTRunGetAdvances(run, range, advancesBuffer);
    if (originsBuffer != NULL)
        CTRunGetPositions(run, range, originsBuffer);
}

void CTRunDraw(CTRunRef run, CGContextRef context, CFRange range)
{
    if (run == NULL || context == NULL)
        return;
    range = normalizedRange(run, range);
    if (range.length == 0)
        return;
    CTFontRef font = (CTFontRef)CFDictionaryGetValue(CTRunGetAttributes(run),
                                                     kCTFontAttributeName);
    if (font == NULL)
        return;
    CTFontDrawGlyphs(font, CTRunGetGlyphsPtr(run) + range.location,
                     CTRunGetPositionsPtr(run) + range.location,
                     (size_t)range.length, context);
}
