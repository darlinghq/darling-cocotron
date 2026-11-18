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
    // device pixels. X rejects a zero-sized window.
    O2Rect device = [parent deviceRect: frame];
    device.size.width = fmax(device.size.width, 1.0);
    device.size.height = fmax(device.size.height, 1.0);
    _window = XCreateSimpleWindow(_display, [parent windowHandle],
                                  device.origin.x, device.origin.y,
                                  device.size.width, device.size.height, 0, 0,
                                  0 /* border_width, border, background */
    );
    // The application paints every pixel of a subwindow, so the server must not
    // clear it to a background first.
    XSetWindowBackgroundPixmap(_display, _window, None);

    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(parentBackingDidFlush:)
                                                 name: X11WindowBackingDidFlushNotification
                                               object: parent];
    [self show];
    return self;
}

- (void) parentBackingDidFlush: (NSNotification *) note {
    [[NSNotificationCenter defaultCenter]
            postNotificationName: CGSubWindowBackdropDidChangeNotification
                          object: self];
}

// The parent's drawn pixels beneath the subwindow; a child window is a plain
// opaque X window, so the layer tree blends against these itself.
- (CGImageRef) createBackdropImage {
    return (CGImageRef) [_parent createBackingImageInDeviceRect: [_parent deviceRect: _drawableFrame]];
}

- (void) dealloc {
    // the child windows go with this one
    [_metalWindows release];
    [[NSNotificationCenter defaultCenter] removeObserver: self];
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
    // A Metal layer's window is a child of this one, which has to stay mapped for it to show.
    BOOL coversParent =
            _allowsParentDrawable && _visible && [_metalWindows count] == 0 &&
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
    device.size.width = fmax(device.size.width, 1.0);
    device.size.height = fmax(device.size.height, 1.0);

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


// A Metal layer's surface is a child window of this one, where the layer is in the tree.

// The layer's frame (points, lower left origin, relative to this window's content) in the
// pixels of the child window, whose origin is at the upper left.
- (O2Rect) metalDeviceRectForFrame: (CGRect) frame {
    CGFloat scale = [_parent backingScaleFactor];
    CGFloat top = _drawableFrame.size.height - CGRectGetMaxY(frame);
    O2Rect device;
    device.origin.x = floor(frame.origin.x * scale + 0.5);
    device.origin.y = floor(top * scale + 0.5);
    device.size = [_parent deviceSize: frame.size];
    device.size.width = fmax(device.size.width, 1.0);
    device.size.height = fmax(device.size.height, 1.0);
    return device;
}

- (CGSize) pixelSizeForMetalSurfaceFrame: (CGRect) frame {
    O2Rect device = [self metalDeviceRectForFrame: frame];
    return CGSizeMake(device.size.width, device.size.height);
}

- (void) describeMetalWindow: (Window) window
                      device: (O2Rect) device
                     surface: (CANativeSurface *) surface {
    surface->kind = CANativeSurfaceKindXlib;
    surface->display = _display;
    surface->window = window;
    surface->surface = NULL;
    surface->pixelSize = CGSizeMake(device.size.width, device.size.height);
}

- (BOOL) createMetalSurface: (CANativeSurface *) surface
                   forLayer: (CAMetalLayer *) layer
                      frame: (CGRect) frame {
    if (_metalWindows == nil)
        _metalWindows = [[NSMapTable mapTableWithWeakToStrongObjects] retain];
    if ([_metalWindows objectForKey: layer] != nil)
        return [self updateMetalSurface: surface forLayer: layer frame: frame];

    O2Rect device = [self metalDeviceRectForFrame: frame];
    Window window = XCreateSimpleWindow(_display, _window, device.origin.x, device.origin.y,
                                        device.size.width, device.size.height, 0, 0, 0);
    if (window == None)
        return NO;
    // the layer's frames cover every pixel
    XSetWindowBackgroundPixmap(_display, window, None);
    XMapWindow(_display, window);
    // the Vulkan surface is made for a window the server knows
    XSync(_display, False);

    [_metalWindows setObject: [NSNumber numberWithUnsignedLong: window] forKey: layer];
    [self describeMetalWindow: window device: device surface: surface];
    return YES;
}

- (BOOL) updateMetalSurface: (CANativeSurface *) surface
                   forLayer: (CAMetalLayer *) layer
                      frame: (CGRect) frame {
    NSNumber *handle = [_metalWindows objectForKey: layer];
    if (handle == nil)
        return NO;

    Window window = [handle unsignedLongValue];
    O2Rect device = [self metalDeviceRectForFrame: frame];
    XMoveResizeWindow(_display, window, device.origin.x, device.origin.y,
                      device.size.width, device.size.height);
    [self describeMetalWindow: window device: device surface: surface];
    return YES;
}

- (void) destroyMetalSurfaceForLayer: (CAMetalLayer *) layer {
    NSNumber *handle = [_metalWindows objectForKey: layer];
    if (handle == nil)
        return;
    XDestroyWindow(_display, [handle unsignedLongValue]);
    [_metalWindows removeObjectForKey: layer];
}

@end
