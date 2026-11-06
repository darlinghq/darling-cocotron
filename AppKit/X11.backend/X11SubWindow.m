#import "X11SubWindow.h"
#import "X11Display.h"
#import "X11Window.h"

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

    _display = [(X11Display *) [NSDisplay currentDisplay] display];

    _window = XCreateSimpleWindow(_display, [parent windowHandle],
                                  frame.origin.x, frame.origin.y,
                                  frame.size.width, frame.size.height, 0, 0,
                                  0 /* border_width, border, background */
    );

    [self show];
    return self;
}

- (void) dealloc {
    XDestroyWindow(_display, _window);
    [_parent release];
    [super dealloc];
}

- (void *) nativeWindow {
    return (void *) _window;
}

- (void) show {
    XMapWindow(_display, _window);
}

- (void) hide {
    XUnmapWindow(_display, _window);
}

- (void) setFrame: (CGRect) frame {
    frame = [self convertFrame: frame];

    XMoveResizeWindow(_display, _window, frame.origin.x, frame.origin.y,
                      frame.size.width, frame.size.height);
}

@end
