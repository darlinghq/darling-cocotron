/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * Darling's own drawings of a few system symbols, and the generic glyph drawn
 * for every other symbol name. They are simple line drawings made for Darling,
 * not Apple's symbol artwork.
 */
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSColor.h>
#import <Foundation/NSString.h>
#include <math.h>
#include <string.h>

typedef void (*GlyphDrawer)(NSRect box, CGFloat line);

// A point at fractions (x, y) of the box, y up.
static NSPoint at(NSRect box, CGFloat x, CGFloat y) {
    return NSMakePoint(NSMinX(box) + x * NSWidth(box), NSMinY(box) + y * NSHeight(box));
}

static NSBezierPath *strokePath(CGFloat line) {
    NSBezierPath *path = [NSBezierPath bezierPath];
    [path setLineWidth: line];
    [path setLineJoinStyle: NSRoundLineJoinStyle];
    [path setLineCapStyle: NSRoundLineCapStyle];
    return path;
}

static void drawPlaceholder(NSRect box, CGFloat line) {
    CGFloat radius = NSWidth(box) / 5.0;
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect: box xRadius: radius yRadius: radius];
    [path setLineWidth: line];
    [path stroke];
}

// A rounded square with a plus in it.
static void drawPlusSquare(NSRect box, CGFloat line) {
    drawPlaceholder(box, line);
    NSBezierPath *plus = strokePath(line);
    [plus moveToPoint: at(box, 0.5, 0.25)];
    [plus lineToPoint: at(box, 0.5, 0.75)];
    [plus moveToPoint: at(box, 0.25, 0.5)];
    [plus lineToPoint: at(box, 0.75, 0.5)];
    [plus stroke];
}

// A filled triangle pointing up over a filled bar.
static void drawEjectFill(NSRect box, CGFloat line) {
    NSBezierPath *triangle = [NSBezierPath bezierPath];
    [triangle moveToPoint: at(box, 0.5, 0.92)];
    [triangle lineToPoint: at(box, 0.95, 0.4)];
    [triangle lineToPoint: at(box, 0.05, 0.4)];
    [triangle closePath];
    [triangle fill];
    NSRect bar = NSMakeRect(NSMinX(box) + 0.05 * NSWidth(box), NSMinY(box) + 0.08 * NSHeight(box),
                            0.9 * NSWidth(box), 0.16 * NSHeight(box));
    [[NSBezierPath bezierPathWithRoundedRect: bar xRadius: line yRadius: line] fill];
}

// A folder outline: a body with a tab on its top left.
static void drawFolder(NSRect box, CGFloat line) {
    NSBezierPath *path = strokePath(line);
    [path moveToPoint: at(box, 0.0, 0.12)];
    [path lineToPoint: at(box, 1.0, 0.12)];
    [path lineToPoint: at(box, 1.0, 0.72)];
    [path lineToPoint: at(box, 0.48, 0.72)];
    [path lineToPoint: at(box, 0.4, 0.86)];
    [path lineToPoint: at(box, 0.0, 0.86)];
    [path closePath];
    [path moveToPoint: at(box, 0.0, 0.62)];
    [path lineToPoint: at(box, 1.0, 0.62)];
    [path stroke];
}

// A globe: a circle with a meridian ellipse, the equator and two parallels.
static void drawNetwork(NSRect box, CGFloat line) {
    CGFloat side = MIN(NSWidth(box), NSHeight(box));
    NSRect circle = NSMakeRect(NSMidX(box) - side / 2, NSMidY(box) - side / 2, side, side);
    NSBezierPath *path = strokePath(line);
    [path appendBezierPathWithOvalInRect: circle];
    [path appendBezierPathWithOvalInRect: NSInsetRect(circle, side * 0.25, 0)];
    [path moveToPoint: NSMakePoint(NSMinX(circle), NSMidY(circle))];
    [path lineToPoint: NSMakePoint(NSMaxX(circle), NSMidY(circle))];
    // The parallels at a quarter of the diameter above and below the equator.
    CGFloat offset = side / 4, half = sqrt(side * side / 4 - offset * offset);
    [path moveToPoint: NSMakePoint(NSMidX(circle) - half, NSMidY(circle) + offset)];
    [path lineToPoint: NSMakePoint(NSMidX(circle) + half, NSMidY(circle) + offset)];
    [path moveToPoint: NSMakePoint(NSMidX(circle) - half, NSMidY(circle) - offset)];
    [path lineToPoint: NSMakePoint(NSMidX(circle) + half, NSMidY(circle) - offset)];
    [path stroke];
}

static const struct {
    const char *name;
    GlyphDrawer draw;
} glyphs[] = {
    { "eject.fill", drawEjectFill },
    { "folder", drawFolder },
    { "network", drawNetwork },
    { "plus.square", drawPlusSquare },
};

static GlyphDrawer drawerForName(NSString *name) {
    const char *string = [name UTF8String];
    if (string == NULL)
        return NULL;
    for (size_t i = 0; i < sizeof(glyphs) / sizeof(glyphs[0]); i++)
        if (strcmp(glyphs[i].name, string) == 0)
            return glyphs[i].draw;
    return NULL;
}

BOOL NSImageSymbolHasGlyph(NSString *name) {
    return drawerForName(name) != NULL;
}

// Draws the symbol in black into rect; the image is a template, so drawing
// tints it.
void NSImageSymbolDrawGlyph(NSString *name, NSRect rect) {
    GlyphDrawer draw = drawerForName(name);
    CGFloat line = MAX(1.0, floor(NSWidth(rect) / 12.0));
    NSRect box = NSInsetRect(rect, line * 1.5, line * 1.5);
    [[NSColor blackColor] set];
    (draw ? draw : drawPlaceholder)(box, line);
}
