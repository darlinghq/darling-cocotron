#import "X11Cursor.h"
#import "X11Display.h"
#import <AppKit/NSGraphicsContext.h>
#import <string.h>

@implementation X11Cursor

@synthesize cursor = _cursor;

- (id) initWithShape: (unsigned int) shape {
    X11Display *d = (X11Display *) [NSDisplay currentDisplay];
    Display *display = [d display];

    _cursor = XCreateFontCursor(display, shape);

    return self;
}

- (id) initWithName: (const char *) name {
    X11Display *d = (X11Display *) [NSDisplay currentDisplay];
    Display *display = [d display];

    _cursor = XcursorLibraryLoadCursor(display, name);

    if (_cursor == None) {
        _cursor = XcursorLibraryLoadCursor(display, "left_ptr");
    }

    return self;
}

- (id) initWithImage: (NSImage *) image hotPoint: (NSPoint) hotPoint {
    X11Display *d = (X11Display *) [NSDisplay currentDisplay];
    Display *display = [d display];

    const size_t width = image.size.width;
    const size_t height = image.size.height;

    XcursorImage *ximage = XcursorImageCreate(width, height);
    if (!ximage) {
        return [self initWithName: "left_ptr"];
    }

    ximage->xhot = hotPoint.x;
    ximage->yhot = hotPoint.y;

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(
        NULL, width, height, 8, 0, colorSpace,
        kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
    CGColorSpaceRelease(colorSpace);

    @autoreleasepool {
        NSGraphicsContext *graphicsContext =
            [NSGraphicsContext graphicsContextWithGraphicsPort: context
                                                       flipped: NO];

        [NSGraphicsContext saveGraphicsState];
        [NSGraphicsContext setCurrentContext: graphicsContext];

        [image drawInRect: NSMakeRect(0, 0, width, height)
                 fromRect: NSZeroRect
                operation: NSCompositeCopy
                 fraction: 1.0];

        [NSGraphicsContext restoreGraphicsState];
    }

    const uint8_t *rowBytes = CGBitmapContextGetData(context);
    const size_t bytesPerRow = CGBitmapContextGetBytesPerRow(context);

    for (int row = 0; row < height; row++, rowBytes += bytesPerRow) {
        for (int column = 0; column < width; column++) {
            memcpy(ximage->pixels + row * width, &rowBytes[column * 4],
                   bytesPerRow);
        }
    }

    CGContextRelease(context);

    _cursor = XcursorImageLoadCursor(display, ximage);
    if (_cursor == None) {
        _cursor = XcursorLibraryLoadCursor(display, "left_ptr");
    }
    return self;
}

- (id) initBlank {
    X11Display *d = (X11Display *) [NSDisplay currentDisplay];
    Display *display = [d display];

    static const char data[1] = {0};

    Pixmap blank;
    XColor dummy;

    blank =
        XCreateBitmapFromData(display, DefaultRootWindow(display), data, 1, 1);
    if (blank != None) {
        _cursor =
            XCreatePixmapCursor(display, blank, blank, &dummy, &dummy, 0, 0);
        XFreePixmap(display, blank);
    } else {
        _cursor = None;
    }

    return self;
}

- (id) init {
    X11Display *d = (X11Display *) [NSDisplay currentDisplay];
    Display *display = [d display];

    _cursor = XcursorLibraryLoadCursor(display, "left_ptr");
    return self;
}

- (void) dealloc {
    X11Display *d = (X11Display *) [NSDisplay currentDisplay];
    Display *display = [d display];

    if (display) {
        XFreeCursor(display, _cursor);
    }
    [super dealloc];
}

@end
