#import <CoreText/CTFrameSetter.h>
#import <CoreText/CTFrame.h>
#import "KTFrameInternal.h"
#include <CoreFoundation/CFRuntime.h>
#include <pthread.h>
#include <math.h>

static const CFStringRef typesetterKey = CFSTR("KTFramesetterTypesetter");
static const CFStringRef lengthKey = CFSTR("KTFramesetterLength");
static CFTypeID framesetterType;
static pthread_once_t registerOnce = PTHREAD_ONCE_INIT;
static const CFRuntimeClass framesetterClass = {
    0, "CTFramesetter", NULL, NULL, KTCoreTextFinalizeObject, NULL, NULL, NULL, NULL,
};
static void registerFramesetter(void) { framesetterType = _CFRuntimeRegisterClass(&framesetterClass); }
CFTypeID CTFramesetterGetTypeID(void) {
    pthread_once(&registerOnce, registerFramesetter);
    return framesetterType;
}

CTFramesetterRef CTFramesetterCreateWithTypesetter(CTTypesetterRef typesetter) {
    if (!typesetter) return NULL;
    CTLineRef whole = CTTypesetterCreateLine(typesetter, CFRangeMake(0, 0));
    if (!whole) return NULL;
    CFIndex length = CTLineGetStringRange(whole).length;
    CFRelease(whole);
    CFMutableDictionaryRef storage = CFDictionaryCreateMutable(NULL, 0,
            &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    if (!storage) return NULL;
    CFDictionarySetValue(storage, typesetterKey, typesetter);
    KTCoreTextDictionarySetIndex(storage, lengthKey, length);
    CTFramesetterRef result = (CTFramesetterRef)KTCoreTextCreateObject(CTFramesetterGetTypeID(), storage);
    CFRelease(storage);
    return result;
}

CTFramesetterRef CTFramesetterCreateWithAttributedString(CFAttributedStringRef string) {
    if (!string) return NULL;
    CFAttributedStringRef copy = CFAttributedStringCreateCopy(NULL, string);
    if (!copy) return NULL;
    CTTypesetterRef typesetter = CTTypesetterCreateWithAttributedString(copy);
    CFRelease(copy);
    if (!typesetter) return NULL;
    CTFramesetterRef result = CTFramesetterCreateWithTypesetter(typesetter);
    CFRelease(typesetter);
    return result;
}

CTTypesetterRef CTFramesetterGetTypesetter(CTFramesetterRef framesetter) {
    return framesetter ? (CTTypesetterRef)CFDictionaryGetValue(KTCoreTextObjectDictionary(framesetter), typesetterKey) : NULL;
}

static bool normalizeRange(CTFramesetterRef framesetter, CFRange *range) {
    if (!framesetter || range->location < 0 || range->length < 0) return false;
    CFIndex length = KTCoreTextDictionaryGetIndex(KTCoreTextObjectDictionary(framesetter), lengthKey);
    if (range->location > length || range->length > length - range->location) return false;
    if (!range->length) range->length = length - range->location;
    return true;
}

static CGSize layout(CTFramesetterRef framesetter, CFRange range, CGSize constraints,
                      CFMutableArrayRef lines, CFMutableDataRef origins, CFRange *fit, bool *valid) {
    *valid = true;
    CFIndex cursor = range.location, end = range.location + range.length;
    CGFloat usedHeight = 0, usedWidth = 0;
    CTTypesetterRef typesetter = CTFramesetterGetTypesetter(framesetter);
    while (cursor < end && constraints.width > 0 && constraints.height > 0) {
        CFIndex count = CTTypesetterSuggestLineBreak(typesetter, cursor, constraints.width);
        count = MIN(count, end - cursor);
        if (count <= 0) break;
        CTLineRef line = CTTypesetterCreateLine(typesetter, CFRangeMake(cursor, count));
        if (!line) { *valid = false; return CGSizeZero; }
        CGFloat ascent, descent, leading;
        CGFloat width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading);
        CGFloat height = ascent + descent + leading;
        if (!isfinite(width) || !isfinite(height) || height <= 0) {
            CFRelease(line); *valid = false; return CGSizeZero;
        }
        if (height > constraints.height - usedHeight) {
            CFRelease(line);
            break;
        }
        CGPoint origin = CGPointMake(0, constraints.height - usedHeight - ascent);
        if (lines) CFArrayAppendValue(lines, line);
        if (origins) CFDataAppendBytes(origins, (const UInt8 *)&origin, sizeof(origin));
        CFRelease(line);
        usedWidth = MAX(usedWidth, width);
        usedHeight += height;
        cursor += count;
    }
    if (fit) *fit = CFRangeMake(range.location, cursor - range.location);
    return CGSizeMake(usedWidth, usedHeight);
}

