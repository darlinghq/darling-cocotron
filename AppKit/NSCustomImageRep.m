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
#import <AppKit/NSCustomImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSView.h>

@interface NSCustomImageRepFocusView : NSView {
    BOOL _handlerFlipped;
}
- (instancetype) initWithFlipped: (BOOL) flipped;
@end

@implementation NSCustomImageRepFocusView
- (instancetype) initWithFlipped: (BOOL) flipped {
    if ((self = [super initWithFrame: NSZeroRect]))
        _handlerFlipped = flipped;
    return self;
}
- (BOOL) isFlipped { return _handlerFlipped; }
@end

@implementation NSCustomImageRep

- (instancetype) initWithSize: (NSSize) size
                     flipped: (BOOL) flipped
              drawingHandler: (BOOL (^)(NSRect)) handler {
    if ((self = [super init])) {
        [self setSize: size];
        _drawingHandler = [handler copy];
        _drawingHandlerFlipped = flipped;
    }
    return self;
}

- (BOOL (^)(NSRect)) drawingHandler {
    return _drawingHandler;
}

- (id) copyWithZone: (NSZone *) zone {
    NSCustomImageRep *result = [super copyWithZone: zone];
    // NSImageRep uses NSCopyObject; balance this subclass's copied pointer.
    result->_drawingHandler = [_drawingHandler copy];
    return result;
}

- (void) dealloc {
    [_drawingHandler release];
    [super dealloc];
}

- initWithDrawSelector: (SEL) selector delegate: delegate {
    _drawSelector = selector;
    _delegate = delegate;
    return self;
}

- (SEL) drawSelector {
    return _drawSelector;
}

- delegate {
    return _delegate;
}

- (BOOL) draw {
    if (_drawingHandler != nil) {
        NSGraphicsContext *context = [NSGraphicsContext currentContext];
        if (context == nil)
            return NO;
        NSSize size = [self size];
        BOOL flip = [context isFlipped] != _drawingHandlerFlipped;
        NSCustomImageRepFocusView *focus = [[[NSCustomImageRepFocusView alloc]
                initWithFlipped: _drawingHandlerFlipped] autorelease];
        [NSGraphicsContext saveGraphicsState];
        [[context focusStack] addObject: focus];
        @try {
            if (flip) {
                CGContextTranslateCTM([context graphicsPort], 0, size.height);
                CGContextScaleCTM([context graphicsPort], 1, -1);
            }
            return _drawingHandler(NSMakeRect(0, 0, size.width, size.height));
        } @finally {
            [[context focusStack] removeLastObject];
            [NSGraphicsContext restoreGraphicsState];
        }
    }
    [_delegate performSelector: _drawSelector withObject: self];
    return YES;
}

@end
