#import <CoreText/CTLine.h>
#import <CoreText/CTRun.h>
#import "KTCoreTextInternal.h"
#include <stdlib.h>
#include <CoreFoundation/CFRuntime.h>
#include <pthread.h>

struct KTCoreTextObject {
    CFRuntimeBase base;
    CFDictionaryRef storage;
};

static void finalizeCoreTextObject(CFTypeRef value) {
    const struct KTCoreTextObject *object = value;
    if (object->storage != NULL)
        CFRelease(object->storage);
}

static const CFRuntimeClass lineClass = {
    0, "CTLine", NULL, NULL, finalizeCoreTextObject, NULL, NULL, NULL, NULL,
};
static const CFRuntimeClass runClass = {
    0, "CTRun", NULL, NULL, finalizeCoreTextObject, NULL, NULL, NULL, NULL,
};
static CFTypeID lineTypeID, runTypeID;
static pthread_once_t registerObjectsOnce = PTHREAD_ONCE_INIT;

static void registerCoreTextObjects(void) {
    lineTypeID = _CFRuntimeRegisterClass(&lineClass);
    runTypeID = _CFRuntimeRegisterClass(&runClass);
}

CFTypeID KTCoreTextRunGetTypeID(void) {
    pthread_once(&registerObjectsOnce, registerCoreTextObjects);
    return runTypeID;
}

CFDictionaryRef KTCoreTextObjectDictionary(CFTypeRef value) {
    return value == NULL ? NULL : ((const struct KTCoreTextObject *)value)->storage;
}

static CFTypeRef createCoreTextObject(CFTypeID type, CFDictionaryRef storage) {
    struct KTCoreTextObject *object = (struct KTCoreTextObject *)
            _CFRuntimeCreateInstance(kCFAllocatorDefault, type,
                    sizeof(*object) - sizeof(CFRuntimeBase), NULL);
    if (object == NULL)
        return NULL;
    object->storage = CFRetain(storage);
    return object;
}

const CFStringRef KTLineAttributedStringKey = CFSTR("KTLineAttributedString");
const CFStringRef KTLineRunsKey = CFSTR("KTLineRuns");
const CFStringRef KTLineRangeLocationKey = CFSTR("KTLineRangeLocation");
const CFStringRef KTLineRangeLengthKey = CFSTR("KTLineRangeLength");
const CFStringRef KTLineWidthKey = CFSTR("KTLineWidth");
const CFStringRef KTLineAscentKey = CFSTR("KTLineAscent");
const CFStringRef KTLineDescentKey = CFSTR("KTLineDescent");
const CFStringRef KTLineLeadingKey = CFSTR("KTLineLeading");

const CFStringRef KTRunAttributesKey = CFSTR("KTRunAttributes");
const CFStringRef KTRunGlyphsKey = CFSTR("KTRunGlyphs");
const CFStringRef KTRunPositionsKey = CFSTR("KTRunPositions");
const CFStringRef KTRunAdvancesKey = CFSTR("KTRunAdvances");
const CFStringRef KTRunIndicesKey = CFSTR("KTRunIndices");
const CFStringRef KTRunRangeLocationKey = CFSTR("KTRunRangeLocation");
const CFStringRef KTRunRangeLengthKey = CFSTR("KTRunRangeLength");
const CFStringRef KTRunGlyphCountKey = CFSTR("KTRunGlyphCount");
const CFStringRef KTRunWidthKey = CFSTR("KTRunWidth");
const CFStringRef KTRunAscentKey = CFSTR("KTRunAscent");
const CFStringRef KTRunDescentKey = CFSTR("KTRunDescent");
const CFStringRef KTRunLeadingKey = CFSTR("KTRunLeading");

CFIndex KTCoreTextDictionaryGetIndex(CFDictionaryRef dictionary,
                                    CFStringRef key)
{
    CFIndex value = 0;
    CFNumberRef number = CFDictionaryGetValue(dictionary, key);
    if (number != NULL)
        CFNumberGetValue(number, kCFNumberCFIndexType, &value);
    return value;
}

