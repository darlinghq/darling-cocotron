/* Copyright (c) 2007 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <CoreFoundation/CFData.h>
#import <CoreGraphics/CoreGraphicsExport.h>

typedef struct CF_BRIDGED_TYPE(id) O2DataProvider *CGDataProviderRef;

typedef void (*CGDataProviderReleaseDataCallback)(void *info, const void *data, size_t size);

typedef size_t (*CGDataProviderGetBytesCallback)(void* info, void* buffer, size_t count);
typedef off_t (*CGDataProviderSkipForwardCallback)(void* info, off_t count);
typedef void (*CGDataProviderRewindCallback)(void* info);
typedef void (*CGDataProviderReleaseInfoCallback)(void* info);

typedef struct CGDataProviderSequentialCallbacks {
	unsigned int version;
	CGDataProviderGetBytesCallback getBytes;
	CGDataProviderSkipForwardCallback skipForward;
	CGDataProviderRewindCallback rewind;
	CGDataProviderReleaseInfoCallback releaseInfo;
} CGDataProviderSequentialCallbacks;

CF_IMPLICIT_BRIDGING_ENABLED

COREGRAPHICS_EXPORT CGDataProviderRef CGDataProviderRetain(CGDataProviderRef provider);
COREGRAPHICS_EXPORT void CGDataProviderRelease(CGDataProviderRef provider);

COREGRAPHICS_EXPORT CGDataProviderRef CGDataProviderCreateWithCFData(CFDataRef data);
COREGRAPHICS_EXPORT CGDataProviderRef CGDataProviderCreateWithURL(CFURLRef url);
COREGRAPHICS_EXPORT CGDataProviderRef CGDataProviderCreateWithData(void *info, const void *data, size_t size, CGDataProviderReleaseDataCallback releaseCallback);

COREGRAPHICS_EXPORT CGDataProviderRef __nullable CGDataProviderCreateSequential(void* info, const CGDataProviderSequentialCallbacks* callbacks);

COREGRAPHICS_EXPORT CFDataRef CGDataProviderCopyData(CGDataProviderRef self);

CF_IMPLICIT_BRIDGING_DISABLED
