/* Copyright (c) 2006-2007 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <AppKit/NSCursor.h>
#import <AppKit/NSDisplay.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSRaise.h>
#import <Foundation/NSNull.h>
#ifdef WINDOWS
#import <AppKit/Win32Cursor.h>
#import <Foundation/NSPlatform_win32.h>
#import <windows.h>
#endif

id NSPlatformCreateCursorImpWithName(NSString *name) {
    return [[[NSDisplay currentDisplay] cursorWithName: name] retain];
}

id NSPlatformCreateCursorImpWithImage(NSImage *image, NSPoint hotSpot) {
#ifndef WINDOWS
    return [[[NSDisplay currentDisplay] cursorWithImage: image
                                                hotSpot: hotSpot] retain];
#else
    /// move to the platform files
    size_t width = [image size].width;
    size_t height = [image size].height;

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(
            NULL, width, height, 8, 0, colorSpace,
            kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(colorSpace);

    NSAutoreleasePool *pool = [NSAutoreleasePool new];
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

    [pool release];

    uint8_t *rowBytes = CGBitmapContextGetData(context);
    size_t bytesPerRow = CGBitmapContextGetBytesPerRow(context);

    HDC displayDC = GetDC(NULL);
    HBITMAP colorBitmap;
    HBITMAP maskBitmap;

    if (NSPlatformGreaterThanOrEqualToWindows2000()) {
        // Cursor with alpha channel, no mask. Win2k and above
        BITMAPV5HEADER bi;
        void *lpBits;
        uint8_t *dibRowBytes;

        ZeroMemory(&bi, sizeof(BITMAPV5HEADER));
        bi.bV5Size = sizeof(BITMAPV5HEADER);
        bi.bV5Width = width;
        bi.bV5Height = -height;
        bi.bV5Planes = 1;
        bi.bV5BitCount = 32;
        bi.bV5Compression = BI_BITFIELDS;
        bi.bV5RedMask = 0x00FF0000;
        bi.bV5GreenMask = 0x0000FF00;
        bi.bV5BlueMask = 0x000000FF;
        bi.bV5AlphaMask = 0xFF000000;

        colorBitmap = CreateDIBSection(displayDC, (BITMAPINFO *) &bi,
                                       DIB_RGB_COLORS, &lpBits, NULL, 0);
        dibRowBytes = lpBits;

        maskBitmap = CreateBitmap(width, height, 1, 1, NULL);
        int row, column;

        for (row = 0; row < height;
             row++, rowBytes += bytesPerRow, dibRowBytes += width * 4) {
            for (column = 0; column < width; column++) {
                dibRowBytes[column * 4] = rowBytes[column * 4];
                dibRowBytes[column * 4 + 1] = rowBytes[column * 4 + 1];
                dibRowBytes[column * 4 + 2] = rowBytes[column * 4 + 2];
                dibRowBytes[column * 4 + 3] = rowBytes[column * 4 + 3];
            }
        }

    } else {
        // This works for versions lower than 2k, not really needed, but here.
        HDC colorDC = CreateCompatibleDC(displayDC);
        HDC maskDC = CreateCompatibleDC(displayDC);

        colorBitmap = CreateCompatibleBitmap(displayDC, width, height);
        maskBitmap = CreateCompatibleBitmap(displayDC, width, height);

        HBITMAP oldColorBitmap = SelectObject(colorDC, colorBitmap);
        HBITMAP oldMaskBitmap = SelectObject(maskDC, maskBitmap);

        int row, column;

        for (row = 0; row < height; row++, rowBytes += bytesPerRow) {
            for (column = 0; column < width; column++) {
                uint8_t b = rowBytes[column * 4];
                uint8_t g = rowBytes[column * 4 + 1];
                uint8_t r = rowBytes[column * 4 + 2];
                uint8_t a = rowBytes[column * 4 + 3];

                if (a < 255) {
                    SetPixel(colorDC, column, row, RGB(r, g, b));
                    SetPixel(maskDC, column, row, RGB(255, 255, 255));
                } else {
                    SetPixel(colorDC, column, row, RGB(r, g, b));
                    SetPixel(maskDC, column, row, RGB(0, 0, 0));
                }
            }
        }
        SelectObject(colorDC, oldColorBitmap);
        SelectObject(maskDC, oldMaskBitmap);
        DeleteDC(colorDC);
        DeleteDC(maskDC);
    }

    ReleaseDC(NULL, displayDC);

    CGContextRelease(context);

    ICONINFO iconInfo;

    iconInfo.fIcon = FALSE;
    iconInfo.xHotspot = hotSpot.x;
    iconInfo.yHotspot = hotSpot.y;
    iconInfo.hbmMask = maskBitmap;
    iconInfo.hbmColor = colorBitmap;

    HCURSOR hCursor = CreateIconIndirect(&iconInfo);

    DeleteObject(colorBitmap);
    DeleteObject(maskBitmap);

    return [[Win32Cursor alloc] initWithHCURSOR: hCursor];
#endif
}

void NSPlatformReleaseCursorImp(id object) {
    [object release];
}

void NSPlatformSetCursorImp(id object) {
    [[NSDisplay currentDisplay] setCursor: object];
}

@implementation NSCursor

static NSMutableArray *_cursorStack = nil;

+ (void) initialize {
    if (self == [NSCursor class]) {
        _cursorStack = [[NSMutableArray alloc] init];
    }
}

+ (NSCursor *) currentCursor {
    return [[[_cursorStack lastObject] retain] autorelease];
}

+ (NSCursor *) currentSystemCursor {
    return [[[_cursorStack lastObject] retain] autorelease];
}

- initWithCoder: (NSCoder *) coder {
    if (![coder allowsKeyedCoding]) {
        // QUIRK: a cursor archived with NSArchiver decodes to the standard arrow cursor,
        // whichever cursor (standard or created from an image) was archived. The archive holds
        // the hot spot as two floats, the image (nil for standard cursors) and two flag bytes,
        // all of which are read and dropped. Not documented. Evidence: black-box observation on
        // macOS 10.14.4, i386 and x86_64 (tier 2): 17 standard cursors and one image cursor
        // all unarchive to +arrowCursor, also while another cursor is current.
        // Test: tests/src/typedstream_appkit.m (test_quirk_cursor_decodes_as_arrow)
        float hotSpot[2];
        id image = nil;
        char flags[2];

        [coder decodeValuesOfObjCTypes: "ff", &hotSpot[0], &hotSpot[1]];
        [coder decodeValueOfObjCType: @encode(id) at: &image];
        [coder decodeValueOfObjCType: @encode(char) at: &flags[0]];
        [coder decodeValueOfObjCType: @encode(char) at: &flags[1]];
        [image release];
        return [self initWithName: @"arrowCursor"];
    }
    return self;
}

- (void) encodeWithCoder: (NSCoder *) coder {
    NSUnimplementedMethod();
}

- initWithName: (NSString *) name {
    NS_EXTRA(NSCursor, self)->_platformCursor = NSPlatformCreateCursorImpWithName(name);
    return self;
}

+ (NSCursor *) arrowCursor {
    static NSCursor *shared = nil;

    if (shared == nil)
        shared = [[self alloc] initWithName: NSStringFromSelector(_cmd)];

    return shared;
}

+ (NSCursor *) closedHandCursor {
    static NSCursor *shared = nil;

    if (shared == nil)
        shared = [[self alloc] initWithName: NSStringFromSelector(_cmd)];

    return shared;
}

+ (NSCursor *) contextualMenuCursor {
    static NSCursor *shared = nil;

    if (shared == nil)
        shared = [[self alloc] initWithName: NSStringFromSelector(_cmd)];

    return shared;
}

+ (NSCursor *) crosshairCursor {
    static NSCursor *shared = nil;

    if (shared == nil)
        shared = [[self alloc] initWithName: NSStringFromSelector(_cmd)];

    return shared;
}

+ (NSCursor *) disappearingItemCursor {
    static NSCursor *shared = nil;

    if (shared == nil)
        shared = [[self alloc] initWithName: NSStringFromSelector(_cmd)];

    return shared;
}

+ (NSCursor *) IBeamCursor {
    static NSCursor *shared = nil;

    if (shared == nil)
        shared = [[self alloc] initWithName: NSStringFromSelector(_cmd)];

    return shared;
}

+ (NSCursor *) openHandCursor {
    static NSCursor *shared = nil;

    if (shared == nil)
        shared = [[self alloc] initWithName: NSStringFromSelector(_cmd)];

    return shared;
}

+ (NSCursor *) pointingHandCursor {
    static NSCursor *shared = nil;

    if (shared == nil)
        shared = [[self alloc] initWithName: NSStringFromSelector(_cmd)];

    return shared;
}

+ (NSCursor *) resizeDownCursor {
    static NSCursor *shared = nil;

    if (shared == nil)
        shared = [[self alloc] initWithName: NSStringFromSelector(_cmd)];

    return shared;
}

+ (NSCursor *) resizeLeftCursor {
    static NSCursor *shared = nil;

    if (shared == nil)
        shared = [[self alloc] initWithName: NSStringFromSelector(_cmd)];

    return shared;
}

+ (NSCursor *) resizeLeftRightCursor {
    static NSCursor *shared = nil;

    if (shared == nil)
        shared = [[self alloc] initWithName: NSStringFromSelector(_cmd)];

    return shared;
}

+ (NSCursor *) resizeRightCursor {
    static NSCursor *shared = nil;

    if (shared == nil)
        shared = [[self alloc] initWithName: NSStringFromSelector(_cmd)];

    return shared;
}

+ (NSCursor *) resizeUpCursor {
    static NSCursor *shared = nil;

    if (shared == nil)
        shared = [[self alloc] initWithName: NSStringFromSelector(_cmd)];

    return shared;
}

+ (NSCursor *) resizeUpDownCursor {
    static NSCursor *shared = nil;

    if (shared == nil)
        shared = [[self alloc] initWithName: NSStringFromSelector(_cmd)];

    return shared;
}

// A corner's cursor is one of six diagonal arrows, shared like the named ones and looked up by these private names by
// every backend (-initWithName:); a backend that does not know a name draws the arrow cursor.
+ (NSCursor *) _diagonalFrameResizeCursorNamed: (NSString *) name {
    static NSMutableDictionary *shared = nil;
    NSCursor *cursor;

    @synchronized([NSCursor class]) {
        if (shared == nil)
            shared = [[NSMutableDictionary alloc] init];
        cursor = [shared objectForKey: name];
        if (cursor == nil) {
            cursor = [[[self alloc] initWithName: name] autorelease];
            [shared setObject: cursor forKey: name];
        }
    }
    return cursor;
}

// Apple's documentation gives the cursor for every position and direction set as a table of pictures, each showing
// the arrows the edge or corner can move along; this follows the arrows' compass directions (top outward is north,
// inward south, both north-south; topLeft outward is north-west, inward south-east, both north-west to south-east;
// likewise for the others). The empty set is documented as not allowed.
// GUESS (not in the public documentation, not observed): which of this tree's cursors stands for each picture (the
// four edge arrows are the existing arrow cursors, the corners are the diagonal arrows above) and that an empty set
// raises NSInvalidArgumentException.
+ (NSCursor *) frameResizeCursorFromPosition: (NSCursorFrameResizePosition) position
                                 inDirections: (NSCursorFrameResizeDirections) directions
{
    BOOL inward = (directions & NSCursorFrameResizeDirectionsInward) != 0;
    BOOL outward = (directions & NSCursorFrameResizeDirectionsOutward) != 0;
    if (!inward && !outward)
        [NSException raise: NSInvalidArgumentException
                    format: @"+[NSCursor frameResizeCursorFromPosition:inDirections:] needs at least one direction"];

    BOOL both = inward && outward;
    switch (position) {
    case NSCursorFrameResizePositionTop:
        return both ? [self resizeUpDownCursor] : outward ? [self resizeUpCursor] : [self resizeDownCursor];
    case NSCursorFrameResizePositionBottom:
        return both ? [self resizeUpDownCursor] : outward ? [self resizeDownCursor] : [self resizeUpCursor];
    case NSCursorFrameResizePositionLeft:
        return both ? [self resizeLeftRightCursor] : outward ? [self resizeLeftCursor] : [self resizeRightCursor];
    case NSCursorFrameResizePositionRight:
        return both ? [self resizeLeftRightCursor] : outward ? [self resizeRightCursor] : [self resizeLeftCursor];
    case NSCursorFrameResizePositionTopLeft:
        return [self _diagonalFrameResizeCursorNamed: both ? @"frameResizeNorthWestSouthEastCursor"
                                                    : outward ? @"frameResizeNorthWestCursor"
                                                              : @"frameResizeSouthEastCursor"];
    case NSCursorFrameResizePositionBottomRight:
        return [self _diagonalFrameResizeCursorNamed: both ? @"frameResizeNorthWestSouthEastCursor"
                                                    : outward ? @"frameResizeSouthEastCursor"
                                                              : @"frameResizeNorthWestCursor"];
    case NSCursorFrameResizePositionTopRight:
        return [self _diagonalFrameResizeCursorNamed: both ? @"frameResizeNorthEastSouthWestCursor"
                                                    : outward ? @"frameResizeNorthEastCursor"
                                                              : @"frameResizeSouthWestCursor"];
    case NSCursorFrameResizePositionBottomLeft:
        return [self _diagonalFrameResizeCursorNamed: both ? @"frameResizeNorthEastSouthWestCursor"
                                                    : outward ? @"frameResizeSouthWestCursor"
                                                              : @"frameResizeNorthEastCursor"];
    }
    [NSException raise: NSInvalidArgumentException
                format: @"+[NSCursor frameResizeCursorFromPosition:inDirections:]: unknown position %lu",
                        (unsigned long) position];
    return nil;
}

+ (NSCursor *) dragCopyCursor {
    static NSCursor *shared = nil;

    if (shared == nil)
        shared = [[self alloc] initWithName: NSStringFromSelector(_cmd)];

    return shared;
}

+ (NSCursor *) dragLinkCursor {
    static NSCursor *shared = nil;

    if (shared == nil)
        shared = [[self alloc] initWithName: NSStringFromSelector(_cmd)];

    return shared;
}

+ (NSCursor *) operationNotAllowedCursor {
    static NSCursor *shared = nil;

    if (shared == nil)
        shared = [[self alloc] initWithName: NSStringFromSelector(_cmd)];

    return shared;
}

+ (void) hide {
    [[NSDisplay currentDisplay] hideCursorCounted];
}

+ (void) unhide {
    [[NSDisplay currentDisplay] unhideCursorCounted];
}

+ (void) setHiddenUntilMouseMoves: (BOOL) flag {
    [[NSDisplay currentDisplay] setCursorHiddenUntilMouseMoves: flag];
}

- initWithImage: (NSImage *) image
        foregroundColorHint: (NSColor *) foregroundHint
        backgroundColorHint: (NSColor *) backgroundHint
                    hotSpot: (NSPoint) hotSpot
{
    // the hints are unused per doc.s
    return [self initWithImage: image hotSpot: hotSpot];
}

- initWithImage: (NSImage *) image hotSpot: (NSPoint) hotSpot {
    NS_EXTRA(NSCursor, self)->_image = [image retain];
    NS_EXTRA(NSCursor, self)->_hotSpot = hotSpot;
    NS_EXTRA(NSCursor, self)->_platformCursor = NSPlatformCreateCursorImpWithImage(image, hotSpot);
    return self;
}

- (void) dealloc {
    [NS_EXTRA(NSCursor, self)->_image release];
    NSPlatformReleaseCursorImp(NS_EXTRA(NSCursor, self)->_platformCursor);
    NS_EXTRA_FREE(NSCursor, self);
    [super dealloc];
}

- (NSImage *) image {
    return NS_EXTRA(NSCursor, self)->_image;
}

- (NSPoint) hotSpot {
    return NS_EXTRA(NSCursor, self)->_hotSpot;
}

- (BOOL) isSetOnMouseEntered {
    return NS_EXTRA(NSCursor, self)->_isSetOnMouseEntered;
}

- (BOOL) isSetOnMouseExited {
    return NS_EXTRA(NSCursor, self)->_isSetOnMouseExited;
}

- (void) setOnMouseEntered: (BOOL) value {
    NS_EXTRA(NSCursor, self)->_isSetOnMouseEntered = value;
}

- (void) setOnMouseExited: (BOOL) value {
    NS_EXTRA(NSCursor, self)->_isSetOnMouseExited = value;
}

- (void) mouseEntered: (NSEvent *) event {
    NSUnimplementedMethod();
}

- (void) mouseExited: (NSEvent *) event {
    NSUnimplementedMethod();
}

- (void) pop {
    [[self class] pop];
}

- (void) set {
    if ([_cursorStack count])
        [_cursorStack removeLastObject];

    [_cursorStack addObject: self];
    NSPlatformSetCursorImp(NS_EXTRA(NSCursor, self)->_platformCursor);
}

- (void) push {
    [_cursorStack addObject: self];
    NSPlatformSetCursorImp(NS_EXTRA(NSCursor, self)->_platformCursor);
}

+ (void) pop {
    if ([_cursorStack count] < 2)
        return;

    [_cursorStack removeLastObject];

    NSCursor *cursor = [_cursorStack lastObject];

    if (cursor == nil)
        cursor = [NSCursor arrowCursor];

    NSPlatformSetCursorImp(NS_EXTRA(NSCursor, cursor)->_platformCursor);
}

@end
