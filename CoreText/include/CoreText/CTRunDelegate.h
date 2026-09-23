#import <CoreText/CoreTextExport.h>
#import <CoreFoundation/CFBase.h>
#import <CoreGraphics/CGBase.h>

CF_IMPLICIT_BRIDGING_ENABLED

typedef const struct __CTRunDelegate *CTRunDelegateRef;

typedef void (*CTRunDelegateDeallocateCallback)(void *refCon);
typedef CGFloat (*CTRunDelegateGetAscentCallback)(void *refCon);
typedef CGFloat (*CTRunDelegateGetDescentCallback)(void *refCon);
typedef CGFloat (*CTRunDelegateGetWidthCallback)(void *refCon);

enum {
    kCTRunDelegateVersion1 = 1,
    kCTRunDelegateCurrentVersion = kCTRunDelegateVersion1,
};

typedef struct {
    CFIndex version;
    CTRunDelegateDeallocateCallback dealloc;
    CTRunDelegateGetAscentCallback getAscent;
    CTRunDelegateGetDescentCallback getDescent;
    CTRunDelegateGetWidthCallback getWidth;
} CTRunDelegateCallbacks;

CORETEXT_EXPORT CFTypeID CTRunDelegateGetTypeID(void);
CORETEXT_EXPORT CTRunDelegateRef CTRunDelegateCreate(const CTRunDelegateCallbacks *callbacks,
                                                     void *refCon);
CORETEXT_EXPORT void *CTRunDelegateGetRefCon(CTRunDelegateRef runDelegate);

CF_IMPLICIT_BRIDGING_DISABLED
