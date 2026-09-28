#import <CoreText/CTFont.h>
#import <CoreText/CTLine.h>
#import <CoreText/CTRun.h>

CFTypeID KTCoreTextRunGetTypeID(void);
CFDictionaryRef KTCoreTextObjectDictionary(CFTypeRef object);

extern const CFStringRef kCTFontAttributeName;

extern const CFStringRef KTLineAttributedStringKey;
extern const CFStringRef KTLineRunsKey;
extern const CFStringRef KTLineWidthKey;
extern const CFStringRef KTLineAscentKey;
extern const CFStringRef KTLineDescentKey;
extern const CFStringRef KTLineLeadingKey;

extern const CFStringRef KTRunAttributesKey;
extern const CFStringRef KTRunGlyphsKey;
extern const CFStringRef KTRunPositionsKey;
extern const CFStringRef KTRunAdvancesKey;
extern const CFStringRef KTRunIndicesKey;
extern const CFStringRef KTRunRangeLocationKey;
extern const CFStringRef KTRunRangeLengthKey;
extern const CFStringRef KTRunGlyphCountKey;
extern const CFStringRef KTRunWidthKey;
extern const CFStringRef KTRunAscentKey;
extern const CFStringRef KTRunDescentKey;
extern const CFStringRef KTRunLeadingKey;

CFIndex KTCoreTextDictionaryGetIndex(CFDictionaryRef dictionary,
                                    CFStringRef key);
CGFloat KTCoreTextDictionaryGetFloat(CFDictionaryRef dictionary,
                                     CFStringRef key);
void KTCoreTextDictionarySetIndex(CFMutableDictionaryRef dictionary,
                                  CFStringRef key, CFIndex value);
void KTCoreTextDictionarySetFloat(CFMutableDictionaryRef dictionary,
                                  CFStringRef key, CGFloat value);
