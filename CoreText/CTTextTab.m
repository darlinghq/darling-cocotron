#import <CoreText/CTTextTab.h>
#include <CoreFoundation/CFRuntime.h>
#include <pthread.h>
#include <math.h>

struct __CTTextTab {
    CFRuntimeBase base;
    CTTextAlignment alignment;
    double location;
    CFDictionaryRef options;
};

static void finalizeTab(CFTypeRef value) {
    CTTextTabRef tab = value;
    if (tab->options != NULL) CFRelease(tab->options);
}

static const CFRuntimeClass tabClass = {
    0, "CTTextTab", NULL, NULL, finalizeTab, NULL, NULL, NULL, NULL,
};
static CFTypeID tabType;
static pthread_once_t registerTabOnce = PTHREAD_ONCE_INIT;

static void registerTab(void) {
    tabType = _CFRuntimeRegisterClass(&tabClass);
}

CFTypeID CTTextTabGetTypeID(void) {
    pthread_once(&registerTabOnce, registerTab);
    return tabType;
}

static void copyOption(const void *key, const void *value, void *context) {
    CFDictionarySetValue(context, key, value);
}

CTTextTabRef CTTextTabCreate(CTTextAlignment alignment, double location, CFDictionaryRef options) {
    if (alignment > kCTTextAlignmentNatural || !isfinite(location) ||
        (options != NULL && CFGetTypeID(options) != CFDictionaryGetTypeID())) return NULL;
    CFDictionaryRef snapshot = NULL;
    if (options != NULL) {
        CFMutableDictionaryRef owned = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        if (owned == NULL) return NULL;
        CFDictionaryApplyFunction(options, copyOption, owned);
        snapshot = CFDictionaryCreateCopy(kCFAllocatorDefault, owned);
        CFRelease(owned);
        if (snapshot == NULL) return NULL;
    }
    struct __CTTextTab *tab = (struct __CTTextTab *)_CFRuntimeCreateInstance(
            kCFAllocatorDefault, CTTextTabGetTypeID(), sizeof(*tab) - sizeof(CFRuntimeBase), NULL);
    if (tab == NULL) {
        if (snapshot != NULL) CFRelease(snapshot);
        return NULL;
    }
    tab->alignment = alignment;
    tab->location = location;
    tab->options = snapshot;
    return tab;
}

CTTextAlignment CTTextTabGetAlignment(CTTextTabRef tab) { return tab->alignment; }
double CTTextTabGetLocation(CTTextTabRef tab) { return tab->location; }
CFDictionaryRef CTTextTabGetOptions(CTTextTabRef tab) { return tab->options; }
