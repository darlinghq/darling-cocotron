#include <CoreText/CoreText.h>

static int deallocCalls;

static void releaseContext(void *context) {
    if (context != &deallocCalls)
        deallocCalls = -100;
    else
        deallocCalls++;
}

static CGFloat ascent(void *context) { return context == &deallocCalls ? 12 : 0; }
static CGFloat descent(void *context) { return context == &deallocCalls ? 3 : 0; }
static CGFloat width(void *context) { return context == &deallocCalls ? 24 : 0; }

int main(void) {
    CTRunDelegateCallbacks callbacks = {
        kCTRunDelegateCurrentVersion, releaseContext, ascent, descent, width,
    };
    CTRunDelegateRef delegate = CTRunDelegateCreate(&callbacks, &deallocCalls);
    if (delegate == NULL) return 1;
    if (CFGetTypeID(delegate) != CTRunDelegateGetTypeID()) return 2;
    if (CTRunDelegateGetRefCon(delegate) != &deallocCalls) return 3;
    if (callbacks.getAscent(CTRunDelegateGetRefCon(delegate)) != 12) return 4;
    if (callbacks.getDescent(CTRunDelegateGetRefCon(delegate)) != 3) return 5;
    if (callbacks.getWidth(CTRunDelegateGetRefCon(delegate)) != 24) return 6;
    if (kCTRunDelegateAttributeName == NULL) return 7;

    CFRetain(delegate);
    CFRelease(delegate);
    if (deallocCalls != 0) return 8;
    CFRelease(delegate);
    if (deallocCalls != 1) return 9;

    callbacks.version = 0;
    if (CTRunDelegateCreate(&callbacks, NULL) != NULL) return 10;
    return 0;
}
