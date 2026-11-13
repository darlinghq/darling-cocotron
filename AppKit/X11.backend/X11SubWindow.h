#import <CoreGraphics/CGSubWindow.h>
#import <X11/Xlib.h>

@class X11Window;

@interface X11SubWindow : CGSubWindow {
    X11Window *_parent;
    Display *_display;
    Window _window;
    CGRect _drawableFrame; // in the parent's coordinate space, points
    BOOL _visible;
    BOOL _mapped;
    BOOL _allowsParentDrawable;
    BOOL _usingParentDrawable;
    BOOL _syncsToDisplay;
}

- initWithParentWindow: (X11Window *) parent frame: (CGRect) frame;

// What the layer context sizes its GL viewport from: without these, the
// CGSubWindow defaults (1.0 and CGSizeZero) would give a scaled subwindow a
// viewport that shows a fraction of it.
- (CGFloat) backingScaleFactor;
- (CGSize) drawablePixelSize;

@end
