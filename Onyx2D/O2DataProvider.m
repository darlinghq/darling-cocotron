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

#import <Foundation/NSData.h>
#import <Foundation/NSFileManager.h>
#import <Foundation/NSStream.h>
#import <Foundation/NSURL.h>
#import <Foundation/NSValue.h>
#import <Onyx2D/O2DataProvider.h>
#import <string.h>

@implementation O2DataProvider

- initWithData: (NSData *) data {
    // Owned outright: a convenience constructor would also leave the stream (and the data or
    // file it holds) in the autorelease pool until the pool drains, after the provider is gone.
    _inputStream = [[NSInputStream alloc] initWithData: data];
    [_inputStream open];
    _data = [data retain];
    _isDirectAccess = YES;
    _bytes = [data bytes];
    _length = [data length];
    return self;
}

- initWithBytes: (const void *) bytes length: (size_t) length {
    NSData *data = [[NSData alloc] initWithBytesNoCopy: (void *) bytes
                                        length: length
                                  freeWhenDone: NO];
    id result = [self initWithData: data];
    [data release];
    return result;
}

- initWithFilename: (const char *) pathCString {
    // why doesn't O2DataProvider use CFString's, ugh
    NSUInteger len = strlen(pathCString);
    _path = [[[NSFileManager defaultManager]
            stringWithFileSystemRepresentation: pathCString
                                        length: len] copy];
    if (![[NSFileManager defaultManager] isReadableFileAtPath: _path]) {
        // A file that cannot be opened for reading gives no provider.
        [self release];
        return nil;
    }
    _inputStream = [[NSInputStream alloc] initWithFileAtPath: _path];
    [_inputStream open];
    _data = nil;
    _isDirectAccess = NO;
    _bytes = nil;
    _length = 0;
    return self;
}

- initWithURL: (NSURL *) url {
    NSData *data = (url != nil) ? [[NSData alloc] initWithContentsOfURL: url] : nil;

    if (data == nil) {
        // Unreadable or missing file: CGDataProviderCreateWithURL returns NULL.
        [self release];
        return nil;
    }

    id result = [self initWithData: data];

    [data release];

    return result;
}

O2DataProviderRef
O2DataProviderCreateWithData(void *info, const void *data, size_t size,
                             O2DataProviderReleaseDataCallback releaseCallback)
{
    O2DataProvider *provider = [[O2DataProvider alloc] initWithBytes: data length: size];
    if (provider != nil) {
        provider->_releaseInfo = info;
        provider->_releaseData = data;
        provider->_releaseSize = size;
        provider->_releaseCallback = releaseCallback;
    }
    return provider;
}

O2DataProviderRef O2DataProviderCreateSequential(void *info, const O2DataProviderSequentialCallbacks *callbacks) {
    if (callbacks == NULL || callbacks->version != 0 || callbacks->getBytes == NULL)
        return NULL;
    O2DataProvider *provider = [[O2DataProvider alloc] init];
    provider->_sequential = YES;
    provider->_sequentialInfo = info;
    provider->_sequentialCallbacks = *callbacks;
    return provider;
}

// Reads the whole content through the callbacks: rewind, read until a call gives no bytes, rewind again.
- (NSData *) _copySequentialContent {
    if (_sequentialCallbacks.rewind != NULL)
        _sequentialCallbacks.rewind(_sequentialInfo);
    NSMutableData *content = [[NSMutableData alloc] init];
    unsigned char buffer[8192];
    for (;;) {
        size_t count = _sequentialCallbacks.getBytes(_sequentialInfo, buffer, sizeof(buffer));
        if (count == 0)
            break;
        if (count > sizeof(buffer))
            count = sizeof(buffer);
        [content appendBytes: buffer length: count];
    }
    if (_sequentialCallbacks.rewind != NULL)
        _sequentialCallbacks.rewind(_sequentialInfo);
    return content;
}

// Direct access to the content of a sequential provider: it is read once, on first use.
- (void) _materialize {
    if (!_sequential || _data != nil)
        return;
    _data = [self _copySequentialContent];
    _inputStream = [[NSInputStream alloc] initWithData: _data];
    [_inputStream open];
    _isDirectAccess = YES;
    _bytes = [_data bytes];
    _length = [_data length];
}

O2DataProviderRef O2DataProviderCreateWithCFData(CFDataRef data) {
    return [[O2DataProvider alloc] initWithData: (NSData *) data];
}

O2DataProviderRef O2DataProviderCreateWithURL(NSURL *url) {
    return [[O2DataProvider alloc] initWithURL: url];
}

O2DataProviderRef O2DataProviderCreateWithFilename(const char *pathCString) {
    return [[O2DataProvider alloc] initWithFilename: pathCString];
}

O2DataProviderRef O2DataProviderRetain(O2DataProviderRef self) {
    return (self != NULL) ? (O2DataProviderRef) CFRetain(self) : NULL;
}

void O2DataProviderRelease(O2DataProviderRef self) {
    if (self != NULL)
        CFRelease(self);
}

CFDataRef O2DataProviderCopyData(O2DataProviderRef self) {
    // CGDataProviderCopyData returns NULL for a NULL provider.
    if (self == NULL)
        return NULL;
    // Every copy of a sequential provider's data is a fresh pass over the callbacks.
    if (self->_sequential)
        return (CFDataRef) [self _copySequentialContent];
    if (self->_data != nil)
        return (CFDataRef) [[NSData alloc] initWithBytes: [self->_data bytes]
                                                length: [self->_data length]];
    else
        return (CFDataRef) [[NSData alloc] initWithContentsOfFile: self->_path];
}

- (void) dealloc {
    [_inputStream close];
    [_inputStream release];
    [_data release];
    [_path release];
    if (_releaseCallback != NULL)
        _releaseCallback(_releaseInfo, _releaseData, _releaseSize);
    if (_sequential && _sequentialCallbacks.releaseInfo != NULL)
        _sequentialCallbacks.releaseInfo(_sequentialInfo);
    [super dealloc];
}

- (NSString *) path {
    return _path;
}

- (NSInputStream *) inputStream {
    [self _materialize];
    return _inputStream;
}

- (BOOL) isDirectAccess {
    [self _materialize];
    return _isDirectAccess;
}

- (NSData *) data {
    [self _materialize];
    return _data;
}

- (const void *) bytes {
    [self _materialize];
    return _bytes;
}

- (size_t) length {
    [self _materialize];
    return _length;
}

- (void) rewind {
    [self _materialize];
    NSNumber *number = [[NSNumber alloc] initWithInt: 0];

    [_inputStream setProperty: number forKey: NSStreamFileCurrentOffsetKey];

    [number release];
}

- (NSInteger) getBytes: (void *) bytes range: (NSRange) range {
    [self _materialize];
    if (_data != nil) {
        NSUInteger length = [_data length];

        if (NSMaxRange(range) <= length) {
            [_data getBytes: bytes range: range];
            return range.length;
        } else if (range.location < length) {
            range.length = length - range.location;
            [_data getBytes: bytes range: range];
            return range.length;
        } else
            return -1;
    } else {
        NSInteger check = -1;
        NSNumber *number = [[NSNumber alloc] initWithInt: range.location];

        if ([_inputStream setProperty: number
                               forKey: NSStreamFileCurrentOffsetKey])
            check = [_inputStream read: bytes maxLength: range.length];

        [number release];

        return check;
    }
}

@end