CGFloat KTCoreTextDictionaryGetFloat(CFDictionaryRef dictionary,
                                     CFStringRef key)
{
    CGFloat value = 0;
    CFNumberRef number = CFDictionaryGetValue(dictionary, key);
    if (number != NULL)
        CFNumberGetValue(number, kCFNumberCGFloatType, &value);
    return value;
}

void KTCoreTextDictionarySetIndex(CFMutableDictionaryRef dictionary,
                                  CFStringRef key, CFIndex value)
{
    CFNumberRef number = CFNumberCreate(kCFAllocatorDefault,
                                        kCFNumberCFIndexType, &value);
    CFDictionarySetValue(dictionary, key, number);
    CFRelease(number);
}

void KTCoreTextDictionarySetFloat(CFMutableDictionaryRef dictionary,
                                  CFStringRef key, CGFloat value)
{
    CFNumberRef number = CFNumberCreate(kCFAllocatorDefault,
                                        kCFNumberCGFloatType, &value);
    CFDictionarySetValue(dictionary, key, number);
    CFRelease(number);
}

static CFDictionaryRef createRun(CFAttributedStringRef attributedString,
                                 CFRange range, CGFloat *linePosition)
{
    CFDictionaryRef attributes = CFAttributedStringGetAttributes(
            attributedString, range.location, NULL);
    CTFontRef font = (CTFontRef)CFDictionaryGetValue(attributes,
                                                     kCTFontAttributeName);
    if (font == NULL)
        font = (CTFontRef)CFDictionaryGetValue(attributes,
                                               CFSTR("NSFontAttributeName"));
    if (font == NULL || range.length <= 0)
        return NULL;

    size_t count = (size_t)range.length;
    if (count > SIZE_MAX / sizeof(UniChar) ||
        count > SIZE_MAX / sizeof(CGGlyph) ||
        count > SIZE_MAX / sizeof(CGPoint) ||
        count > SIZE_MAX / sizeof(CGSize) ||
        count > SIZE_MAX / sizeof(CFIndex))
        return NULL;

    UniChar *characters = calloc(count, sizeof(*characters));
    CGGlyph *glyphs = calloc(count, sizeof(*glyphs));
    CGPoint *positions = calloc(count, sizeof(*positions));
    CGSize *advances = calloc(count, sizeof(*advances));
    CFIndex *indices = calloc(count, sizeof(*indices));
    if (characters == NULL || glyphs == NULL || positions == NULL ||
        advances == NULL || indices == NULL) {
        free(characters);
        free(glyphs);
        free(positions);
        free(advances);
        free(indices);
        return NULL;
    }

    CFStringGetCharacters(CFAttributedStringGetString(attributedString), range,
                          characters);
    CTFontGetGlyphsForCharacters(font, characters, glyphs, range.length);
    CTFontGetAdvancesForGlyphs(font, kCTFontOrientationDefault, glyphs,
                               advances, range.length);

    CFStringRef string = CFAttributedStringGetString(attributedString);
    CGFloat runWidth = 0;
    for (CFIndex index = 0; index < range.length; ++index) {
        CFIndex characterIndex = range.location + index;
        CFRange cluster = CFStringGetRangeOfComposedCharactersAtIndex(
                string, characterIndex);
        if (cluster.location >= range.location &&
            cluster.location < characterIndex) {
            CFIndex baseIndex = cluster.location - range.location;
            positions[index] = positions[baseIndex];
            advances[index] = CGSizeZero;
            indices[index] = cluster.location;
        } else {
            positions[index] = CGPointMake(*linePosition + runWidth, 0);
            indices[index] = characterIndex;
            runWidth += advances[index].width;
        }
    }
    *linePosition += runWidth;

    CFMutableDictionaryRef run = CFDictionaryCreateMutable(
            kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks,
            &kCFTypeDictionaryValueCallBacks);
    CFMutableDictionaryRef runAttributes = CFDictionaryCreateMutableCopy(
            kCFAllocatorDefault, 0, attributes);
    CFDictionarySetValue(runAttributes, kCTFontAttributeName, font);
    CFDictionarySetValue(run, KTRunAttributesKey, runAttributes);
    CFRelease(runAttributes);

    CFDataRef data = CFDataCreate(kCFAllocatorDefault,
                                  (const UInt8 *)glyphs,
                                  count * sizeof(*glyphs));
    CFDictionarySetValue(run, KTRunGlyphsKey, data);
    CFRelease(data);
    data = CFDataCreate(kCFAllocatorDefault, (const UInt8 *)positions,
                        count * sizeof(*positions));
    CFDictionarySetValue(run, KTRunPositionsKey, data);
    CFRelease(data);
    data = CFDataCreate(kCFAllocatorDefault, (const UInt8 *)advances,
                        count * sizeof(*advances));
    CFDictionarySetValue(run, KTRunAdvancesKey, data);
    CFRelease(data);
    data = CFDataCreate(kCFAllocatorDefault, (const UInt8 *)indices,
                        count * sizeof(*indices));
    CFDictionarySetValue(run, KTRunIndicesKey, data);
    CFRelease(data);

    KTCoreTextDictionarySetIndex(run, KTRunRangeLocationKey, range.location);
    KTCoreTextDictionarySetIndex(run, KTRunRangeLengthKey, range.length);
    KTCoreTextDictionarySetIndex(run, KTRunGlyphCountKey, range.length);
    KTCoreTextDictionarySetFloat(run, KTRunWidthKey, runWidth);
    KTCoreTextDictionarySetFloat(run, KTRunAscentKey, CTFontGetAscent(font));
    KTCoreTextDictionarySetFloat(run, KTRunDescentKey, CTFontGetDescent(font));
    KTCoreTextDictionarySetFloat(run, KTRunLeadingKey, CTFontGetLeading(font));

    free(characters);
    free(glyphs);
    free(positions);
    free(advances);
    free(indices);
    return run;
}

