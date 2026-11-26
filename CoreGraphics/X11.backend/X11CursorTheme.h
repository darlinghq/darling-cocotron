// The X11 cursors of CoreGraphics' cursors (CGSCursor): a shape is loaded from the cursor theme at the display's
// backing scale, an image is made into an Xcursor image at the scale. Header-only, like the other X11 helpers of
// this backend.
#ifndef X11CURSORTHEME_H
#define X11CURSORTHEME_H

#include <X11/Xlib.h>
#include <X11/Xcursor/Xcursor.h>
#include <math.h>
#include <string.h>
#include <CoreGraphics/CGSCursorPrivate.h>

// The X cursor convention: a cursor theme is authored against a nominal size, and
// 24 is what X reports when nothing else has been asked for.
#define X11_CURSOR_NOMINAL_SIZE 24

// Requests a cursor image of `nominalSize` logical points at the display's backing scale, rounded to whole
// device pixels. X11 rasterises a cursor at its image's native size and never scales it for a HiDPI display, so a
// themed 24pt arrow on a 2x screen has to be asked for as 48px or it renders half size.
static inline int X11CursorScaledSize(int nominalSize, double scale)
{
	if (nominalSize <= 0)
		nominalSize = X11_CURSOR_NOMINAL_SIZE;
	if (!(scale >= 1.0) || !isfinite(scale))
		scale = 1.0;

	double requested = round((double) nominalSize * scale);
	if (requested < 1.0)
		return 1;
	// XCURSOR_IMAGE_MAX_SIZE; asking for more is a corrupt scale, not a big cursor.
	if (requested > XCURSOR_IMAGE_MAX_SIZE)
		return XCURSOR_IMAGE_MAX_SIZE;
	return (int) requested;
}

// Loads a themed cursor at the backing scale, falling back to the nominal size and then to libXcursor's own
// lookup. Returns None when the theme has no such cursor.
static inline Cursor X11LoadThemedCursor(Display* display, const char* name, double scale)
{
	Cursor cursor = None;

	// Ask the theme for an image at the scaled size and let libXcursor scale the hot spot with it, so the cursor
	// stays sharp rather than being one image stretched.
	const int nominal = XcursorGetDefaultSize(display);
	XcursorImages* images = XcursorLibraryLoadImages(NULL, name, X11CursorScaledSize(nominal, scale));
	if (images != NULL)
	{
		XcursorImagesSetName(images, name);
		cursor = XcursorImagesLoadCursor(display, images);
		XcursorImagesDestroy(images);
	}

	// No scaled image: a theme may only carry one size, or resolve to nothing at all. Try the nominal size before
	// giving up on the theme-aware path.
	if (cursor == None)
	{
		images = XcursorLibraryLoadImages(NULL, name, X11CursorScaledSize(nominal, 1.0));
		if (images != NULL)
		{
			XcursorImagesSetName(images, name);
			cursor = XcursorImagesLoadCursor(display, images);
			XcursorImagesDestroy(images);
		}
	}

	if (cursor == None)
		cursor = XcursorLibraryLoadCursor(display, name);

	return cursor;
}

// The cursor of a shape: the theme's spelling of the name, else the alternative a theme may use for it, else the
// arrow.
static inline Cursor X11CreateShapeCursor(Display* display, CGSCursor* cursor, double scale)
{
	Cursor result = X11LoadThemedCursor(display, [cursor x11Name], scale);
	// The theme may not know the legacy spelling; retry with the name it does ship.
	if (result == None && [cursor x11AliasName] != NULL)
		result = X11LoadThemedCursor(display, [cursor x11AliasName], scale);
	if (result == None)
		result = XcursorLibraryLoadCursor(display, "left_ptr");
	return result;
}

// An image cursor: the pixels at the scale, and the hot spot scaled with them.
static inline Cursor X11CreateImageCursor(Display* display, CGSCursor* cursor, double scale)
{
	CGSize pixelSize = [cursor pixelSizeForScale: scale];
	NSData* pixels = [cursor pixelsForScale: scale];
	if (pixelSize.width < 1 || pixelSize.height < 1 || pixels == nil)
		return None;

	const size_t width = (size_t) pixelSize.width, height = (size_t) pixelSize.height;
	XcursorImage* ximage = XcursorImageCreate((int) width, (int) height);
	if (ximage == NULL)
		return None;

	// libXcursor requires the hot spot to be inside the image.
	CGPoint hotSpot = [cursor hotSpot];
	ximage->xhot = (XcursorDim) fmin(fmax(floor(hotSpot.x * scale), 0.0), (double) width - 1);
	ximage->yhot = (XcursorDim) fmin(fmax(floor(hotSpot.y * scale), 0.0), (double) height - 1);
	memcpy(ximage->pixels, [pixels bytes], width * height * sizeof(XcursorPixel));

	Cursor result = XcursorImageLoadCursor(display, ximage);
	XcursorImageDestroy(ximage);
	return result;
}

#endif
