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

#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSGraphicsContextFunctions.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSImageRep.h>
#import <AppKit/NSPDFImageRep.h>
#import <AppKit/NSPICTImageRep.h>
#import <AppKit/NSPasteboard.h>
#import <AppKit/NSRaise.h>

@implementation NSImageRep

static NSMutableArray *_registeredClasses = nil;

+ (void) initialize {
    if (self == [NSImageRep class]) {
        _registeredClasses = [NSMutableArray new];
        [_registeredClasses addObject: [NSBitmapImageRep class]];
        [_registeredClasses addObject: [NSPDFImageRep class]];
        [_registeredClasses addObject: [NSPICTImageRep class]];
    }
}

+ (NSArray *) registeredImageRepClasses {
    return _registeredClasses;
}

+ (void) registerImageRepClass: (Class) class {
    [_registeredClasses addObject: class];
}

+ (void) unregisterImageRepClass: (Class) class {
    [_registeredClasses removeObjectIdenticalTo: class];
}

+ (NSArray *) imageFileTypes {
    NSMutableSet *result = [NSMutableSet set];
    int i, count = [_registeredClasses count];

    for (i = 0; i < count; i++) {
        Class cls = [_registeredClasses objectAtIndex: i];

        [result addObjectsFromArray: [cls imageUnfilteredFileTypes]];
    }

    return [result allObjects];
}

+ (NSArray *) imageUnfilteredFileTypes {
    return [NSArray array];
}

// There is no type database to consult, so this covers the extensions the
// built-in image reps read.
static NSArray *typesForFileTypes(NSArray *fileTypes) {
    NSDictionary *utis = @{
        @"png" : @"public.png",
        @"tiff" : @"public.tiff",
        @"tif" : @"public.tiff",
        @"jpg" : @"public.jpeg",
        @"jpeg" : @"public.jpeg",
        @"jpe" : @"public.jpeg",
        @"gif" : @"com.compuserve.gif",
        @"bmp" : @"com.microsoft.bmp",
        @"icns" : @"com.apple.icns",
        @"pdf" : @"com.adobe.pdf",
        @"pict" : @"com.apple.pict",
        @"pct" : @"com.apple.pict",
        @"pic" : @"com.apple.pict",
    };
    NSMutableArray *result = [NSMutableArray array];

    for (NSString *fileType in fileTypes) {
        NSString *uti = [utis objectForKey: [fileType lowercaseString]];
        if (uti != nil && ![result containsObject: uti])
            [result addObject: uti];
    }
    return result;
}

+ (NSArray *) imageTypes {
    // +imageFileTypes merges every registered class, which only suits NSImageRep itself.
    if (self != [NSImageRep class])
        return typesForFileTypes([self imageUnfilteredFileTypes]);
    return typesForFileTypes([self imageFileTypes]);
}

+ (NSArray *) imageUnfilteredTypes {
    return typesForFileTypes([self imageUnfilteredFileTypes]);
}

+ (NSArray *) imagePasteboardTypes {
    NSMutableSet *result = [NSMutableSet set];
    int i, count = [_registeredClasses count];

    for (i = 0; i < count; i++) {
        Class cls = [_registeredClasses objectAtIndex: i];

        [result addObjectsFromArray: [cls imageUnfilteredPasteboardTypes]];
    }

    return [result allObjects];
}

+ (NSArray *) imageUnfilteredPasteboardTypes {
    return [NSArray array];
}

+ (BOOL) canInitWithData: (NSData *) data {
    return NO;
}

+ (BOOL) canInitWithPasteboard: (NSPasteboard *) pasteboard {
    NSString *available = [pasteboard
            availableTypeFromArray: [self imageUnfilteredPasteboardTypes]];

    return (available != nil) ? YES : NO;
}

+ (Class) imageRepClassForData: (NSData *) data {
    int count = [_registeredClasses count];

    while (--count >= 0) {
        Class check = [_registeredClasses objectAtIndex: count];

        if ([check canInitWithData: data])
            return check;
    }

    return nil;
}

