/* Copyright (c) 2008 Johannes Fortmann

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

#import <CoreGraphics/CGWindow.h>
#import <GL/glx.h>
#import <Onyx2D/O2Geometry.h>
#import <OpenGL/CGLInternal.h>
#import <X11/Xlib.h>
#import <X11/Xresource.h>
#import <X11/Xlocale.h>

@class X11Display, CAWindowOpenGLContext, NSWindow, O2Context;

@interface X11Window : CGWindow {
    int _level; // TODO: care about this value
    Display *_display;
    XVisualInfo *_visualInfo;
    Window _window;
    CGLContextObj _cglContext;
    CGLWindowRef _cglWindow;
    CAWindowOpenGLContext *_caContext;

    NSWindow *_delegate;
    CGSBackingStoreType _backingType; // stored, but ignored
    O2Context *_context;

    NSMutableDictionary *_deviceDictionary;
    O2Rect _frame;
    NSUInteger _styleMask;
    BOOL _mapped;
    CGPoint _lastMotionPos;
    BOOL _isModal;
    BOOL _isOpaque;
    BOOL _hasShadow;

@public
    XIC _xic;
}

+ (void) removeDecorationForWindow: (Window) w onDisplay: (Display *) dpy;
- (instancetype) initWithDelegate: (NSWindow *) delegate;
- (O2Rect) frame;
- (Visual *) visual;
- (Drawable) drawable;
- (NSPoint) transformPoint: (NSPoint) pos;
- (O2Rect) transformFrame: (O2Rect) frame;

- (Window) windowHandle;

- (void) frameChanged;
- (void) setLastKnownCursorPosition: (CGPoint) point;

- (void) setStyleMaskInternal: (NSUInteger) styleMask force: (BOOL) force;

@end

void CGNativeBorderFrameWidthsForStyle(NSUInteger styleMask, CGFloat *top,
                                       CGFloat *left, CGFloat *bottom,
                                       CGFloat *right);
