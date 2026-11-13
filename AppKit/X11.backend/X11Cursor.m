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

// The X cursor convention: a cursor theme is authored against a nominal size, and
// 24 is what X reports when nothing else has been asked for.
static const int X11CursorNominalSize = 24;

// Requests a cursor image of `nominalSize` logical points at the display's backing
// scale, rounded to whole device pixels. X11 rasterises a cursor at its image's native
// size and never scales it for a HiDPI display, so a themed 24pt arrow on a 2x screen
// has to be *asked* for as 48px or it renders half size.
static int X11CursorScaledSize(int nominalSize, CGFloat scale) {
    if (nominalSize <= 0)
        nominalSize = X11CursorNominalSize;
    if (!(scale >= 1.0) || !isfinite(scale))
        scale = 1.0;

    double requested = round((double) nominalSize * (double) scale);
    if (requested < 1.0)
        return 1;
    // XCURSOR_IMAGE_MAX_SIZE; asking for more is a corrupt scale, not a big cursor.
    if (requested > XCURSOR_IMAGE_MAX_SIZE)
        return XCURSOR_IMAGE_MAX_SIZE;
    return (int) requested;
}

// Cocoa cursor names have no single X11 spelling. "hand" is the pre-Xcursor name that
// current themes no longer ship (Adwaita and Breeze call it "pointer" and "grabbing"),
// so asking for "hand" alone falls through to the arrow. Try the theme's spelling
// before giving up.
static const char *X11CursorAliasesFor(const char *name)
{
    static const struct { const char *cocoa, *theme; } aliases[] = {
        { "hand",   "pointer"   },
        { "hand2",  "pointer"   },
        { "hand3",  "pointer"   },
        { "xterm",  "text"      },
        { "fleur",  "move"      },
    };
    for (size_t i = 0; i < sizeof(aliases) / sizeof(*aliases); i++) {
        if (strcmp(name, aliases[i].cocoa) == 0)
            return aliases[i].theme;
    }
    return NULL;
}

// Loads a themed cursor at the backing scale, falling back to the nominal size and
// then to libXcursor's own lookup. Returns None when the theme has no such cursor.
static Cursor X11LoadThemedCursor(Display *display, const char *name, CGFloat scale) {
    Cursor cursor = None;

    // Ask the theme for an image at the scaled size and let libXcursor scale the hot
    // spot with it, so the cursor stays sharp rather than being one image stretched.
    const int nominal = XcursorGetDefaultSize(display);
    XcursorImages *images =
            XcursorLibraryLoadImages(NULL, name, X11CursorScaledSize(nominal, scale));
    if (images != NULL) {
        XcursorImagesSetName(images, name);
        cursor = XcursorImagesLoadCursor(display, images);
        XcursorImagesDestroy(images);
    }

    // No scaled image: a theme may only carry one size, or resolve to nothing at all.
    // Try the nominal size before giving up on the theme-aware path.
    if (cursor == None) {
        images = XcursorLibraryLoadImages(NULL, name, X11CursorScaledSize(nominal, 1.0));
        if (images != NULL) {
            XcursorImagesSetName(images, name);
            cursor = XcursorImagesLoadCursor(display, images);
            XcursorImagesDestroy(images);
        }
    }

    if (cursor == None)
        cursor = XcursorLibraryLoadCursor(display, name);

    return cursor;
}

- (id) initWithName: (const char *) name {
    X11Display *d = (X11Display *) [NSDisplay currentDisplay];
    Display *display = [d display];
    const CGFloat scale = [d backingScale];

    _cursor = X11LoadThemedCursor(display, name, scale);

    // The theme may not know the legacy spelling; retry with the name it does ship.
    const char *alias = _cursor == None ? X11CursorAliasesFor(name) : NULL;
    if (alias != NULL)
        _cursor = X11LoadThemedCursor(display, alias, scale);

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

    // libXcursor requires the hot spot to be inside the image, and converting a
    // non-finite float to int is undefined, so a NaN or infinite hot spot (or a
    // non-finite/non-positive image size) has to be rejected before the cast.
    if (!isfinite(hotPoint.x) || !isfinite(hotPoint.y)
            || !(logicalWidth > 0.0) || !(logicalHeight > 0.0)
            || !isfinite(logicalWidth) || !isfinite(logicalHeight))
        return [self initWithName: "left_ptr"];

    const double scaledWidth = floor(logicalWidth * scale + 0.5);
    const double scaledHeight = floor(logicalHeight * scale + 0.5);

    // XcursorImageCreate allocates width*height*4, and nothing else bounds it, so an
    // image with an enormous size would ask for gigabytes. Bound on floating-point
    // values before converting to size_t.
    if (scaledWidth < 1.0 || scaledHeight < 1.0 || scaledWidth > 0x7FFF || scaledHeight > 0x7FFF)
        return [self initWithName: "left_ptr"];

    const size_t width = (size_t) scaledWidth;
    const size_t height = (size_t) scaledHeight;

    XcursorImage *ximage = XcursorImageCreate(width, height);
    if (!ximage)
        return [self initWithName: "left_ptr"];

    // libXcursor requires the hot spot to be inside the image.
    ximage->xhot = (int) fmin(fmax(floor(hotPoint.x * scale), 0.0), (CGFloat) width - 1);
    ximage->yhot = (int) fmin(fmax(floor(hotPoint.y * scale), 0.0), (CGFloat) height - 1);

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

    // A 1x1 pixmap with a garbage XColor would still draw, but the undefined contents
    // leak into the server as the cursor's fore/background colours.
    XColor dummy = {0, 0, 0, 0, 0, 0};

    Pixmap blank = XCreateBitmapFromData(display, DefaultRootWindow(display), data, 1,
                                         1);
    if (blank != None) {
        _cursor = XCreatePixmapCursor(display, blank, blank, &dummy, &dummy, 0, 0);
        XFreePixmap(display, blank);
    }

    // None means "inherit the parent's cursor" to XDefineCursor, not "no cursor", so
    // leaving it None on failure would show an arbitrary cursor instead of hiding one.
    if (_cursor == None)
        return [self initWithName: "left_ptr"];

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
