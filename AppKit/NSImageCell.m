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

#import "NSImage+TemplateDrawing.h"
#import <AppKit/NSColor.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSImageCell.h>
#import <ApplicationServices/ApplicationServices.h>
#import <Foundation/NSKeyedArchiver.h>

@implementation NSImageCell

- (void) encodeWithCoder: (NSCoder *) coder {
    [super encodeWithCoder: coder];
    [coder encodeBool: _animates forKey: @"NSAnimates"];
    [coder encodeInt: _imageAlignment forKey: @"NSAlign"];
    [coder encodeInt: _imageScaling forKey: @"NSScale"];
    [coder encodeInt: _frameStyle forKey: @"NSStyle"];
}

- (id) initWithCoder: (NSCoder *) coder {
    // The class version is asked before the superclass part is decoded.
    NSInteger version = [coder allowsKeyedCoding] ? 0 : [coder versionForClassName: @"NSImageCell"];

    [super initWithCoder: coder];
    if ([coder allowsKeyedCoding]) {
        NSKeyedUnarchiver *keyed = (NSKeyedUnarchiver *) coder;
        _animates = [keyed decodeBoolForKey: @"NSAnimates"];
        _imageAlignment = [keyed decodeIntForKey: @"NSAlign"];
        _imageScaling = [keyed decodeIntForKey: @"NSScale"];
        _frameStyle = [keyed decodeIntForKey: @"NSStyle"];
    } else {
        if (version >= 41) {
            // Alignment in the low four bits of the first word; the higher bits have
            // an unknown meaning.
            int alignmentWord, scaling, frameStyle;
            [coder decodeValuesOfObjCTypes: "iii", &alignmentWord, &scaling, &frameStyle];
            _imageAlignment = alignmentWord & 0xf;
            _imageScaling = scaling;
            _frameStyle = frameStyle;
        } else {
            // Alignment, scaling and frame style as three separate bytes.
            char alignment = 0, scaling = 0, frameStyle = 0;
            [coder decodeValuesOfObjCTypes: "c", &alignment];
            [coder decodeValuesOfObjCTypes: "c", &scaling];
            [coder decodeValuesOfObjCTypes: "c", &frameStyle];
            _imageAlignment = alignment;
            _imageScaling = scaling;
            _frameStyle = frameStyle;
        }
    }
    return self;
}

// An image cell's image is its object value: setting either sets both, the
// image is kept without being copied, and a nib stores it as the contents.
// Observed on macOS 26.7.3 and Mac OS X 10.14.4. Test: tests/appkit-image-cell-object-value.m
- initImageCell: (NSImage *) image {
    self = [super initImageCell: nil];
    if (self != nil && image != nil) {
        NS_EXTRA(NSCell, self)->_objectValue = [image retain];
        NS_EXTRA(NSCell, self)->_hasValidObjectValue = YES;
    }
    return self;
}

- (NSImage *) image {
    id value = [self objectValue];
    return [value isKindOfClass: [NSImage class]] ? value : nil;
}

- (void) setImage: (NSImage *) image {
    [self setObjectValue: image];
}

- (void) setObjectValue: (id<NSCopying>) value {
    if (![(id) value isKindOfClass: [NSImage class]]) {
        [super setObjectValue: value];
        return;
    }

    NSView *controlView = [self controlView];
    [controlView willChangeValueForKey: @"objectValue"];
    [(id) value retain];
    [NS_EXTRA(NSCell, self)->_objectValue release];
    NS_EXTRA(NSCell, self)->_objectValue = value;
    NS_EXTRA(NSCell, self)->_hasValidObjectValue = YES;
    [controlView didChangeValueForKey: @"objectValue"];

    if ([controlView respondsToSelector: @selector(updateCell:)])
        [controlView performSelector: @selector(updateCell:) withObject: self];
    else
        [controlView setNeedsDisplay: YES];
}

- (NSImageAlignment) imageAlignment {
    return _imageAlignment;
}

- (NSImageFrameStyle) imageFrameStyle {
    return _frameStyle;
}

- (NSImageScaling) imageScaling {
    return _imageScaling;
}

- (void) setImageAlignment: (NSImageAlignment) alignment {
    _imageAlignment = alignment;
}

- (void) setImageFrameStyle: (NSImageFrameStyle) frameStyle {
    _frameStyle = frameStyle;
}

- (void) setImageScaling: (NSImageScaling) imageScaling {
    _imageScaling = imageScaling;
}