static CTFontRef fontForAttributes(CFDictionaryRef attributes)
{
    CTFontRef font = (CTFontRef)CFDictionaryGetValue(attributes,
                                                     kCTFontAttributeName);
    if (font == NULL)
        font = (CTFontRef)CFDictionaryGetValue(attributes,
                                               CFSTR("NSFontAttributeName"));
    return font;
}

static bool rangeNeedsClusterRuns(CFAttributedStringRef attributedString,
                                  CFRange range, CTFontRef font)
{
    if (font == NULL || range.length <= 0)
        return false;

    size_t count = (size_t)range.length;
    UniChar *characters = calloc(count, sizeof(*characters));
    CGGlyph *glyphs = calloc(count, sizeof(*glyphs));
    if (characters == NULL || glyphs == NULL) {
        free(characters);
        free(glyphs);
        return false;
    }

    CFStringRef string = CFAttributedStringGetString(attributedString);
    CFStringGetCharacters(string, range, characters);
    CTFontGetGlyphsForCharacters(font, characters, glyphs, range.length);
    bool needed = false;
    for (CFIndex index = 0; index < range.length; ++index) {
        CFIndex characterIndex = range.location + index;
        CFRange cluster = CFStringGetRangeOfComposedCharactersAtIndex(
                string, characterIndex);
        if (glyphs[index] == 0 || cluster.length > 1) {
            needed = true;
            break;
        }
    }
    free(characters);
    free(glyphs);
    return needed;
}

