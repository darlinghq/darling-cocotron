#import "X11Cursor.h"
#import "X11Display.h"
#import <AppKit/NSGraphicsContext.h>
#import <string.h>
#include <math.h>

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

    if (_cursor == None)
        _cursor = XcursorLibraryLoadCursor(display, "left_ptr");

    return self;
}

- (id) initWithImage: (NSImage *) image hotPoint: (NSPoint) hotPoint {
    X11Display *d = (X11Display *) [NSDisplay currentDisplay];
    Display *display = [d display];

    // Xcursor wants device pixels. Rasterize at the backing scale rather than
    // stretching a 1x image, so the cursor stays sharp on a 2x display instead of
    // being upscaled. The hotspot scales with it.
    CGFloat scale = [(X11Display *) [NSDisplay currentDisplay] backingScale];
    const CGFloat logicalWidth = image.size.width, logicalHeight = image.size.height;
    const size_t width = (size_t) fmax(floor(logicalWidth * scale + 0.5), 1.0);
    const size_t height = (size_t) fmax(floor(logicalHeight * scale + 0.5), 1.0);

    XcursorImage *ximage = XcursorImageCreate(width, height);
    if (!ximage)
        return [self initWithName: "left_ptr"];

    ximage->xhot = (int) fmin(floor(hotPoint.x * scale), (CGFloat)width - 1);
    ximage->yhot = (int) fmin(floor(hotPoint.y * scale), (CGFloat)height - 1);

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(
            NULL, width, height, 8, 0, colorSpace,
            kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
    CGColorSpaceRelease(colorSpace);
    if (context == NULL) {
        XcursorImageDestroy(ximage);
        return [self initWithName: "left_ptr"];
    }

    @autoreleasepool {
        NSGraphicsContext *graphicsContext =
                [NSGraphicsContext graphicsContextWithGraphicsPort: context
                                                           flipped: NO];

        [NSGraphicsContext saveGraphicsState];
        [NSGraphicsContext setCurrentContext: graphicsContext];
        CGContextScaleCTM(context, width / logicalWidth, height / logicalHeight);

        [image drawInRect: NSMakeRect(0, 0, logicalWidth, logicalHeight)
                 fromRect: NSZeroRect
                operation: NSCompositeCopy
                 fraction: 1.0];

        [NSGraphicsContext restoreGraphicsState];
    }

    const uint8_t *rowBytes = CGBitmapContextGetData(context);
    const size_t bytesPerRow = CGBitmapContextGetBytesPerRow(context);

    // The Xcursor image is packed, one XcursorPixel per pixel; the bitmap rows
    // may be padded. Copy each row once.
    for (size_t row = 0; row < height; row++, rowBytes += bytesPerRow)
        memcpy(ximage->pixels + row * width, rowBytes,
               width * sizeof(XcursorPixel));

    CGContextRelease(context);

    _cursor = XcursorImageLoadCursor(display, ximage);
    XcursorImageDestroy(ximage);
    if (_cursor == None)
        _cursor = XcursorLibraryLoadCursor(display, "left_ptr");
    return self;
}

- (id) initBlank {
    X11Display *d = (X11Display *) [NSDisplay currentDisplay];
    Display *display = [d display];

    static const char data[1] = {0};

    Pixmap blank;
    XColor dummy;

    blank = XCreateBitmapFromData(display, DefaultRootWindow(display), data, 1,
                                  1);
    if (blank != None) {
        _cursor = XCreatePixmapCursor(display, blank, blank, &dummy, &dummy, 0,
                                      0);
        XFreePixmap(display, blank);
    } else
        _cursor = None;

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

    if (display)
        XFreeCursor(display, _cursor);
    [super dealloc];
}

@end
