#import <CoreFoundation/CoreFoundation.h>

#if __cplusplus
	#define CA_EXPORT extern "C"
#else
	#define CA_EXPORT extern
#endif

// CA_EXTERN is the spelling recent macOS SDK headers use for the same declaration.
#define CA_EXTERN CA_EXPORT

CA_EXPORT CFTimeInterval CACurrentMediaTime(void);