static CFDictionaryRef createClusterRun(
        CFAttributedStringRef attributedString, CFDictionaryRef attributes,
        CFRange sourceRange, CTFontRef baseFont, CGFloat *linePosition)
{
    CFStringRef source = CFAttributedStringGetString(attributedString);
    CFStringRef substring = CFStringCreateWithSubstring(kCFAllocatorDefault,
                                                        source, sourceRange);
    if (substring == NULL)
        return NULL;
    CFMutableStringRef normalized = CFStringCreateMutableCopy(
            kCFAllocatorDefault, 0, substring);
    CFRelease(substring);
    if (normalized == NULL)
        return NULL;
    CFStringNormalize(normalized, kCFStringNormalizationFormC);

    CFIndex characterCount = CFStringGetLength(normalized);
    size_t count = (size_t)characterCount;
    UniChar *characters = calloc(count, sizeof(*characters));
    CGGlyph *mappedGlyphs = calloc(count, sizeof(*mappedGlyphs));
    CGGlyph *glyphs = calloc(count, sizeof(*glyphs));
    CGPoint *positions = calloc(count, sizeof(*positions));
    CGSize *advances = calloc(count, sizeof(*advances));
    CFIndex *indices = calloc(count, sizeof(*indices));
    if (characterCount <= 0 || characters == NULL || mappedGlyphs == NULL ||
        glyphs == NULL || positions == NULL || advances == NULL ||
        indices == NULL) {
        free(characters);
        free(mappedGlyphs);
        free(glyphs);
        free(positions);
        free(advances);
        free(indices);
        CFRelease(normalized);
        return NULL;
    }

    CFStringGetCharacters(normalized, CFRangeMake(0, characterCount),
                          characters);
    bool baseCovers = CTFontGetGlyphsForCharacters(
            baseFont, characters, mappedGlyphs, characterCount);
    CTFontRef selectedFont = baseFont;
    CTFontRef fallbackFont = NULL;
    if (!baseCovers) {
        fallbackFont = CTFontCreateForString(
                baseFont, normalized, CFRangeMake(0, characterCount));
        if (fallbackFont != NULL) {
            selectedFont = fallbackFont;
            memset(mappedGlyphs, 0, count * sizeof(*mappedGlyphs));
            CTFontGetGlyphsForCharacters(selectedFont, characters,
                                         mappedGlyphs, characterCount);
        }
    }

    CFIndex glyphCount = 0;
    for (CFIndex index = 0; index < characterCount; ++index) {
        glyphs[glyphCount] = mappedGlyphs[index];
        indices[glyphCount] = sourceRange.location;
        if (characters[index] >= 0xD800 && characters[index] <= 0xDBFF &&
            index + 1 < characterCount && characters[index + 1] >= 0xDC00 &&
            characters[index + 1] <= 0xDFFF)
            ++index;
        ++glyphCount;
    }

    CTFontGetAdvancesForGlyphs(selectedFont, kCTFontOrientationDefault,
                               glyphs, advances, glyphCount);
    CGFloat runWidth = 0;
    for (CFIndex index = 0; index < glyphCount; ++index) {
        positions[index] = CGPointMake(*linePosition, 0);
        if (index == 0)
            runWidth += advances[index].width;
        else
            advances[index] = CGSizeZero;
    }
    *linePosition += runWidth;

    CFMutableDictionaryRef run = CFDictionaryCreateMutable(
            kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks,
            &kCFTypeDictionaryValueCallBacks);
    CFMutableDictionaryRef runAttributes = CFDictionaryCreateMutableCopy(
            kCFAllocatorDefault, 0, attributes);
    CFDictionarySetValue(runAttributes, kCTFontAttributeName, selectedFont);
    CFDictionarySetValue(run, KTRunAttributesKey, runAttributes);
    CFRelease(runAttributes);

    CFDataRef data = CFDataCreate(kCFAllocatorDefault,
                                  (const UInt8 *)glyphs,
                                  (CFIndex)(glyphCount * sizeof(*glyphs)));
    CFDictionarySetValue(run, KTRunGlyphsKey, data);
    CFRelease(data);
    data = CFDataCreate(kCFAllocatorDefault, (const UInt8 *)positions,
                        (CFIndex)(glyphCount * sizeof(*positions)));
    CFDictionarySetValue(run, KTRunPositionsKey, data);
    CFRelease(data);
    data = CFDataCreate(kCFAllocatorDefault, (const UInt8 *)advances,
                        (CFIndex)(glyphCount * sizeof(*advances)));
    CFDictionarySetValue(run, KTRunAdvancesKey, data);
    CFRelease(data);
    data = CFDataCreate(kCFAllocatorDefault, (const UInt8 *)indices,
                        (CFIndex)(glyphCount * sizeof(*indices)));
    CFDictionarySetValue(run, KTRunIndicesKey, data);
    CFRelease(data);

    KTCoreTextDictionarySetIndex(run, KTRunRangeLocationKey,
                                 sourceRange.location);
    KTCoreTextDictionarySetIndex(run, KTRunRangeLengthKey,
                                 sourceRange.length);
    KTCoreTextDictionarySetIndex(run, KTRunGlyphCountKey, glyphCount);
    KTCoreTextDictionarySetFloat(run, KTRunWidthKey, runWidth);
    KTCoreTextDictionarySetFloat(run, KTRunAscentKey,
                                 CTFontGetAscent(selectedFont));
    KTCoreTextDictionarySetFloat(run, KTRunDescentKey,
                                 CTFontGetDescent(selectedFont));
    KTCoreTextDictionarySetFloat(run, KTRunLeadingKey,
                                 CTFontGetLeading(selectedFont));

    if (fallbackFont != NULL)
        CFRelease(fallbackFont);
    free(characters);
    free(mappedGlyphs);
    free(glyphs);
    free(positions);
    free(advances);
    free(indices);
    CFRelease(normalized);
    return run;
}

