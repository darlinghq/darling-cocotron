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

#import <Foundation/NSGeometry.h>
#import <AppKit/AppKitIvarLayout.h>
#import <Foundation/NSObject.h>

@class NSImage, NSColor, NSEvent;

@interface NSCursor : NSObject <NSCoding> {
    NS_LEGACY_IVAR_PAD(_NSCursorReserved, 12)
    NS_EXTRA_IVARS_BEGIN(NSCursor)
    NSImage *_image;
    NSPoint _hotSpot;
    BOOL _isSetOnMouseEntered;
    BOOL _isSetOnMouseExited;
    id _platformCursor;
    NS_EXTRA_IVARS_END(NSCursor)
}

@property(class, readonly, retain, nonnull) NSCursor *currentCursor;
@property(class, readonly, retain) NSCursor *currentSystemCursor;

@property(class, readonly, retain, nonnull) NSCursor *arrowCursor;
@property(class, readonly, retain, nonnull) NSCursor *closedHandCursor;
@property(class, readonly, retain, nonnull) NSCursor *contextualMenuCursor;
@property(class, readonly, retain, nonnull) NSCursor *crosshairCursor;
@property(class, readonly, retain, nonnull) NSCursor *disappearingItemCursor;
@property(class, readonly, retain, nonnull) NSCursor *IBeamCursor;
@property(class, readonly, retain, nonnull) NSCursor *openHandCursor;
@property(class, readonly, retain, nonnull) NSCursor *pointingHandCursor;
@property(class, readonly, retain, nonnull) NSCursor *resizeDownCursor;
@property(class, readonly, retain, nonnull) NSCursor *resizeLeftCursor;
@property(class, readonly, retain, nonnull) NSCursor *resizeLeftRightCursor;
@property(class, readonly, retain, nonnull) NSCursor *resizeRightCursor;
@property(class, readonly, retain, nonnull) NSCursor *resizeUpCursor;
@property(class, readonly, retain, nonnull) NSCursor *resizeUpDownCursor;

@property(class, readonly, retain, nonnull) NSCursor *dragCopyCursor;
@property(class, readonly, retain, nonnull) NSCursor *dragLinkCursor;
@property(class, readonly, retain, nonnull) NSCursor *operationNotAllowedCursor;

+ (void) hide;
+ (void) unhide;

+ (void) setHiddenUntilMouseMoves: (BOOL) flag;

- initWithImage: (NSImage *) image
        foregroundColorHint: (NSColor *) foregroundHint
        backgroundColorHint: (NSColor *) backgroundHint
                    hotSpot: (NSPoint) hotSpot;
- initWithImage: (NSImage *) image hotSpot: (NSPoint) hotSpot;

- (NSImage *) image;
- (NSPoint) hotSpot;

- (BOOL) isSetOnMouseEntered;
- (BOOL) isSetOnMouseExited;

- (void) setOnMouseEntered: (BOOL) value;
- (void) setOnMouseExited: (BOOL) value;

- (void) mouseEntered: (NSEvent *) event;
- (void) mouseExited: (NSEvent *) event;

- (void) pop;

- (void) set;

- (void) push;
+ (void) pop;

@end
