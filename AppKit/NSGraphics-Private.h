/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/

#import <AppKit/NSGraphics.h>
#import <AppKit/NSGraphicsContext.h>
#import <CoreGraphics/CoreGraphics.h>

// Private: the focus ring style of the context (NSSetFocusRingStyle). The outer-only flavour draws the ring
// only outside the shape, for rings drawn by a superview around a subview that was painted before.
@interface NSGraphicsContext (FocusRing)
- (NSInteger) _focusRingPlacement;
- (BOOL) _focusRingOuterOnly;
- (void) _setFocusRingPlacement: (NSInteger) placement outerOnly: (BOOL) outerOnly;
@end

// Private: the fill and stroke functions paint a focus ring around a shape when NSSetFocusRingStyle asked for one.
BOOL _NSFocusRingBeforePaintingPath(CGContextRef context, CGPathRef path);
void _NSFocusRingAfterPaintingPath(CGContextRef context, CGPathRef path);

// Private: the sunken frames that Carbon-based themed controls get. The rect is the outer bounds; only the frame is
// drawn, the inside is left as it is. `flipped` says whether the y axis of the context points down (the "top" edge,
// the darker one, is then the one at the smallest y).
APPKIT_EXPORT void _NSDrawCarbonThemeBezel(NSRect rect, BOOL enabled, BOOL flipped);
APPKIT_EXPORT void _NSDrawCarbonThemeListBox(NSRect rect, BOOL enabled, BOOL flipped, BOOL active);