static bool appendRun(CFMutableArrayRef runs, CFDictionaryRef run,
                      CGFloat *ascent, CGFloat *descent, CGFloat *leading)
{
    if (run == NULL)
        return false;
    CFTypeRef object = createCoreTextObject(KTCoreTextRunGetTypeID(), run);
    if (object == NULL) {
        CFRelease(run);
        return false;
    }
    CFArrayAppendValue(runs, object);
    CFRelease(object);
    *ascent = MAX(*ascent, KTCoreTextDictionaryGetFloat(run,
                                                        KTRunAscentKey));
    *descent = MAX(*descent, KTCoreTextDictionaryGetFloat(run,
                                                          KTRunDescentKey));
    *leading = MAX(*leading, KTCoreTextDictionaryGetFloat(run,
                                                          KTRunLeadingKey));
    CFRelease(run);
    return true;
}

CFTypeID CTLineGetTypeID(void)
{
    pthread_once(&registerObjectsOnce, registerCoreTextObjects);
    return lineTypeID;
}

static CFRange clippedStringRange(CFRange range, CFIndex start, CFIndex end)
{
    if (start < 0 || end < start || range.location < 0 ||
        range.length <= 0 || range.location > end)
        return CFRangeMake(start, 0);
    CFIndex limit = range.length > end - range.location
            ? end : range.location + range.length;
    CFIndex location = MAX(start, range.location);
    return CFRangeMake(location, limit > location ? limit - location : 0);
}

