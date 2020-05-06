#import <AppKit/CGEvent.h>
#import <X11/Xlib.h>

// Does inheriting from CGEvent make sense? The real CG doesn't use any
// objc and our CGEvent class was empty.
@interface X11Event : NSObject {
    XEvent _event;
}

- initWithXEvent: (XEvent) event;

@end
