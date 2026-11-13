#import <CoreText/CTFrame.h>
#import "KTFrameInternal.h"
#include <CoreFoundation/CFRuntime.h>
#include <pthread.h>
#include <string.h>

const CFStringRef KTFrameLinesKey = CFSTR("KTFrameLines");
const CFStringRef KTFrameOriginsKey = CFSTR("KTFrameOrigins");
const CFStringRef KTFramePathKey = CFSTR("KTFramePath");
const CFStringRef KTFrameAttributesKey = CFSTR("KTFrameAttributes");
const CFStringRef KTFrameStringRangeKey = CFSTR("KTFrameStringRange");
const CFStringRef KTFrameVisibleRangeKey = CFSTR("KTFrameVisibleRange");
static CFTypeID frameType;
static pthread_once_t registerOnce = PTHREAD_ONCE_INIT;
static const CFRuntimeClass frameClass = {
    0, "CTFrame", NULL, NULL, KTCoreTextFinalizeObject, NULL, NULL, NULL, NULL,
};
static void registerFrame(void) { frameType = _CFRuntimeRegisterClass(&frameClass); }
CFTypeID CTFrameGetTypeID(void) {
    pthread_once(&registerOnce, registerFrame);
    return frameType;
}
static CFRange storedRange(CTFrameRef frame, CFStringRef key) {
    CFRange range = CFRangeMake(0, 0);
    if (frame) {
        CFDataRef data = CFDictionaryGetValue(KTCoreTextObjectDictionary(frame), key);
        memcpy(&range, CFDataGetBytePtr(data), sizeof(range));
    }
    return range;
}
CFRange CTFrameGetStringRange(CTFrameRef frame) { return storedRange(frame, KTFrameStringRangeKey); }
CFRange CTFrameGetVisibleStringRange(CTFrameRef frame) { return storedRange(frame, KTFrameVisibleRangeKey); }
CGPathRef CTFrameGetPath(CTFrameRef frame) {
    return frame ? (CGPathRef)CFDictionaryGetValue(KTCoreTextObjectDictionary(frame), KTFramePathKey) : NULL;
}
CFDictionaryRef CTFrameGetFrameAttributes(CTFrameRef frame) {
    return frame ? (CFDictionaryRef)CFDictionaryGetValue(KTCoreTextObjectDictionary(frame), KTFrameAttributesKey) : NULL;
}
CFArrayRef CTFrameGetLines(CTFrameRef frame) {
    return frame ? (CFArrayRef)CFDictionaryGetValue(KTCoreTextObjectDictionary(frame), KTFrameLinesKey) : NULL;
}
void CTFrameGetLineOrigins(CTFrameRef frame, CFRange range, CGPoint origins[]) {
    if (!frame || !origins) return;
    CFIndex count = CFArrayGetCount(CTFrameGetLines(frame));
    if (range.location < 0 || range.length < 0 || range.location > count || range.length > count - range.location) return;
    if (!range.length) range.length = count - range.location;
    CFDataRef data = CFDictionaryGetValue(KTCoreTextObjectDictionary(frame), KTFrameOriginsKey);
    memcpy(origins, CFDataGetBytePtr(data) + range.location * sizeof(CGPoint), range.length * sizeof(CGPoint));
}
void CTFrameDraw(CTFrameRef frame, CGContextRef context) {
    if (!frame || !context) return;
    CFArrayRef lines = CTFrameGetLines(frame);
    CFDataRef data = CFDictionaryGetValue(KTCoreTextObjectDictionary(frame), KTFrameOriginsKey);
    CGRect bounds;
    CGPathIsRect(CTFrameGetPath(frame), &bounds);
    CGContextSaveGState(context);
    CGContextClipToRect(context, bounds);
    for (CFIndex index = 0; index < CFArrayGetCount(lines); ++index) {
        CGPoint origin;
        memcpy(&origin, CFDataGetBytePtr(data) + index * sizeof(origin), sizeof(origin));
        CGContextSetTextPosition(context, bounds.origin.x + origin.x, bounds.origin.y + origin.y);
        CTLineDraw((CTLineRef)CFArrayGetValueAtIndex(lines, index), context);
    }
    CGContextRestoreGState(context);
}
