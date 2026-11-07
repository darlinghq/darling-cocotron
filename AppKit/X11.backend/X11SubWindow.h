#import <CoreGraphics/CGSubWindow.h>
#import <X11/Xlib.h>

@class X11Window;

@interface X11SubWindow : CGSubWindow {
    X11Window *_parent;
    Display *_display;
    Window _window;
    CGRect _drawableFrame; // in the parent's X coordinates
    BOOL _visible;
    BOOL _mapped;
    BOOL _allowsParentDrawable;
    BOOL _usingParentDrawable;
    BOOL _syncsToDisplay;
}

- initWithParentWindow: (X11Window *) parent frame: (CGRect) frame;

@end
