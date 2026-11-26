/* Copyright (c) 2007 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <CoreGraphics/CGDataProvider.h>
#import <Onyx2D/O2DataProvider.h>
#import <CoreGraphics/CoreGraphicsPrivate.h>
#include <stdlib.h>
#include <string.h>

CGDataProviderRef CGDataProviderRetain(CGDataProviderRef provider) {
    return (CGDataProviderRef)O2DataProviderRetain((O2DataProviderRef)provider);
}

void CGDataProviderRelease(CGDataProviderRef provider) {
    O2DataProviderRelease((O2DataProviderRef)provider);
}

CGDataProviderRef CGDataProviderCreateWithCFData(CFDataRef data) {
    return (CGDataProviderRef)O2DataProviderCreateWithCFData(data);
}

// NULL for a NULL name and for a file that cannot be opened for reading
// (observed on macOS 26.7.3 for a missing file).
CGDataProviderRef CGDataProviderCreateWithFilename(const char *filename) {
    if (filename == NULL)
        return NULL;
    return (CGDataProviderRef)O2DataProviderCreateWithFilename(filename);
}

COREGRAPHICS_EXPORT CGDataProviderRef
CGDataProviderCreateWithData(void *info, const void *data, size_t size,
                             CGDataProviderReleaseDataCallback releaseCallback)
{
    return (CGDataProviderRef)O2DataProviderCreateWithData(info, data, size, releaseCallback);
}

// A direct provider reads all of its data when it is created, into a
// copy the provider owns; the client's info is released with the provider.
typedef struct {
    void *info;
    CGDataProviderReleaseInfoCallback releaseInfo;
} CallbackProviderContext;

static void releaseCallbackProviderData(void *context, const void *data, size_t size) {
    CallbackProviderContext *callbackContext = context;
    free((void *) data);
    if (callbackContext->releaseInfo != NULL)
        callbackContext->releaseInfo(callbackContext->info);
    free(callbackContext);
}

static CGDataProviderRef createProviderOwningBytes(void *bytes, size_t size, void *info, CGDataProviderReleaseInfoCallback releaseInfo) {
    CallbackProviderContext *context = malloc(sizeof(CallbackProviderContext));
    if (context == NULL) {
        free(bytes);
        return NULL;
    }
    context->info = info;
    context->releaseInfo = releaseInfo;
    CGDataProviderRef provider = CGDataProviderCreateWithData(context, bytes, size, releaseCallbackProviderData);
    if (provider == NULL) {
        free(bytes);
        free(context);
    }
    return provider;
}

CGDataProviderRef CGDataProviderCreateDirect(void *info, off_t size, const CGDataProviderDirectCallbacks *callbacks) {
    if (callbacks == NULL || size < 0 || (callbacks->getBytePointer == NULL && callbacks->getBytesAtPosition == NULL))
        return NULL;
    unsigned char *bytes = malloc(size > 0 ? (size_t) size : 1);
    if (bytes == NULL)
        return NULL;
    const void *pointer = callbacks->getBytePointer != NULL ? callbacks->getBytePointer(info) : NULL;
    if (pointer != NULL) {
        memcpy(bytes, pointer, (size_t) size);
        if (callbacks->releaseBytePointer != NULL)
            callbacks->releaseBytePointer(info, pointer);
    } else if (callbacks->getBytesAtPosition != NULL) {
        size_t done = 0;
        while (done < (size_t) size) {
            size_t count = callbacks->getBytesAtPosition(info, bytes + done, (off_t) done, (size_t) size - done);
            if (count == 0)
                break;
            done += count;
        }
        size = (off_t) done;
    } else {
        free(bytes);
        return NULL;
    }
    return createProviderOwningBytes(bytes, (size_t) size, info, callbacks->releaseInfo);
}

static void releaseCopiedData(void *info, const void *data, size_t size) {
    (void) info;
    (void) size;
    free((void *) data);
}

CGDataProviderRef CGDataProviderCreateWithCopyOfData(const void *data, size_t size) {
    if (data == NULL && size != 0)
        return NULL;
    void *copy = malloc(size > 0 ? size : 1);
    if (copy == NULL)
        return NULL;
    if (size > 0)
        memcpy(copy, data, size);
    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, copy, size, releaseCopiedData);
    if (provider == NULL)
        free(copy);
    return provider;
}

// NULL for NULL callbacks, a callbacks version other than 0 and a missing getBytes callback
// (observed on macOS 26.7.3 and 10.14.4); skipForward, rewind and releaseInfo may be NULL.
// The callbacks structure has the layout of O2DataProviderSequentialCallbacks.
CGDataProviderRef CGDataProviderCreateSequential(void *info, const CGDataProviderSequentialCallbacks *callbacks) {
    return (CGDataProviderRef)O2DataProviderCreateSequential(info, (const O2DataProviderSequentialCallbacks *)callbacks);
}

COREGRAPHICS_EXPORT CFDataRef CGDataProviderCopyData(CGDataProviderRef self) {
    return (CFDataRef) O2DataProviderCopyData((O2DataProviderRef)self);
}
