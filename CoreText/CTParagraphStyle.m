#import <CoreText/CTParagraphStyle.h>
#import <CoreText/CTTextTab.h>
#import <CoreText/CTLine.h>
#include <CoreFoundation/CFArray.h>
#include <CoreFoundation/CFRuntime.h>
#include <pthread.h>
#include <string.h>
#include <math.h>

union ParagraphValue {
    CGFloat number;
    CTTextAlignment alignment;
    CTLineBreakMode breakMode;
    CTWritingDirection direction;
    CTLineBoundsOptions bounds;
};

struct __CTParagraphStyle {
    CFRuntimeBase base;
    union ParagraphValue values[kCTParagraphStyleSpecifierCount];
    CFArrayRef tabs;
};

static void finalizeParagraph(CFTypeRef value) {
    CTParagraphStyleRef style = value;
    if (style->tabs != NULL) CFRelease(style->tabs);
}

static const CFRuntimeClass paragraphClass = {
    0, "CTParagraphStyle", NULL, NULL, finalizeParagraph, NULL, NULL, NULL, NULL,
};
static CFTypeID paragraphType;
static pthread_once_t registerParagraphOnce = PTHREAD_ONCE_INIT;

static void registerParagraph(void) { paragraphType = _CFRuntimeRegisterClass(&paragraphClass); }
CFTypeID CTParagraphStyleGetTypeID(void) {
    pthread_once(&registerParagraphOnce, registerParagraph);
    return paragraphType;
}

static size_t valueSize(CTParagraphStyleSpecifier spec) {
    switch (spec) {
    case kCTParagraphStyleSpecifierAlignment: return sizeof(CTTextAlignment);
    case kCTParagraphStyleSpecifierLineBreakMode: return sizeof(CTLineBreakMode);
    case kCTParagraphStyleSpecifierBaseWritingDirection: return sizeof(CTWritingDirection);
    case kCTParagraphStyleSpecifierTabStops: return sizeof(CFArrayRef);
    case kCTParagraphStyleSpecifierLineBoundsOptions: return sizeof(CTLineBoundsOptions);
    default: return sizeof(CGFloat);
    }
}

static bool supported(CTParagraphStyleSpecifier spec) {
    return spec <= kCTParagraphStyleSpecifierBaseWritingDirection ||
           spec == kCTParagraphStyleSpecifierLineBoundsOptions;
}

static CFArrayRef defaultTabs(void) {
    CTTextTabRef tabs[12];
    size_t count = 0;
    for (; count < 12; ++count) {
        tabs[count] = CTTextTabCreate(kCTTextAlignmentLeft, (count + 1) * 28.0, NULL);
        if (tabs[count] == NULL) break;
    }
    CFArrayRef result = count == 12 ? CFArrayCreate(kCFAllocatorDefault,
            (const void **)tabs, 12, &kCFTypeArrayCallBacks) : NULL;
    for (size_t index = 0; index < count; ++index) CFRelease(tabs[index]);
    return result;
}

