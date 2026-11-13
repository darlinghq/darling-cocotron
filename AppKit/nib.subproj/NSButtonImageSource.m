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

// Original - Christopher Lloyd <cjwl@objc.net>
#import <AppKit/NSButtonImageSource.h>
#import <AppKit/NSImage.h>
#import <Foundation/NSKeyedArchiver.h>
#import <Foundation/NSString.h>

@implementation NSButtonImageSource

- initWithCoder: (NSCoder *) coder {
    if ([coder allowsKeyedCoding]) {
        NSKeyedUnarchiver *keyed = (NSKeyedUnarchiver *) coder;

        _imageName = [[keyed decodeObjectForKey: @"NSImageName"] retain];
    } else {
        NSInteger version = [coder versionForClassName: @"NSButtonImageSource"];

        if (version == 1) {
            _imageName = [[coder decodeObject] retain];
        } else if (version == 2) {
            // A flag selects between the image name and a dictionary of images with sizes.
            char hasImages;
            [coder decodeValuesOfObjCTypes: "c", &hasImages];

            if (hasImages == 0) {
                _imageName = [[coder decodeObject] retain];
            } else {
                char reserved1;
                int reserved2, reserved3, reserved4;
                float f1, f2, f3, f4;

                [coder decodeValuesOfObjCTypes: "@ffffciii", &_buttonImages, &f1, &f2, &f3, &f4, &reserved1, &reserved2,
                                                &reserved3, &reserved4];

                _imageSize = NSMakeSize(f1, f2);
                _focusRingImageSize = NSMakeSize(f3, f4);
            }
        } else {
            id obj = [coder decodeObject];
            if ([obj isKindOfClass: [NSString class]]) {
                _imageName = [obj retain];
            } else {
                _buttonImages = (NSDictionary *) [obj retain];

                // Four sizes, four bytes and three ints follow; the bytes and ints are
                // reserved or of unknown meaning.
                char reservedBytes[4];
                int reservedInts[3];
                float f1, f2, f3, f4;

                [coder decodeValuesOfObjCTypes: "ffffcccciii", &f1, &f2, &f3, &f4, &reservedBytes[0], &reservedBytes[1],
                                                &reservedBytes[2], &reservedBytes[3], &reservedInts[0], &reservedInts[1],
                                                &reservedInts[2]];

                _imageSize = NSMakeSize(f1, f2);
                _focusRingImageSize = NSMakeSize(f3, f4);
            }
        }
    }
    return self;
}

- (void) dealloc {
    [_imageName release];
    [_buttonImages release];
    [super dealloc];
}

- (NSImage *) normalImage {
    return [NSImage imageNamed: _imageName];
}

- (NSImage *) alternateImage {
    NSString *name = [@"NSHighlighted"
            stringByAppendingString: [_imageName substringFromIndex: 2]];

    return [NSImage imageNamed: name];
}

- (NSImage *) imageForState: (NSButtonState) state {
    // The dictionary of per-state images is not consulted: every state gets the normal image.
    return [self normalImage];
}

- (NSString *) name {
    return _imageName;
}

@end
