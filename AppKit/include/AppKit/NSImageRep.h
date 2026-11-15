/* Copyright (c) 2006-2007 Christopher J. W. Lloyd

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

#import <Foundation/NSGeometry.h>
#import <Foundation/NSObject.h>

@class NSArray, NSData, NSPasteboard, NSURL;

typedef NS_ENUM(NSInteger, NSImageLayoutDirection) {
    NSImageLayoutDirectionUnspecified = -1,
    NSImageLayoutDirectionLeftToRight = 2,
    NSImageLayoutDirectionRightToLeft = 3,
};

// Legacy ObjC ABI (i386): instance size must stay 0x1c, Apple's, which leaves
// no room for further ivars or for a pointer to extra state: the two flags
// share the storage unit of _bitsPerSample there (assign them YES/NO only).
// Never add an ivar to this class.
@interface NSImageRep : NSObject <NSCopying> {
    NSSize _size;
    NSString *_colorSpaceName;
#if __OBJC2__
    NSInteger _bitsPerSample;
    int _pixelsWide;
    int _pixelsHigh;

    BOOL _hasAlpha;
    BOOL _isOpaque;
#else
    NSInteger _bitsPerSample : 30;
    unsigned int _hasAlpha : 1;
    unsigned int _isOpaque : 1;
    int _pixelsWide;
    int _pixelsHigh;
#endif
}

+ (NSArray *) registeredImageRepClasses;
+ (void) registerImageRepClass: (Class) aClass;
+ (void) unregisterImageRepClass: (Class) aClass;

+ (NSArray *) imageFileTypes;
+ (NSArray *) imageUnfilteredFileTypes;
+ (NSArray *) imageTypes;
+ (NSArray *) imageUnfilteredTypes;
+ (NSArray *) imagePasteboardTypes;
+ (NSArray *) imageUnfilteredPasteboardTypes;

+ (BOOL) canInitWithData: (NSData *) data;
+ (BOOL) canInitWithPasteboard: (NSPasteboard *) pasteboard;

+ (Class) imageRepClassForData: (NSData *) data;
+ (Class) imageRepClassForFileType: (NSString *) type;
+ (Class) imageRepClassForPasteboardType: (NSString *) type;

+ (NSArray *) imageRepsWithContentsOfFile: (NSString *) path;
+ (NSArray *) imageRepsWithContentsOfURL: (NSURL *) url;
+ (NSArray *) imageRepsWithPasteboard: (NSPasteboard *) pasteboard;
+ imageRepWithContentsOfFile: (NSString *) path;
+ imageRepWithContentsOfURL: (NSURL *) url;
+ imageRepWithPasteboard: (NSPasteboard *) pasteboard;

- (instancetype) initWithCoder:(NSCoder *) coder;

@property(nonatomic) NSSize size;
@property(nonatomic) int pixelsWide;
@property(nonatomic) int pixelsHigh;
@property(nonatomic, getter=isOpaque) BOOL opaque;
- (BOOL) hasAlpha;
@property(nonatomic, copy) NSString *colorSpaceName;
@property(nonatomic) NSInteger bitsPerSample;

- (void) setAlpha: (BOOL) value;

- (BOOL) draw;
- (BOOL) drawAtPoint: (NSPoint) point;
- (BOOL) drawInRect: (NSRect) rect;

@end
