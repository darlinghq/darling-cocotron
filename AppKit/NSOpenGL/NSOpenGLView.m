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

#import <AppKit/NSOpenGLContext.h>
#import <AppKit/NSOpenGLPixelFormat.h>
#import <AppKit/NSOpenGLView.h>
#import <AppKit/NSRaise.h>
#import <Foundation/NSKeyedArchiver.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSNull.h>

#include <math.h>
@interface NSOpenGLContext (DrawableScale)
- (NSSize) _drawablePixelSize;
- (BOOL) _drawableAttachmentSucceeded;
@end

@implementation NSOpenGLView

+ (NSOpenGLPixelFormat *) defaultPixelFormat {
    NSOpenGLPixelFormatAttribute attributes[] = {0};

    return [[[NSOpenGLPixelFormat alloc] initWithAttributes: attributes]
            autorelease];
}

- (id) initWithFrame: (NSRect) frame
         pixelFormat: (NSOpenGLPixelFormat *) pixelFormat
{
    [super initWithFrame: frame];

    _pixelFormat = [pixelFormat retain];
    _context = nil;
    _lastDrawablePixelSize = NSZeroSize;

    return self;
}

- (id) initWithFrame: (NSRect) frame {
    [super initWithFrame: frame];

    _pixelFormat = [[[self class] defaultPixelFormat] retain];
    _context = nil;
    _lastDrawablePixelSize = NSZeroSize;

    return self;
}

- (id) initWithCoder: (NSCoder *) coder {
    [super initWithCoder: coder];

    if ([coder allowsKeyedCoding])
        _pixelFormat = [[coder decodeObjectForKey: @"NSPixelFormat"] retain];
    else
        NSUnimplementedMethod();

    return self;
}

- (void) dealloc {
    [_focusContexts release];
    [_pixelFormat release];
    [_context release];
    [super dealloc];
}

- (NSOpenGLPixelFormat *) pixelFormat {
    return _pixelFormat;
}

- (NSOpenGLContext *) openGLContext {
    if (_context == nil) {
        _context = [[NSOpenGLContext alloc] initWithFormat: _pixelFormat
                                              shareContext: nil];
        [_context setView: self];
        _needsReshape = YES;
    }

    return _context;
}

- (void) _setWindow: (NSWindow *) window {
    if ([self window] != window) [_context clearDrawable];
    [super _setWindow: window];
    [_context setView: self];
}

- (void) setPixelFormat: (NSOpenGLPixelFormat *) pixelFormat {
    pixelFormat = [pixelFormat retain];
    [_pixelFormat release];
    _pixelFormat = pixelFormat;
}

- (void) setOpenGLContext: (NSOpenGLContext *) context {
    [_context clearDrawable];
    context = [context retain];
    [_context release];
    _context = context;
    _lastDrawablePixelSize = NSZeroSize;
    [_context setView: self];
    _needsReshape = YES;
}

- (void) update {
    // we don't want to create the context if it doesn't exist
    [_context update];
}

- (void) reshape {
    // do nothing
}

- (void) prepareOpenGL {
    // do nothing
}

- (BOOL) isOpaque {
    return YES;
}

- (void) viewDidHide {
    // setView:self is a no-op when the view is unchanged.
    [_context update];
}

- (void) viewDidUnhide {
    // setView:self is a no-op when the view is unchanged.
    [_context update];
}

- (void) lockFocus {
    [super lockFocus];
    NSOpenGLContext *context = [self openGLContext];
    if (!_focusContexts) _focusContexts = [NSMutableArray new];
    // The paired unlock must use the context we locked, even if application
    // prepareOpenGL/reshape replaces it or recursively focuses another view.
    [_focusContexts addObject: context ?: (id)[NSNull null]];
    CGLLockContext([context CGLContextObj]);
    @try {
        [context setView: self];
        [context makeCurrentContext];
        if (_context == context && [context view] == self && [context _drawableAttachmentSucceeded] &&
            [NSOpenGLContext currentContext] == context &&
            CGLGetCurrentContext() == [context CGLContextObj]) {
            NSSize pixels = [context _drawablePixelSize];
            if (!NSEqualSizes(pixels, _lastDrawablePixelSize)) {
                _lastDrawablePixelSize = pixels;
                _needsReshape = YES;
            }
            if (_needsReshape) {
                _needsReshape = NO;
                [self reshape];
            }
        }
    } @catch (id exception) {
        if (_context == context) _needsReshape = YES;
        [self unlockFocus];
        @throw;
    }
}

- (void) unlockFocus {
    id context = [[_focusContexts lastObject] retain];
    if (context != nil) [_focusContexts removeLastObject];
    if (context != [NSNull null]) CGLUnlockContext([context CGLContextObj]);
    [context release];
    [super unlockFocus];
}

- (void) clearGLContext {
    [_context clearDrawable];
    [_context release];
    _context = nil;
    _lastDrawablePixelSize = NSZeroSize;
}

// Backing coordinates belong to this GL drawable, whose preferred scale can
// differ from its parent surface. Map full bounds to the exact allocation.
- (BOOL) _drawableSize: (NSSize *) pixels logicalSize: (NSSize *) logical {
    if ([_context view] != self) return NO;
    *pixels = [_context _drawablePixelSize]; *logical = [self bounds].size;
    return isfinite(pixels->width) && isfinite(pixels->height) &&
        pixels->width > 0 && pixels->height > 0 &&
        floor(pixels->width) == pixels->width && floor(pixels->height) == pixels->height &&
        isfinite(logical->width) && isfinite(logical->height) &&
        logical->width > 0 && logical->height > 0;
}
- (NSRect) convertRectToBacking: (NSRect) rect {
    NSSize pixels, logical;
    if (![self _drawableSize: &pixels logicalSize: &logical]) return [super convertRectToBacking: rect];
    // Divide first so full bounds map exactly to integral allocation dimensions
    // (71 * (124 / 71) can otherwise become 123.999..., then truncate to 123).
    return NSMakeRect(rect.origin.x / logical.width * pixels.width, rect.origin.y / logical.height * pixels.height,
        rect.size.width / logical.width * pixels.width, rect.size.height / logical.height * pixels.height);
}
- (NSRect) convertRectFromBacking: (NSRect) rect {
    NSSize pixels, logical;
    if (![self _drawableSize: &pixels logicalSize: &logical]) return [super convertRectFromBacking: rect];
    return NSMakeRect(rect.origin.x / pixels.width * logical.width, rect.origin.y / pixels.height * logical.height,
        rect.size.width / pixels.width * logical.width, rect.size.height / pixels.height * logical.height);
}

// -setFrame: goes through both of these.
- (void) setFrameOrigin: (NSPoint) origin {
    [super setFrameOrigin: origin];
    [self update];
}

- (void) setFrameSize: (NSSize) size {
    [super setFrameSize: size];
    _needsReshape = YES;
    [self update];
}
@end