+ (Class) imageRepClassForFileType: (NSString *) type {
    int count = [_registeredClasses count];

    while (--count >= 0) {
        Class checkClass = [_registeredClasses objectAtIndex: count];
        NSArray *types = [checkClass imageUnfilteredFileTypes];

        for (NSString *checkType in types)
            if ([checkType caseInsensitiveCompare: type] == NSOrderedSame)
                return checkClass;
    }

    return nil;
}

+ (Class) imageRepClassForPasteboardType: (NSString *) type {
    int count = [_registeredClasses count];

    while (--count >= 0) {
        Class checkClass = [_registeredClasses objectAtIndex: count];
        NSArray *types = [checkClass imageUnfilteredPasteboardTypes];

        if ([types containsObject: type])
            return checkClass;
    }

    return nil;
}

+ (NSArray *) imageRepsWithContentsOfFile: (NSString *) path {
    // Try to guess which class to use from the path extension
    NSString *type = [path pathExtension];
    Class class = [self imageRepClassForFileType: type];
    if (class == nil) {
        // Else use the content of the file to guess the class to use
        NSData *data = [NSData dataWithContentsOfFile: path];

        if (data == nil) {
            return nil;
        }

        if (self == [NSImageRep class]) {
            class = [self imageRepClassForData: data];
        }
        return [class imageRepsWithData: data];
    }
    return [class imageRepsWithContentsOfFile: path];
}

+ (NSArray *) imageRepsWithContentsOfURL: (NSURL *) url {
    Class class = self;
    NSData *data = [NSData dataWithContentsOfURL: url];

    if (data == nil)
        return nil;

    if (self == [NSImageRep class]) {
        if ((class = [self imageRepClassForData: data]) == nil)
            return nil;
    }

    return [class imageRepsWithData: data];
}

+ (NSArray *) imageRepsWithPasteboard: (NSPasteboard *) pasteboard {
    NSArray *imageTypes = [self imagePasteboardTypes];
    NSArray *pbTypes = [pasteboard types];

    for (NSString *check in pbTypes) {
        if ([imageTypes containsObject: check]) {
            NSData *data = [pasteboard dataForType: check];
            Class class;

            if ((class = [self imageRepClassForData: data]) != nil) {
                NSArray *result;

                if ((result = [class imageRepsWithData: data]) != nil)
                    return result;
            }
        }
    }

    return nil;
}

+ imageRepWithContentsOfFile: (NSString *) path {
    Class class = self;
    NSData *data = [NSData dataWithContentsOfFile: path];

    if (data == nil)
        return nil;

    if (self == [NSImageRep class]) {
        NSString *type = [path pathExtension];

        if ((class = [self imageRepClassForFileType: type]) == nil)
            return nil;
    }

    return [class imageRepWithData: data];
}

+ imageRepWithContentsOfURL: (NSURL *) url {
    Class class = self;
    NSData *data = [NSData dataWithContentsOfURL: url];

    if (data == nil)
        return nil;

    if (self == [NSImageRep class]) {
        if ((class = [self imageRepClassForData: data]) == nil)
            return nil;
    }

    return [class imageRepWithData: data];
}

+ imageRepWithPasteboard: (NSPasteboard *) pasteboard {
    NSArray *imageTypes = [self imagePasteboardTypes];
    NSArray *pbTypes = [pasteboard types];

    for (NSString *check in pbTypes) {
        if ([imageTypes containsObject: check]) {
            NSData *data = [pasteboard dataForType: check];
            Class class;

            if ((class = [self imageRepClassForData: data]) != nil) {
                NSArray *result;

                if ((result = [class imageRepWithData: data]) != nil)
                    return result;
            }
        }
    }

    return nil;
}