CTFrameRef CTFramesetterCreateFrame(CTFramesetterRef framesetter, CFRange range,
                                     CGPathRef path, CFDictionaryRef attributes) {
    CGRect bounds;
    if (!normalizeRange(framesetter, &range) || !path || !CGPathIsRect(path, &bounds) ||
        (attributes && CFDictionaryGetCount(attributes))) return NULL;
    if (!isfinite(bounds.origin.x) || !isfinite(bounds.origin.y) ||
        !isfinite(bounds.size.width) || !isfinite(bounds.size.height) ||
        bounds.size.width < 0 || bounds.size.height < 0) return NULL;
    CFMutableArrayRef lines = CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks);
    CFMutableDataRef origins = CFDataCreateMutable(NULL, 0);
    CFMutableDictionaryRef storage = CFDictionaryCreateMutable(NULL, 0,
            &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CGPathRef pathCopy = CGPathCreateCopy(path);
    CFDictionaryRef attributesCopy = attributes ? CFDictionaryCreateCopy(NULL, attributes) : NULL;
    CFDataRef requestedData = CFDataCreate(NULL, (const UInt8 *)&range, sizeof(range));
    CFDataRef visibleData = NULL;
    CTFrameRef frame = NULL;
    if (!lines || !origins || !storage || !pathCopy || !requestedData ||
        (attributes && !attributesCopy)) goto cleanup;
    CFRange visible;
    bool valid;
    layout(framesetter, range, bounds.size, lines, origins, &visible, &valid);
    if (!valid) goto cleanup;
    visibleData = CFDataCreate(NULL, (const UInt8 *)&visible, sizeof(visible));
    if (!visibleData) goto cleanup;
    CFDictionarySetValue(storage, KTFrameLinesKey, lines);
    CFDictionarySetValue(storage, KTFrameOriginsKey, origins);
    CFDictionarySetValue(storage, KTFramePathKey, pathCopy);
    if (attributesCopy) CFDictionarySetValue(storage, KTFrameAttributesKey, attributesCopy);
    CFDictionarySetValue(storage, KTFrameStringRangeKey, requestedData);
    CFDictionarySetValue(storage, KTFrameVisibleRangeKey, visibleData);
    frame = (CTFrameRef)KTCoreTextCreateObject(CTFrameGetTypeID(), storage);
cleanup:
    if (visibleData) CFRelease(visibleData);
    if (requestedData) CFRelease(requestedData);
    if (attributesCopy) CFRelease(attributesCopy);
    if (pathCopy) CGPathRelease(pathCopy);
    if (storage) CFRelease(storage);
    if (lines) CFRelease(lines);
    if (origins) CFRelease(origins);
    return frame;
}

CGSize CTFramesetterSuggestFrameSizeWithConstraints(CTFramesetterRef framesetter,
        CFRange range, CFDictionaryRef attributes, CGSize constraints, CFRange *fit) {
    if (!normalizeRange(framesetter, &range) || (attributes && CFDictionaryGetCount(attributes)) ||
        !isfinite(constraints.width) || !isfinite(constraints.height) ||
        constraints.width < 0 || constraints.height < 0) {
        if (fit) *fit = CFRangeMake(0, 0);
        return CGSizeZero;
    }
    bool valid;
    CGSize size = layout(framesetter, range, constraints, NULL, NULL, fit, &valid);
    if (!valid && fit) *fit = CFRangeMake(0, 0);
    return size;
}
