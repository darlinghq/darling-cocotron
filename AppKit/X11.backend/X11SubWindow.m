#import "X11SubWindow.h"
#import "X11Display.h"
#import "X11Window.h"
#import <AppKit/NSWindow.h>

@implementation X11SubWindow

- (CGRect) convertFrame: (CGRect) frame {
    CGFloat top, left, bottom, right;
    CGNativeBorderFrameWidthsForStyle([_parent styleMask], &top, &left, &bottom,
                                      &right);
    frame.origin.y = [_parent frame].size.height - CGRectGetMaxY(frame);
    frame.origin.y -= top;
    frame.origin.x -= left;
    return frame;
}

- (id) initWithParentWindow: (X11Window *) parent frame: (CGRect) frame {
    // Owners such as NSOpenGLContext can keep a subwindow after its NSWindow
    // has gone, and the subwindow still asks its parent for its geometry.
    _parent = [parent retain];
    frame = [self convertFrame: frame];
    _drawableFrame = frame;
    _syncsToDisplay = YES;

    _display = [(X11Display *) [NSDisplay currentDisplay] display];

    // _drawableFrame is in points; a child window is positioned in the parent's
    // device pixels.
    O2Rect device = [parent deviceRect: frame];
    _window = XCreateSimpleWindow(_display, [parent windowHandle],
                                  device.origin.x, device.origin.y,
                                  device.size.width, device.size.height, 0, 0,
                                  0 /* border_width, border, background */
    );
    // The application paints every pixel of a subwindow, so the server must not
    // clear it to a background first.
    XSetWindowBackgroundPixmap(_display, _window, None);

    [self show];
    return self;
}

- (void) dealloc {
    if (_usingParentDrawable)
        [_parent releaseLayerDrawable: self];
    XDestroyWindow(_display, _window);
    [_parent release];
    [super dealloc];
}

- (void *) nativeWindow {
    return (void *) _window;
}

- (void) setAllowsParentDrawable: (BOOL) allowed {
    _allowsParentDrawable = allowed;
}

- (void) setSyncsToDisplay: (BOOL) syncs {
    if (syncs == _syncsToDisplay)
        return;
    _syncsToDisplay = syncs;
    if (_usingParentDrawable)
        [_parent setLayerDrawable: self syncsToDisplay: syncs];
}

// A borderless window whose content is a single full-size layer tree, such as
// a game's Metal view, presents that tree in the window itself rather than in
// a child window stacked on top. A compositor can then show the application's
// frames without compositing them (and drive variable refresh by them), which
// it cannot do for a child window. Any other subwindow keeps its own drawable.
- (void *) sharedCGLWindow {
    CGSize parentSize = [_parent frame].size;
    BOOL coversParent =
            _allowsParentDrawable && _visible &&
            !([_parent styleMask] & NSWindowStyleMaskTitled) &&
            CGRectEqualToRect(_drawableFrame,
                              CGRectMake(0, 0, parentSize.width, parentSize.height));
    void *surface = coversParent ? [_parent layerDrawableFor: self] : NULL;
    BOOL usingParent = surface != NULL;

    if (usingParent != _usingParentDrawable) {
        _usingParentDrawable = usingParent;
        if (usingParent)
            [_parent acquireLayerDrawable: self syncsToDisplay: _syncsToDisplay];
        else
            [_parent releaseLayerDrawable: self];
    }
    [self updateMapping];
    return surface;
}

// The subwindow is shown while it is visible and draws into its own drawable.
- (void) updateMapping {
    BOOL mapped = _visible && !_usingParentDrawable;
    if (mapped == _mapped)
        return;
    _mapped = mapped;
    if (mapped)
        XMapWindow(_display, _window);
    else
        XUnmapWindow(_display, _window);
}

- (void) show {
    _visible = YES;
    [self updateMapping];
}

- (void) hide {
    _visible = NO;
    [self updateMapping];
}

- (void) setFrame: (CGRect) frame {
    frame = [self convertFrame: frame];
    _drawableFrame = frame;

    O2Rect device = [_parent deviceRect: frame];

    XMoveResizeWindow(_display, _window, device.origin.x, device.origin.y,
                      device.size.width, device.size.height);
}

// A subwindow draws at the display's scale, like the window that holds it.
- (CGFloat) backingScaleFactor {
    return [_parent backingScaleFactor];
}

// The pixel size of this window's own drawable (not its parent's), whole pixels
// as the OpenGL view requires.
- (CGSize) drawablePixelSize {
    NSSize device = [_parent deviceSize: _drawableFrame.size];
    return CGSizeMake(device.width, device.height);
}

@end