CTLineRef KTCoreTextCreateLineWithRange(CFAttributedStringRef attrString, CFRange stringRange)
{
    if (attrString == NULL || stringRange.location < 0 || stringRange.length < 0)
        return NULL;
    CFIndex total = CFAttributedStringGetLength(attrString);
    if (stringRange.location > total || stringRange.length > total - stringRange.location)
        return NULL;

    CFAttributedStringRef copy = CFAttributedStringCreateCopy(
            kCFAllocatorDefault, attrString);
    if (copy == NULL)
        return NULL;
    CFMutableArrayRef runs = CFArrayCreateMutable(
            kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
    if (runs == NULL) {
        CFRelease(copy);
        return NULL;
    }
    CFIndex length = stringRange.location + stringRange.length;
    CFIndex cursor = stringRange.location;
    CGFloat width = 0;
    CGFloat ascent = 0;
    CGFloat descent = 0;
    CGFloat leading = 0;

    while (cursor < length) {
        CFRange range;
        CFAttributedStringGetAttributes(copy, cursor, &range);
        range = clippedStringRange(range, cursor, length);
        if (range.length <= 0)
            goto failed;

        CFDictionaryRef attributes = CFAttributedStringGetAttributes(
                copy, range.location, NULL);
        CTFontRef font = fontForAttributes(attributes);
        if (rangeNeedsClusterRuns(copy, range, font)) {
            CFStringRef string = CFAttributedStringGetString(copy);
            CFIndex rangeEnd = range.location + range.length;
            CFIndex clusterCursor = range.location;
            while (clusterCursor < rangeEnd) {
                CFRange cluster = CFStringGetRangeOfComposedCharactersAtIndex(
                        string, clusterCursor);
                cluster = clippedStringRange(cluster, clusterCursor, rangeEnd);
                if (cluster.length <= 0)
                    goto failed;
                if (!appendRun(runs, createClusterRun(copy, attributes, cluster,
                                                  font, &width),
                          &ascent, &descent, &leading))
                    goto failed;
                clusterCursor = cluster.location + cluster.length;
            }
        } else {
            if (!appendRun(runs, createRun(copy, range, &width), &ascent,
                      &descent, &leading))
                goto failed;
        }
        cursor = range.location + range.length;
    }

    CFMutableDictionaryRef line = CFDictionaryCreateMutable(
            kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks,
            &kCFTypeDictionaryValueCallBacks);
    if (line == NULL)
        goto failed;
    CFDictionarySetValue(line, KTLineAttributedStringKey, copy);
    CFDictionarySetValue(line, KTLineRunsKey, runs);
    KTCoreTextDictionarySetIndex(line, KTLineRangeLocationKey, stringRange.location);
    KTCoreTextDictionarySetIndex(line, KTLineRangeLengthKey, stringRange.length);
    KTCoreTextDictionarySetFloat(line, KTLineWidthKey, width);
    KTCoreTextDictionarySetFloat(line, KTLineAscentKey, ascent);
    KTCoreTextDictionarySetFloat(line, KTLineDescentKey, descent);
    KTCoreTextDictionarySetFloat(line, KTLineLeadingKey, leading);
    CFRelease(copy);
    CFRelease(runs);
    CTLineRef result = (CTLineRef)createCoreTextObject(CTLineGetTypeID(), line);
    CFRelease(line);
    return result;

failed:
    CFRelease(copy);
    CFRelease(runs);
    return NULL;
}

CTLineRef CTLineCreateWithAttributedString(CFAttributedStringRef attrString)
{
    if (attrString == NULL)
        return NULL;
    return KTCoreTextCreateLineWithRange(attrString,
            CFRangeMake(0, CFAttributedStringGetLength(attrString)));
}

CTLineRef CTLineCreateTruncatedLine(CTLineRef line, double width,
                                    CTLineTruncationType truncationType,
                                    CTLineRef truncationToken)
{
    // Preserve the unimplemented result rather than pretending to truncate.
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return NULL;
}

CTLineRef CTLineCreateJustifiedLine(CTLineRef line,
                                    CGFloat justificationFactor,
                                    double justificationWidth)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return NULL;
}

CFIndex CTLineGetGlyphCount(CTLineRef line)
{
    if (line == NULL)
        return 0;
    CFArrayRef runs = CFDictionaryGetValue(KTCoreTextObjectDictionary(line),
                                           KTLineRunsKey);
    CFIndex count = 0;
    for (CFIndex index = 0; index < CFArrayGetCount(runs); ++index)
        count += CTRunGetGlyphCount((CTRunRef)CFArrayGetValueAtIndex(
                runs, index));
    return count;
}

CFArrayRef CTLineGetGlyphRuns(CTLineRef line)
{
    if (line == NULL)
        return NULL;
    return CFDictionaryGetValue(KTCoreTextObjectDictionary(line), KTLineRunsKey);
}

CFRange CTLineGetStringRange(CTLineRef line)
{
    if (line == NULL)
        return CFRangeMake(kCFNotFound, 0);
    CFDictionaryRef dictionary = KTCoreTextObjectDictionary(line);
    return CFRangeMake(KTCoreTextDictionaryGetIndex(dictionary, KTLineRangeLocationKey),
            KTCoreTextDictionaryGetIndex(dictionary, KTLineRangeLengthKey));
}

double CTLineGetPenOffsetForFlush(CTLineRef line, CGFloat flushFactor,
                                  double flushWidth)
{
    if (line == NULL)
        return 0;
    CGFloat width = KTCoreTextDictionaryGetFloat(KTCoreTextObjectDictionary(line),
                                                  KTLineWidthKey);
    return (flushWidth - width) * flushFactor;
}

