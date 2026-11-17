/* Copyright (C) 2026 Lubos Dolezel

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

#import <AppKit/NSImageRep.h>
#import <AppKit/AppKitIvarLayout.h>
#import <ApplicationServices/ApplicationServices.h>

// An image representation of a QuickDraw picture (PICT version 2): the bitmaps
// the picture draws are decoded when the representation is created.
@interface NSPICTImageRep : NSImageRep <NSCopying> {
    NS_LEGACY_IVAR_PAD(_NSPICTImageRepReserved, 16)
    NS_EXTRA_IVARS_BEGIN(NSPICTImageRep)
    NSData *_pict;
    NSRect _boundingBox;
    NSMutableArray *_bitmaps;
    NS_EXTRA_IVARS_END(NSPICTImageRep)
}

- initWithData: (NSData *) data;

+ (NSArray *) imageRepsWithData: (NSData *) data;
+ imageRepWithData: (NSData *) data;

- (NSData *) PICTRepresentation;
- (NSRect) boundingBox;

@end
