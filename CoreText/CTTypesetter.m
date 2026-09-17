#import <CoreText/CTTypesetter.h>
#import <CoreText/CTLine.h>
#import <Foundation/NSAttributedString.h>
#import <Foundation/NSDictionary.h>

@interface _CTTypesetter : NSObject {
@public
    CFAttributedStringRef _string;
    CFDictionaryRef _options;
}
@end

@implementation _CTTypesetter
- (void)dealloc {
    if (_string) CFRelease(_string);
    if (_options) CFRelease(_options);
    [super dealloc];
}
@end

CTTypesetterRef CTTypesetterCreateWithAttributedString(CFAttributedStringRef string) {
    return CTTypesetterCreateWithAttributedStringAndOptions(string, NULL);
}

CTTypesetterRef CTTypesetterCreateWithAttributedStringAndOptions(CFAttributedStringRef string, CFDictionaryRef options) {
    _CTTypesetter *ts = [[_CTTypesetter alloc] init];
    if (string) ts->_string = CFRetain(string);
    if (options) ts->_options = CFRetain(options);
    return (CTTypesetterRef)ts;
}

CTLineRef CTTypesetterCreateLine(CTTypesetterRef typesetter, CFRange stringRange) {
    _CTTypesetter *ts = (_CTTypesetter *)typesetter;
    if (!ts || !ts->_string) {
        return NULL;
    }
    CFIndex totalLen = CFAttributedStringGetLength(ts->_string);
    // If an explicit valid subrange is requested, create the line from that range
    if (stringRange.location >= 0 && stringRange.length > 0 &&
        stringRange.length <= totalLen - stringRange.location) {
        CFAttributedStringRef sub = CFAttributedStringCreateWithSubstring(NULL, ts->_string, stringRange);
        if (sub) {
            CTLineRef line = CTLineCreateWithAttributedString(sub);
            CFRelease(sub);
            return line;
        }
    }
    // TODO: When stringRange.length == 0, Apple typesetter dynamically breaks line according
    // to layout constraints and available width. Fall back to the whole string for now.
    return CTLineCreateWithAttributedString(ts->_string);
}

CTLineRef CTTypesetterCreateLineWithOffset(CTTypesetterRef typesetter, CFRange stringRange, double offset) {
    return CTTypesetterCreateLine(typesetter, stringRange);
}

// TODO: Implement full Unicode line-break analysis and glyph advance width calculation.
// Currently returns the remaining character length as a greedy fallback.
CFIndex CTTypesetterSuggestLineBreak(CTTypesetterRef typesetter, CFIndex startIndex, double width) {
    _CTTypesetter *ts = (_CTTypesetter *)typesetter;
    if (!ts || !ts->_string) return 0;
    CFIndex total = CFAttributedStringGetLength(ts->_string);
    if (startIndex >= total) return 0;
    return total - startIndex;
}

CFIndex CTTypesetterSuggestLineBreakWithOffset(CTTypesetterRef typesetter, CFIndex startIndex, double width, double offset) {
    return CTTypesetterSuggestLineBreak(typesetter, startIndex, width);
}

CFIndex CTTypesetterSuggestClusterBreak(CTTypesetterRef typesetter, CFIndex startIndex, double width) {
    return CTTypesetterSuggestLineBreak(typesetter, startIndex, width);
}

CFIndex CTTypesetterSuggestClusterBreakWithOffset(CTTypesetterRef typesetter, CFIndex startIndex, double width, double offset) {
    return CTTypesetterSuggestLineBreak(typesetter, startIndex, width);
}

// In Cocotron/Darling, CFTypeID for bridged/pseudo-CF classes
// is identified by the Objective-C Class pointer convention.
CFTypeID CTTypesetterGetTypeID(void) {
    return (CFTypeID)[_CTTypesetter self];
}