void CTLineDraw(CTLineRef line, CGContextRef context)
{
    if (line == NULL || context == NULL)
        return;
    CFArrayRef runs = CTLineGetGlyphRuns(line);
    CGPoint origin = CGContextGetTextPosition(context);
    for (CFIndex index = 0; index < CFArrayGetCount(runs); ++index) {
        CGContextSetTextPosition(context, origin.x, origin.y);
        CTRunDraw((CTRunRef)CFArrayGetValueAtIndex(runs, index), context,
                  CFRangeMake(0, 0));
    }
}

double CTLineGetTypographicBounds(CTLineRef line, CGFloat *ascent,
                                  CGFloat *descent, CGFloat *leading)
{
    if (line == NULL)
        return 0;
    CFDictionaryRef dictionary = KTCoreTextObjectDictionary(line);
    if (ascent != NULL)
        *ascent = KTCoreTextDictionaryGetFloat(dictionary, KTLineAscentKey);
    if (descent != NULL)
        *descent = KTCoreTextDictionaryGetFloat(dictionary, KTLineDescentKey);
    if (leading != NULL)
        *leading = KTCoreTextDictionaryGetFloat(dictionary, KTLineLeadingKey);
    return KTCoreTextDictionaryGetFloat(dictionary, KTLineWidthKey);
}

CGRect CTLineGetBoundsWithOptions(CTLineRef line, CTLineBoundsOptions options)
{
    CGFloat ascent = 0;
    CGFloat descent = 0;
    CGFloat leading = 0;
    CGFloat width = CTLineGetTypographicBounds(line, &ascent, &descent,
                                                &leading);
    return CGRectMake(0, -descent, width, ascent + descent + leading);
}

double CTLineGetTrailingWhitespaceWidth(CTLineRef line)
{
    return 0;
}

CGRect CTLineGetImageBounds(CTLineRef line, CGContextRef context)
{
    return CTLineGetBoundsWithOptions(line, 0);
}

CFIndex CTLineGetStringIndexForPosition(CTLineRef line, CGPoint position)
{
    if (line == NULL)
        return kCFNotFound;
    CFArrayRef runs = CTLineGetGlyphRuns(line);
    for (CFIndex runIndex = 0; runIndex < CFArrayGetCount(runs); ++runIndex) {
        CTRunRef run = (CTRunRef)CFArrayGetValueAtIndex(runs, runIndex);
        const CGPoint *positions = CTRunGetPositionsPtr(run);
        const CGSize *advances = CTRunGetAdvancesPtr(run);
        const CFIndex *indices = CTRunGetStringIndicesPtr(run);
        CFIndex count = CTRunGetGlyphCount(run);
        for (CFIndex index = 0; index < count; ++index) {
            if (position.x < positions[index].x + advances[index].width / 2)
                return indices[index];
        }
    }
    CFRange range = CTLineGetStringRange(line);
    return range.location + range.length;
}

CGFloat CTLineGetOffsetForStringIndex(CTLineRef line, CFIndex charIndex,
                                      CGFloat *secondaryOffset)
{
    if (secondaryOffset != NULL)
        *secondaryOffset = 0;
    if (line == NULL)
        return 0;
    CFArrayRef runs = CTLineGetGlyphRuns(line);
    for (CFIndex runIndex = 0; runIndex < CFArrayGetCount(runs); ++runIndex) {
        CTRunRef run = (CTRunRef)CFArrayGetValueAtIndex(runs, runIndex);
        const CGPoint *positions = CTRunGetPositionsPtr(run);
        const CFIndex *indices = CTRunGetStringIndicesPtr(run);
        CFIndex count = CTRunGetGlyphCount(run);
        for (CFIndex index = 0; index < count; ++index) {
            if (indices[index] >= charIndex)
                return positions[index].x;
        }
    }
    return KTCoreTextDictionaryGetFloat(KTCoreTextObjectDictionary(line),
                                         KTLineWidthKey);
}