CTParagraphStyleRef CTParagraphStyleCreate(const CTParagraphStyleSetting *settings, size_t settingCount) {
    if (settings == NULL && settingCount != 0) return NULL;
    union ParagraphValue values[kCTParagraphStyleSpecifierCount] = {0};
    bool seen[kCTParagraphStyleSpecifierCount] = {0};
    values[kCTParagraphStyleSpecifierAlignment].alignment = kCTTextAlignmentNatural;
    values[kCTParagraphStyleSpecifierBaseWritingDirection].direction = kCTWritingDirectionNatural;
    CFArrayRef tabs = NULL;
    for (size_t index = 0; index < settingCount; ++index) {
        CTParagraphStyleSpecifier spec = settings[index].spec;
        if (spec >= kCTParagraphStyleSpecifierCount) continue;
        if (!supported(spec) || seen[spec] || settings[index].value == NULL ||
            settings[index].valueSize != valueSize(spec)) goto invalid;
        seen[spec] = true;
        if (spec == kCTParagraphStyleSpecifierTabStops) {
            CFArrayRef input;
            memcpy(&input, settings[index].value, sizeof(input));
            if (input == NULL || CFGetTypeID(input) != CFArrayGetTypeID()) goto invalid;
            for (CFIndex i = 0; i < CFArrayGetCount(input); ++i) {
                CFTypeRef tab = CFArrayGetValueAtIndex(input, i);
                if (tab == NULL || CFGetTypeID(tab) != CTTextTabGetTypeID()) goto invalid;
                if (i && CTTextTabGetLocation(tab) < CTTextTabGetLocation(CFArrayGetValueAtIndex(input, i - 1))) goto invalid;
            }
            CFMutableArrayRef owned = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
            if (owned == NULL) goto invalid;
            for (CFIndex i = 0; i < CFArrayGetCount(input); ++i)
                CFArrayAppendValue(owned, CFArrayGetValueAtIndex(input, i));
            tabs = CFArrayCreateCopy(kCFAllocatorDefault, owned);
            CFRelease(owned);
            if (tabs == NULL) goto invalid;
        } else {
            memcpy(&values[spec], settings[index].value, valueSize(spec));
            if (spec == kCTParagraphStyleSpecifierAlignment) {
                if (values[spec].alignment > kCTTextAlignmentNatural) goto invalid;
            } else if (spec == kCTParagraphStyleSpecifierLineBreakMode) {
                if (values[spec].breakMode > kCTLineBreakByTruncatingMiddle) goto invalid;
            } else if (spec == kCTParagraphStyleSpecifierBaseWritingDirection) {
                if (values[spec].direction < kCTWritingDirectionNatural || values[spec].direction > kCTWritingDirectionRightToLeft) goto invalid;
            } else if (spec != kCTParagraphStyleSpecifierLineBoundsOptions) {
                if (!isfinite(values[spec].number)) goto invalid;
                if ((spec == kCTParagraphStyleSpecifierFirstLineHeadIndent ||
                     spec == kCTParagraphStyleSpecifierHeadIndent ||
                     spec == kCTParagraphStyleSpecifierMaximumLineHeight ||
                     spec == kCTParagraphStyleSpecifierMinimumLineHeight ||
                     spec == kCTParagraphStyleSpecifierLineSpacing ||
                     spec == kCTParagraphStyleSpecifierParagraphSpacing) && values[spec].number < 0) goto invalid;
            }
        }
    }
    if (tabs == NULL) tabs = defaultTabs();
    if (tabs == NULL) return NULL;
    struct __CTParagraphStyle *style = (struct __CTParagraphStyle *)_CFRuntimeCreateInstance(
            kCFAllocatorDefault, CTParagraphStyleGetTypeID(), sizeof(*style) - sizeof(CFRuntimeBase), NULL);
    if (style == NULL) goto invalid;
    memcpy(style->values, values, sizeof(values));
    style->tabs = tabs;
    return style;
invalid:
    if (tabs != NULL) CFRelease(tabs);
    return NULL;
}

CTParagraphStyleRef CTParagraphStyleCreateCopy(CTParagraphStyleRef style) {
    return style && CFGetTypeID(style) == CTParagraphStyleGetTypeID() ? CFRetain(style) : NULL;
}

bool CTParagraphStyleGetValueForSpecifier(CTParagraphStyleRef style, CTParagraphStyleSpecifier spec,
                                         size_t bufferSize, void *buffer) {
    if (buffer == NULL) return false;
    if (spec >= kCTParagraphStyleSpecifierCount) {
        memset(buffer, 0, bufferSize);
        return false;
    }
    if (style == NULL || CFGetTypeID(style) != CTParagraphStyleGetTypeID() ||
        !supported(spec) || bufferSize < valueSize(spec)) return false;
    if (spec == kCTParagraphStyleSpecifierTabStops) memcpy(buffer, &style->tabs, sizeof(style->tabs));
    else memcpy(buffer, &style->values[spec], valueSize(spec));
    return true;
}
