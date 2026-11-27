/* AppKit's Pocket backend: a window on the phone host.

 Permission is hereby granted, free of charge, to any person obtaining a copy of
 this software and associated documentation files (the "Software"), to deal in
 the Software without restriction, including without limitation the rights to
 use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
 of the Software, and to permit persons to whom the Software is furnished to do
 so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE. */

#import "PocketWindow.h"
#import "PocketDisplay.h"
#import <AppKit/NSApplication.h>
#import <AppKit/NSWindow.h>
#import <Onyx2D/O2Context_builtin_FT.h>
#import <Onyx2D/O2Surface.h>
#include <math.h>
#include <string.h>

// NSView replaces the user CTM whenever it locks focus, so the scale goes in
// the device transform, with Onyx2D's bottom-left to top-left flip.
@interface PocketDrawingContext : O2Context_builtin_FT
- (id) initWithSurface: (O2Surface *) surface logicalSize: (NSSize) logicalSize;
@end

@implementation PocketDrawingContext
- (id) initWithSurface: (O2Surface *) surface logicalSize: (NSSize) logicalSize {
    if ((self = [super initWithSurface: surface flipped: NO]) != nil) {
        CGFloat sx = O2SurfaceGetWidth(surface) / logicalSize.width;
        CGFloat sy = O2SurfaceGetHeight(surface) / logicalSize.height;
        _userToDeviceTransform = O2AffineTransformMake(sx, 0, 0, -sy, 0, O2SurfaceGetHeight(surface));
        O2ContextSetCTM(self, O2AffineTransformIdentity);
    }
    return self;
}
@end

@implementation PocketWindow

- (instancetype) initWithDelegate: (NSWindow *) delegate {
    if ((self = [super init]) == nil)
        return nil;
    _delegate = delegate;
    _level = [delegate level];
    _styleMask = [delegate styleMask];
    _isOpaque = [delegate isOpaque];
    _deviceDictionary = [NSMutableDictionary new];
    _display = [(PocketDisplay *) [NSDisplay currentDisplay] retain];
    _frame = [delegate frame];
    _frame.size.width = MAX(_frame.size.width, 1.0);
    _frame.size.height = MAX(_frame.size.height, 1.0);
    [_display windowCreated: self];
    return self;
}

- (void) dealloc {
    [self invalidate];
    [_display release];
    [_deviceDictionary release];
    [_title release];
    [super dealloc];
}

- (void) invalidate {
    if (_invalidated)
        return;
    _invalidated = YES;
    [_context release];
    _context = nil;
    [_delegate platformWindowDidInvalidateCGContext: self];
    _delegate = nil;
    struct pocket_window_id message = {[self number]};
    [_display send: POCKET_DESTROY bytes: &message length: sizeof(message)];
    [_display windowDestroyed: self];
}

- (void) setDelegate: (id) delegate { _delegate = delegate; }
- (NSWindow *) delegate { return _delegate; }
- (void) syncDelegateProperties {}
- (uint32_t) number { return (uint32_t) [self windowNumber]; }
- (BOOL) isVisible { return _visible; }
- (int) level { return _level; }
- (O2Rect) frame { return _frame; }

#pragma mark - What the host knows

// The window in the screen's pixels, from the top left.
- (void) sendState {
    if (_invalidated)
        return;
    CGFloat scale = [_display scale];
    NSRect screen = [_display screenFrame];
    struct pocket_window message = {
        .window = [self number],
        .x = (int32_t) lround(_frame.origin.x * scale),
        .y = (int32_t) lround((NSMaxY(screen) - NSMaxY(_frame)) * scale),
        .width = (int32_t) lround(_frame.size.width * scale),
        .height = (int32_t) lround(_frame.size.height * scale),
        .flags = (_visible ? POCKET_WINDOW_VISIBLE : 0) | (_isOpaque ? POCKET_WINDOW_OPAQUE : 0),
        .level = _level,
    };
    [_display send: POCKET_WINDOW bytes: &message length: sizeof(message)];
}

- (void) show {
    BOOL wasVisible = _visible;
    _visible = YES;
    [_display windowRaised: self];
    if (!wasVisible) {
        [self sendState];
        [_delegate platformWindowActivated: self displayIfNeeded: YES];
    }
}