// An NSArchiver archive holds the size, a byte for has-alpha, a byte for opaque, then the
// pixel width and height, the bits per sample and the colour space name. Versions up to 16
// are not read.
- (instancetype) initWithCoder:(NSCoder *) coder
{
    if ([coder allowsKeyedCoding] || [coder versionForClassName: @"NSImageRep"] < 17) {
        [NSException raise: NSInvalidArgumentException
                        format: @"-[%@ %s] is not implemented for coder %@",
                                [self class], sel_getName(_cmd), coder];
        return nil;
    }
    if ((self = [super init]) == nil)
        return nil;

    float width, height;
    char hasAlpha, opaque;
    int pixelsWide, pixelsHigh, bitsPerSample;
    NSString *colorSpaceName = nil;

    [coder decodeValuesOfObjCTypes: "ff", &width, &height];
    [coder decodeValuesOfObjCTypes: "c", &hasAlpha];
    [coder decodeValuesOfObjCTypes: "c", &opaque];
    [coder decodeValuesOfObjCTypes: "iii@", &pixelsWide, &pixelsHigh, &bitsPerSample, &colorSpaceName];
    _size = NSMakeSize(width, height);
    _hasAlpha = hasAlpha != 0;
    _isOpaque = opaque != 0;
    _pixelsWide = pixelsWide;
    _pixelsHigh = pixelsHigh;
    _bitsPerSample = bitsPerSample;
    _colorSpaceName = colorSpaceName;
    return self;
}

- copyWithZone: (NSZone *) zone {
    NSImageRep *result = NSCopyObject(self, 0, zone);
    result->_colorSpaceName = [_colorSpaceName copy];
    return result;
}

- (NSSize) size {
    return _size;
}

- (int) pixelsWide {
    return _pixelsWide;
}

- (int) pixelsHigh {
    return _pixelsHigh;
}

- (BOOL) isOpaque {
    return _isOpaque;
}

- (BOOL) hasAlpha {
    return _hasAlpha;
}

- (NSString *) colorSpaceName {
    return _colorSpaceName;
}

- (NSInteger) bitsPerSample {
    return _bitsPerSample;
}

- (void) setSize: (NSSize) value {
    _size = value;
}

- (void) setPixelsWide: (int) value {
    _pixelsWide = value;
}

- (void) setPixelsHigh: (int) value {
    _pixelsHigh = value;
}

- (void) setOpaque: (BOOL) value {
    _isOpaque = value;
}

- (void) setAlpha: (BOOL) value {
    _hasAlpha = value;
}

- (void) setColorSpaceName: (NSString *) value {
    value = [value copy];
    [_colorSpaceName release];
    _colorSpaceName = value;
}

- (void) setBitsPerSample: (int) value {
    _bitsPerSample = value;
}

- (BOOL) draw {
    // do nothing
    return YES;
}

- (BOOL) drawAtPoint: (NSPoint) point {
    CGContextRef context = NSCurrentGraphicsPort();
    BOOL result;

    CGContextSaveGState(context);
    @try {
        CGContextTranslateCTM(context, point.x, point.y);
        result = [self draw];
    } @finally {
        CGContextRestoreGState(context);
    }

    return result;
}

