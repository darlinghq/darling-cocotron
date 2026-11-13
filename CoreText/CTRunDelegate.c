#include <CoreText/CTRunDelegate.h>
#include <CoreText/CTStringAttributes.h>
#include <CoreFoundation/CFRuntime.h>
#include <pthread.h>

struct __CTRunDelegate {
    CFRuntimeBase base;
    CTRunDelegateCallbacks callbacks;
    void *refCon;
};

const CFStringRef kCTRunDelegateAttributeName = CFSTR("CTRunDelegate");

static void CTRunDelegateFinalize(CFTypeRef value) {
    const struct __CTRunDelegate *delegate = (const struct __CTRunDelegate *)value;
    if (delegate->callbacks.dealloc != NULL)
        delegate->callbacks.dealloc(delegate->refCon);
}

static const CFRuntimeClass CTRunDelegateClass = {
    0, "CTRunDelegate", NULL, NULL, CTRunDelegateFinalize,
    NULL, NULL, NULL, NULL,
};

static CFTypeID runDelegateTypeID;
static pthread_once_t registerRunDelegateOnce = PTHREAD_ONCE_INIT;

static void RegisterRunDelegate(void) {
    runDelegateTypeID = _CFRuntimeRegisterClass(&CTRunDelegateClass);
}

CFTypeID CTRunDelegateGetTypeID(void) {
    pthread_once(&registerRunDelegateOnce, RegisterRunDelegate);
    return runDelegateTypeID;
}

CTRunDelegateRef CTRunDelegateCreate(const CTRunDelegateCallbacks *callbacks,
                                    void *refCon) {
    if (callbacks == NULL || callbacks->version != kCTRunDelegateCurrentVersion)
        return NULL;

    struct __CTRunDelegate *delegate = (struct __CTRunDelegate *)
        _CFRuntimeCreateInstance(kCFAllocatorDefault, CTRunDelegateGetTypeID(),
                                 sizeof(struct __CTRunDelegate) - sizeof(CFRuntimeBase),
                                 NULL);
    if (delegate == NULL)
        return NULL;
    delegate->callbacks = *callbacks;
    delegate->refCon = refCon;
    return delegate;
}

void *CTRunDelegateGetRefCon(CTRunDelegateRef runDelegate) {
    if (runDelegate == NULL)
        return NULL;
    return runDelegate->refCon;
}