// This function is duplicated in NSButtonCell, consolidate
static NSSize scaledImageSizeInFrameSize(NSSize imageSize, NSSize frameSize,
                                         NSImageScaling scaling)
{

    switch (scaling) {
    case NSImageScaleProportionallyDown: {
        CGFloat xscale = frameSize.width / imageSize.width;
        CGFloat yscale = frameSize.height / imageSize.height;
        CGFloat scale = MIN(1.0, MIN(xscale, yscale));

        imageSize.width *= scale;
        imageSize.height *= scale;

        return imageSize;
    }

    case NSImageScaleAxesIndependently:
        return frameSize;

    case NSImageScaleProportionallyUpOrDown: {
        CGFloat xscale = frameSize.width / imageSize.width;
        CGFloat yscale = frameSize.height / imageSize.height;
        CGFloat scale = MIN(xscale, yscale);

        imageSize.width *= scale;
        imageSize.height *= scale;

        return imageSize;
    }

    default:
    case NSImageScaleNone:
        return imageSize;
    }
}

- (NSRect) _scaledAndAlignedImageFrame: (NSRect) frame {
    NSSize imageSize = scaledImageSizeInFrameSize([[self image] size],
                                                  frame.size, _imageScaling);

    switch (_imageAlignment) {
    default:
    case NSImageAlignCenter:
        frame.origin.x += (frame.size.width / 2) - (imageSize.width / 2);
        frame.origin.y += (frame.size.height / 2) - (imageSize.height / 2);
        break;

    case NSImageAlignTop:
        frame.origin.x += (frame.size.width / 2) - (imageSize.width / 2);
        frame.origin.y += frame.size.height - imageSize.height;
        break;

    case NSImageAlignTopLeft:
        frame.origin.y += frame.size.height - imageSize.height;
        break;

    case NSImageAlignTopRight:
        frame.origin.x += frame.size.width - imageSize.width;
        frame.origin.y += frame.size.height - imageSize.height;
        break;

    case NSImageAlignLeft:
        frame.origin.y += (frame.size.height / 2) - (imageSize.height / 2);
        break;

    case NSImageAlignBottom:
        frame.origin.x += (frame.size.width / 2) - (imageSize.width / 2);
        break;

    case NSImageAlignBottomLeft:
        break;

    case NSImageAlignBottomRight:
        frame.origin.x += frame.size.width - imageSize.width;
        break;

    case NSImageAlignRight:
        frame.origin.x += frame.size.width - imageSize.width;
        frame.origin.y += (frame.size.height / 2) - (imageSize.height / 2);
        break;
    }

    frame.size = imageSize;
    return frame;
}

- (void) drawInteriorWithFrame: (NSRect) controlFrame
                        inView: (NSView *) control
{
    if ([self image] != nil) {

        CGContextRef ctx = [[NSGraphicsContext currentContext] graphicsPort];
        CGContextSaveGState(ctx);
        CGContextClipToRect(ctx, controlFrame);

        NSRect drawInRect = [self _scaledAndAlignedImageFrame: controlFrame];

        if ([control isFlipped]) {
            CGAffineTransform flip = {1, 0, 0, -1, 0, controlFrame.size.height};

            CGContextConcatCTM(ctx, flip);
        }

        NSImage *image = [self image];

        // QUIRK: an image view draws a template image in black at 50 % opacity (light appearance).
        // Evidence: black-box renders on macOS 10.14.4 (tier 2).
        // Test: tests/appkit-template-image-tint.m (test_quirk_template_image_colours)
        if ([image isKindOfClass: [NSImage class]] && [image isTemplate])
            [image _drawTemplateInRect: drawInRect
                                 color: [NSColor colorWithCalibratedWhite: 0.0 alpha: 0.5]
                              fraction: 1.0];
        else
            [image drawInRect: drawInRect
                     fromRect: NSZeroRect
                    operation: NSCompositeSourceOver
                     fraction: 1.0];

        CGContextRestoreGState(ctx);
    }
}

- (void) drawWithFrame: (NSRect) frame inView: (NSView *) control {

    switch (_frameStyle) {

    case NSImageFrameNone:
        break;

    case NSImageFramePhoto:;
        NSRect shadow = frame;
        shadow.size.height--;
        shadow.size.width--;
        shadow.origin.x++;
        [[NSColor darkGrayColor] set];
        NSRectFillUsingOperation(shadow, NSCompositeSourceOver);
        shadow.origin.x--;
        shadow.origin.y++;
        [[NSColor whiteColor] set];
        NSRectFillUsingOperation(shadow, NSCompositeCopy);
        frame = NSInsetRect(frame, 2, 2);
        break;

    case NSImageFrameGrayBezel:
        NSDrawGrayBezel(frame, frame);
        frame = NSInsetRect(frame, 2, 2);
        break;

    case NSImageFrameGroove:
        NSDrawGroove(frame, frame);
        frame = NSInsetRect(frame, 2, 2);
        break;

    case NSImageFrameButton:
        NSDrawButton(frame, frame);
        frame = NSInsetRect(frame, 2, 2);
        break;
    }

    [self drawInteriorWithFrame: frame inView: control];
}

@end
