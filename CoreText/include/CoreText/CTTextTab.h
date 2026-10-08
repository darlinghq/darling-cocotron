#import <CoreText/CTParagraphStyle.h>
#import <CoreFoundation/CFDictionary.h>

CF_IMPLICIT_BRIDGING_ENABLED

typedef const struct __CTTextTab *CTTextTabRef;

CORETEXT_EXPORT CTTextTabRef CTTextTabCreate(CTTextAlignment alignment, double location, CFDictionaryRef options);
CORETEXT_EXPORT CTTextAlignment CTTextTabGetAlignment(CTTextTabRef tab);
CORETEXT_EXPORT double CTTextTabGetLocation(CTTextTabRef tab);
CORETEXT_EXPORT CFDictionaryRef CTTextTabGetOptions(CTTextTabRef tab);
CORETEXT_EXPORT CFTypeID CTTextTabGetTypeID(void);

CF_IMPLICIT_BRIDGING_DISABLED
