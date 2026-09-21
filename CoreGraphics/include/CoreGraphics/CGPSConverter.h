#ifndef CGPSCONVERTER_H
#define CGPSCONVERTER_H

#import <CoreFoundation/CoreFoundation.h>

typedef struct CF_BRIDGED_TYPE(id) CGPSConverter* CGPSConverterRef;

typedef void (*CGPSConverterBeginDocumentCallback)(void* info);
typedef void (*CGPSConverterEndDocumentCallback)(void* info, bool success);
typedef void (*CGPSConverterBeginPageCallback)(void* info, size_t pageNumber, CFDictionaryRef  pageInfo);
typedef void (*CGPSConverterEndPageCallback)(void* info, size_t pageNumber, CFDictionaryRef  pageInfo);
typedef void (*CGPSConverterProgressCallback)(void* info);
typedef void (*CGPSConverterMessageCallback)(void* info, CFStringRef  message);
typedef void (*CGPSConverterReleaseInfoCallback)(void* info);

typedef struct CGPSConverterCallbacks {
	unsigned int version;
	CGPSConverterBeginDocumentCallback beginDocument;
	CGPSConverterEndDocumentCallback endDocument;
	CGPSConverterBeginPageCallback beginPage;
	CGPSConverterEndPageCallback endPage;
	CGPSConverterProgressCallback noteProgress;
	CGPSConverterMessageCallback noteMessage;
	CGPSConverterReleaseInfoCallback releaseInfo;
} CGPSConverterCallbacks;

extern CGPSConverterRef CGPSConverterCreate(void *info, const CGPSConverterCallbacks *callbacks, CFDictionaryRef options);

#endif /* CGPSCONVERTER_H */
