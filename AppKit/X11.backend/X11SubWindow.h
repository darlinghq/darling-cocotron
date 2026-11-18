#import <CoreGraphics/CGSubWindow.h>
#import <QuartzCore/CAMetalLayerSurface.h>
#import <X11/Xlib.h>

@class X11Window;

@interface X11SubWindow : CGSubWindow <CAMetalLayerSurfaceProvider> {
    X11Window *_parent;
    Display *_display;
    Window _window;
    CGRect _drawableFrame; // in the parent's coordinate space, points
    BOOL _visible;
    BOOL _mapped;
    BOOL _allowsParentDrawable;
    BOOL _usingParentDrawable;
    BOOL _syncsToDisplay;
    // The child windows Metal layers present to, by layer (not retained): Window values.
    NSMapTable *_metalWindows;
}

- initWithParentWindow: (X11Window *) parent frame: (CGRect) frame;

// What the layer context sizes its GL viewport from: without these, the
// CGSubWindow defaults (1.0 and CGSizeZero) would give a scaled subwindow a
// viewport that shows a fraction of it.
- (CGFloat) backingScaleFactor;
- (CGSize) drawablePixelSize;

@end
