#import <CoreText/CTTypesetter.h>
#import <CoreText/CTLine.h>
#import "KTCoreTextInternal.h"
#import <Foundation/NSAttributedString.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSException.h>
#include <unicode/ubrk.h>
#include <math.h>
#include <stdlib.h>
#include <limits.h>

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
    if (stringRange.location < 0 || stringRange.length < 0 ||
        stringRange.location > totalLen || stringRange.length > totalLen - stringRange.location)
        return NULL;
    if (stringRange.length == 0)
        stringRange.length = totalLen - stringRange.location;
    return KTCoreTextCreateLineWithRange(ts->_string, stringRange);
}

CTLineRef CTTypesetterCreateLineWithOffset(CTTypesetterRef typesetter, CFRange stringRange, double offset) {
    return CTTypesetterCreateLine(typesetter, stringRange);
}

static CFIndex suggestBreak(_CTTypesetter *typesetter, CFIndex start, double width, UBreakIteratorType kind) {
    if (!typesetter || !typesetter->_string || start < 0 || !(width > 0)) return 0;
    CFStringRef string = CFAttributedStringGetString(typesetter->_string);
    CFIndex length = CFStringGetLength(string);
    if (start >= length) return 0;
    if (length > INT32_MAX) {
        [NSException raise:NSInvalidArgumentException format:@"Typesetter string exceeds ICU index range"];
    }
    UniChar *characters = malloc(length * sizeof(*characters));
    if (!characters) [NSException raise:NSMallocException format:@"Cannot allocate typesetter characters"];
    CFStringGetCharacters(string, CFRangeMake(0, length), characters);
    UErrorCode status = U_ZERO_ERROR;
    UBreakIterator *iterator = ubrk_open(kind, NULL, characters, length, &status);
    if (U_FAILURE(status) || !iterator) {
        free(characters);
        [NSException raise:NSInternalInconsistencyException format:@"ICU typesetter boundary analysis failed: %d", status];
    }
    CFIndex fit = 0;
    for (int32_t end = ubrk_following(iterator, start); end != UBRK_DONE; end = ubrk_next(iterator)) {
        CTLineRef line = CTTypesetterCreateLine((CTTypesetterRef)typesetter, CFRangeMake(start, end - start));
        if (!line) {
            ubrk_close(iterator); free(characters);
            [NSException raise:NSInternalInconsistencyException format:@"Cannot measure typesetter line"];
        }
        double advance = CTLineGetTypographicBounds(line, NULL, NULL, NULL);
        CFRelease(line);
        if (advance > width) break;
        fit = end - start;
        if (kind == UBRK_LINE && ubrk_getRuleStatus(iterator) >= UBRK_LINE_HARD) break;
    }
    ubrk_close(iterator);
    free(characters);
    return fit;
}

CFIndex CTTypesetterSuggestLineBreak(CTTypesetterRef typesetter, CFIndex startIndex, double width) {
    CFIndex fit = suggestBreak((_CTTypesetter *)typesetter, startIndex, width, UBRK_LINE);
    return fit ? fit : suggestBreak((_CTTypesetter *)typesetter, startIndex, width, UBRK_CHARACTER);
}

CFIndex CTTypesetterSuggestLineBreakWithOffset(CTTypesetterRef typesetter, CFIndex startIndex, double width, double offset) {
    return CTTypesetterSuggestLineBreak(typesetter, startIndex, width);
}

CFIndex CTTypesetterSuggestClusterBreak(CTTypesetterRef typesetter, CFIndex startIndex, double width) {
    return suggestBreak((_CTTypesetter *)typesetter, startIndex, width, UBRK_CHARACTER);
}

CFIndex CTTypesetterSuggestClusterBreakWithOffset(CTTypesetterRef typesetter, CFIndex startIndex, double width, double offset) {
    return CTTypesetterSuggestClusterBreak(typesetter, startIndex, width);
}

// In Cocotron/Darling, CFTypeID for bridged/pseudo-CF classes
// is identified by the Objective-C Class pointer convention.
CFTypeID CTTypesetterGetTypeID(void) {
    return (CFTypeID)[_CTTypesetter self];
}