// An image of the representation drawn at the proposed size (its own size without a rect); NSBitmapImageRep
// overrides this with the image it holds. The caller does not own the result.
- (CGImageRef) CGImageForProposedRect: (NSRect *) proposedDestRect
                              context: (NSGraphicsContext *) context
                                hints: (NSDictionary<NSString *, id> *) hints
{
    NSSize size = proposedDestRect != NULL ? proposedDestRect->size : [self size];
    if (!(size.width > 0 && size.height > 0 && isfinite(size.width) && isfinite(size.height)))
        return NULL;
    size_t width = ceil(size.width), height = ceil(size.height);

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    // An explicit byte order: Onyx2D stores the default order as ABGR, unlike Apple's RGBA.
    CGContextRef bitmap = CGBitmapContextCreate(NULL, width, height, 8, width * 4, colorSpace,
                                                kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    if (bitmap == NULL)
        return NULL;
    CGContextClearRect(bitmap, CGRectMake(0, 0, width, height));

    // The thread dictionary may be the only owner of the current context.
    NSGraphicsContext *previous = [[NSGraphicsContext currentContext] retain];
    [NSGraphicsContext setCurrentContext: [NSGraphicsContext graphicsContextWithGraphicsPort: bitmap flipped: NO]];
    [self drawInRect: NSMakeRect(0, 0, width, height)];
    [NSGraphicsContext setCurrentContext: previous];
    [previous release];

    CGImageRef image = CGBitmapContextCreateImage(bitmap);
    CGContextRelease(bitmap);
    return (CGImageRef) [(id) image autorelease];
}

- (BOOL) drawInRect: (NSRect) rect {
    CGContextRef context = NSCurrentGraphicsPort();
    NSSize size = [self size];
    BOOL result;

    CGContextSaveGState(context);
    @try {
        CGContextTranslateCTM(context, rect.origin.x, rect.origin.y);
        CGContextScaleCTM(context, rect.size.width / size.width,
                          rect.size.height / size.height);
        result = [self draw];
    } @finally {
        CGContextRestoreGState(context);
    }

    return result;
}

// Draws the part of the representation given by fromRect (all of it for an empty rectangle) into
// rect, scaled, with the given compositing operation and opacity. The NSImageHintInterpolation hint
// selects the interpolation quality for this drawing only.
- (BOOL) drawInRect: (NSRect) rect
           fromRect: (NSRect) fromRect
          operation: (NSCompositingOperation) operation
           fraction: (CGFloat) fraction
     respectFlipped: (BOOL) respectFlipped
              hints: (NSDictionary<NSString *, id> *) hints
{
    NSGraphicsContext *graphicsContext = [NSGraphicsContext currentContext];
    NSSize size = [self size];
    if (graphicsContext == nil || !(size.width > 0 && size.height > 0))
        return NO;
    if (NSIsEmptyRect(fromRect))
        fromRect = NSMakeRect(0, 0, size.width, size.height);
    if (!(fromRect.size.width > 0 && fromRect.size.height > 0))
        return NO;
    // Observed on macOS 26.7.3: an empty destination draws nothing and still returns YES.
    if (!(rect.size.width > 0 && rect.size.height > 0))
        return YES;

    CGContextRef context = [graphicsContext graphicsPort];
    NSCompositingOperation previousOperation = [graphicsContext compositingOperation];
    NSImageInterpolation previousInterpolation = [graphicsContext imageInterpolation];
    BOOL result;

    CGContextSaveGState(context);
    @try {
        CGContextSetAlpha(context, fraction);
        [graphicsContext setCompositingOperation: operation];
        id interpolation = [hints objectForKey: NSImageHintInterpolation];
        if ([interpolation respondsToSelector: @selector(unsignedIntegerValue)])
            [graphicsContext setImageInterpolation: (NSImageInterpolation) [interpolation unsignedIntegerValue]];
        CGContextClipToRect(context, NSRectToCGRect(rect));
        if (respectFlipped && [graphicsContext isFlipped]) {
            // Upright in a flipped context: mirror the destination about its own centre.
            CGContextTranslateCTM(context, 0, NSMinY(rect) + NSMaxY(rect));
            CGContextScaleCTM(context, 1, -1);
        }
        CGFloat scaleX = rect.size.width / fromRect.size.width;
        CGFloat scaleY = rect.size.height / fromRect.size.height;
        result = [self drawInRect: NSMakeRect(rect.origin.x - fromRect.origin.x * scaleX,
                                              rect.origin.y - fromRect.origin.y * scaleY,
                                              size.width * scaleX, size.height * scaleY)];
    } @finally {
        CGContextRestoreGState(context);
        [graphicsContext setCompositingOperation: previousOperation];
        [graphicsContext setImageInterpolation: previousInterpolation];
    }
    return result;
}

- (NSString *) description {
    return [NSString
            stringWithFormat:
                    @"<%@[%p] size: { %f, %f } colorSpace: %@ (%dx%d @ "
                    @"%ld bps) alpha: %@ opaque: %@>",
                    [self class], self, _size.width, _size.height,
                    _colorSpaceName, _pixelsWide, _pixelsHigh, (long) _bitsPerSample,
                    _hasAlpha ? @"YES" : @"NO", _isOpaque ? @"YES" : @"NO"];
}

@end
