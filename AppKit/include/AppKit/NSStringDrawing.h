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

#import <Foundation/Foundation.h>

typedef NS_OPTIONS(NSInteger, NSStringDrawingOptions) {
    NSStringDrawingUsesLineFragmentOrigin = 0x01,
    NSStringDrawingUsesFontLeading = 0x02,
    NSStringDrawingDisableScreenFontSubstitution = 0x04,
    NSStringDrawingUsesDeviceMetrics = 0x08,
    NSStringDrawingOneShot = 0x10,
    NSStringDrawingTruncatesLastVisibleLine = 0x20,
};

@interface NSStringDrawingContext : NSObject
@property CGFloat minimumScaleFactor;
@property CGFloat minimumTrackingAdjustment;
@property(readonly) CGFloat actualScaleFactor;
@property(readonly) CGFloat actualTrackingAdjustment;
@property(readonly) NSRect totalBounds;
@end

@interface NSString (NSStringDrawing)
- (void) drawAtPoint: (NSPoint) point
        withAttributes: (NSDictionary *) attributes;
- (void) drawInRect: (NSRect) rect withAttributes: (NSDictionary *) attributes;

- (NSSize) sizeWithAttributes: (NSDictionary *) attributes;
- (NSRect) boundingRectWithSize: (NSSize) size
                        options: (NSStringDrawingOptions) options
                     attributes: (NSDictionary *) attributes;
- (NSRect) boundingRectWithSize: (NSSize) size
                        options: (NSStringDrawingOptions) options
                     attributes: (NSDictionary *) attributes
                        context: (NSStringDrawingContext *) context;
- (void) drawWithRect: (NSRect) rect
              options: (NSStringDrawingOptions) options
           attributes: (NSDictionary *) attributes;
- (void) drawWithRect: (NSRect) rect
              options: (NSStringDrawingOptions) options
           attributes: (NSDictionary *) attributes
              context: (NSStringDrawingContext *) context;

@end

@interface NSAttributedString (NSStringDrawing)
- (void) drawAtPoint: (NSPoint) point;
- (void) drawInRect: (NSRect) rect;
- (void) drawWithRect: (NSRect) rect options: (NSStringDrawingOptions) options;
- (void) drawWithRect: (NSRect) rect
              options: (NSStringDrawingOptions) options
              context: (NSStringDrawingContext *) context;
- (NSRect) boundingRectWithSize: (NSSize) size
                        options: (NSStringDrawingOptions) options;
- (NSRect) boundingRectWithSize: (NSSize) size
                        options: (NSStringDrawingOptions) options
                        context: (NSStringDrawingContext *) context;

- (NSSize) size;

@end