- (void) hide {
    if (!_visible)
        return;
    _visible = NO;
    [self sendState];
}

- (void) showWindowWithoutActivation { [self show]; }
- (void) showWindowForAppActivation: (NSRect) frame { [self show]; }
- (void) hideWindowForAppDeactivation: (NSRect) frame {}
- (void) hideWindow { [self hide]; }

- (void) sheetOrderFrontFromFrame: (NSRect) frame aboveWindow: (CGWindow *) aboveWindow {
    [self setFrame: frame];
    [self show];
}

- (void) sheetOrderOutToFrame: (NSRect) frame { [self hide]; }

- (void) placeAboveWindow: (NSInteger) otherNumber { [self show]; }

- (void) placeBelowWindow: (NSInteger) otherNumber {
    [self show];
    [_display windowLowered: self];
}

- (void) makeKey { [self show]; }
- (void) makeMain {}
- (void) captureEvents {}
- (void) miniaturize { [self hide]; }
- (void) deminiaturize { [self show]; }
- (BOOL) isMiniaturized { return NO; }
- (void) flashWindow {}

- (NSUInteger) styleMask { return _styleMask; }
- (void) setStyleMask: (NSUInteger) mask { _styleMask = mask; }

- (void) setLevel: (int) value {
    _level = value;
    [self sendState];
}

- (void) setTitle: (NSString *) title {
    [_title release];
    _title = [title copy];
}

- (void) setOpaque: (BOOL) value {
    _isOpaque = value;
    [self sendState];
}

- (void) setAlphaValue: (CGFloat) value {}
- (void) setHasShadow: (BOOL) value {}
- (CGLContextObj) cglContext { return NULL; }

- (void) addEntriesToDeviceDictionary: (NSDictionary *) entries {
    [_deviceDictionary addEntriesFromDictionary: entries];
}

// Layers and OpenGL views draw into the window's own content here.
- (CGSubWindow *) createSubWindowWithFrame: (CGRect) frame { return nil; }

- (void) setFrame: (O2Rect) frame {
    frame.size.width = MAX(frame.size.width, 1.0);
    frame.size.height = MAX(frame.size.height, 1.0);
    if (NSEqualRects(frame, _frame))
        return;
    if (!NSEqualSizes(frame.size, _frame.size)) {
        [_context release];
        _context = nil;
        [_delegate platformWindowDidInvalidateCGContext: self];
    }
    _frame = frame;
    [self sendState];
}

// The screen's scale or size changed.
- (void) screenChanged {
    [_context release];
    _context = nil;
    [_delegate platformWindowDidInvalidateCGContext: self];
    [self sendState];
    [_delegate display];
}

- (NSPoint) mouseLocationOutsideOfEventStream {
    NSPoint global = [_display mouseLocation];
    return NSMakePoint(global.x - _frame.origin.x, global.y - _frame.origin.y);
}

- (CGFloat) backingScaleFactor { return [_display scale]; }

#pragma mark - Drawing

- (O2Context *) cgContext {
    if (_context == nil) {
        CGFloat scale = [_display scale];
        NSSize logical = NSMakeSize(ceil(_frame.size.width), ceil(_frame.size.height));
        size_t width = (size_t) ceil(logical.width * scale);
        size_t height = (size_t) ceil(logical.height * scale);
        if (width < 1 || height < 1 || width > 16384 || height > 16384) {
            NSLog(@"Pocket backend: a %zux%zu window buffer is too large", width, height);
            return nil;
        }
        O2ColorSpaceRef colorSpace = O2ColorSpaceCreateDeviceRGB();
        O2Surface *surface = [[O2Surface alloc] initWithBytes: NULL
                                                        width: width
                                                       height: height
                                             bitsPerComponent: 8
                                                  bytesPerRow: 0
                                                   colorSpace: colorSpace
                                                   bitmapInfo: kO2ImageAlphaPremultipliedFirst | kO2BitmapByteOrder32Little];
        O2ColorSpaceRelease(colorSpace);
        _context = [[PocketDrawingContext alloc] initWithSurface: surface logicalSize: logical];
        [surface release];
    }
    return _context;
}

- (void) flushBuffer {
    if (_context != nil)
        O2ContextFlush(_context);
}

@end
