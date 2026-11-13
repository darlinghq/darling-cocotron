#import <CoreFoundation/CoreFoundation.h>
#import <CoreText/CoreTextExport.h>
#import <CoreText/CTLine.h>

CF_IMPLICIT_BRIDGING_ENABLED

typedef struct __CTTypesetter* CTTypesetterRef;

CORETEXT_EXPORT CFTypeID CTTypesetterGetTypeID(void);

CORETEXT_EXPORT CTTypesetterRef CTTypesetterCreateWithAttributedString(CFAttributedStringRef string);
CORETEXT_EXPORT CTTypesetterRef CTTypesetterCreateWithAttributedStringAndOptions(CFAttributedStringRef string, CFDictionaryRef options);

CORETEXT_EXPORT CTLineRef CTTypesetterCreateLine(CTTypesetterRef typesetter, CFRange stringRange);
CORETEXT_EXPORT CTLineRef CTTypesetterCreateLineWithOffset(CTTypesetterRef typesetter, CFRange stringRange, double offset);

CORETEXT_EXPORT CFIndex CTTypesetterSuggestLineBreak(CTTypesetterRef typesetter, CFIndex startIndex, double width);
CORETEXT_EXPORT CFIndex CTTypesetterSuggestLineBreakWithOffset(CTTypesetterRef typesetter, CFIndex startIndex, double width, double offset);
CORETEXT_EXPORT CFIndex CTTypesetterSuggestClusterBreak(CTTypesetterRef typesetter, CFIndex startIndex, double width);
CORETEXT_EXPORT CFIndex CTTypesetterSuggestClusterBreakWithOffset(CTTypesetterRef typesetter, CFIndex startIndex, double width, double offset);

CF_IMPLICIT_BRIDGING_DISABLED
