/* Copyright (C) 2026 Lubos Dolezel

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

// The system template images that +[NSImage imageNamed:] answers for the NSImageName...Template constants and
// the table sort indicators.
// AppKit installs no artwork for them, so each is drawn here from simple shapes (our own glyphs, in black on
// a transparent background; template drawing only uses their coverage). The images have the point sizes the
// named images have on macOS 10.14.4 (black-box: -[NSImage size] of +imageNamed:); the Touch Bar images are
// 30 points high there, with the glyph in the middle. Test: tests/appkit-system-template-images.m

#import <AppKit/NSBezierPath.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSImage.h>
#import "NSImageSystemTemplates.h"
#include <math.h>

typedef void (*NSSystemTemplateDraw)(NSRect box);

typedef struct {
    NSString *name;
    CGFloat width, height;
    NSSystemTemplateDraw draw;
} NSSystemTemplate;

static const CGFloat kLine = 1.5;

static void strokePath(NSBezierPath *path) {
    [path setLineWidth: kLine];
    [path setLineCapStyle: NSRoundLineCapStyle];
    [path setLineJoinStyle: NSRoundLineJoinStyle];
    [path stroke];
}

// A chevron pointing left or right, as tall as the box.
static void chevron(NSRect box, BOOL right) {
    NSBezierPath *path = [NSBezierPath bezierPath];
    CGFloat inset = kLine;
    CGFloat w = MIN(NSWidth(box) - 2 * inset, (NSHeight(box) - 2 * inset) / 2);
    CGFloat midX = NSMidX(box), midY = NSMidY(box), half = (NSHeight(box) - 2 * inset) / 2;
    CGFloat tip = right ? midX + w / 2 : midX - w / 2, back = right ? midX - w / 2 : midX + w / 2;

    [path moveToPoint: NSMakePoint(back, midY + half)];
    [path lineToPoint: NSMakePoint(tip, midY)];
    [path lineToPoint: NSMakePoint(back, midY - half)];
    strokePath(path);
}

static void goLeft(NSRect box) { chevron(box, NO); }
static void goRight(NSRect box) { chevron(box, YES); }

// A chevron pointing up or down, as wide as the box.
static void verticalChevron(NSRect box, BOOL up) {
    NSBezierPath *path = [NSBezierPath bezierPath];
    CGFloat half = (NSWidth(box) - 2 * kLine) / 2, h = MIN(half, NSHeight(box) - 2 * kLine);
    CGFloat midX = NSMidX(box), midY = NSMidY(box);
    CGFloat tip = up ? midY + h / 2 : midY - h / 2, back = up ? midY - h / 2 : midY + h / 2;

    [path moveToPoint: NSMakePoint(midX - half, back)];
    [path lineToPoint: NSMakePoint(midX, tip)];
    [path lineToPoint: NSMakePoint(midX + half, back)];
    strokePath(path);
}

static void goUp(NSRect box) { verticalChevron(box, YES); }
static void goDown(NSRect box) { verticalChevron(box, NO); }

// A filled triangle pointing left or right, within the box.
static void fillTriangle(NSRect box, BOOL right) {
    NSBezierPath *path = [NSBezierPath bezierPath];
    CGFloat tip = right ? NSMaxX(box) : NSMinX(box), back = right ? NSMinX(box) : NSMaxX(box);

    [path moveToPoint: NSMakePoint(back, NSMaxY(box))];
    [path lineToPoint: NSMakePoint(tip, NSMidY(box))];
    [path lineToPoint: NSMakePoint(back, NSMinY(box))];
    [path closePath];
    [path fill];
}

static NSRect centeredRect(NSRect box, CGFloat w, CGFloat h) {
    return NSMakeRect(floor(NSMidX(box) - w / 2), floor(NSMidY(box) - h / 2), w, h);
}

static void leftTriangle(NSRect box) {
    fillTriangle(centeredRect(box, MIN(NSWidth(box), NSHeight(box) * 0.6), NSHeight(box) * 0.8), NO);
}

static void rightTriangle(NSRect box) {
    fillTriangle(centeredRect(box, MIN(NSWidth(box), NSHeight(box) * 0.6), NSHeight(box) * 0.8), YES);
}

static void play(NSRect box) {
    fillTriangle(NSInsetRect(box, 1, 1), YES);
}

static void pauseBars(NSRect box) {
    CGFloat bar = MAX(2, floor(NSWidth(box) / 3));

    NSRectFill(NSMakeRect(NSMinX(box), NSMinY(box), bar, NSHeight(box)));
    NSRectFill(NSMakeRect(NSMaxX(box) - bar, NSMinY(box), bar, NSHeight(box)));
}

static void playPause(NSRect box) {
    CGFloat w = NSWidth(box);
    NSRect left = NSMakeRect(NSMinX(box), NSMinY(box), floor(w * 0.5), NSHeight(box));
    NSRect right = NSMakeRect(NSMinX(box) + floor(w * 0.6), NSMinY(box), w - floor(w * 0.6), NSHeight(box));

    fillTriangle(left, YES);
    pauseBars(right);
}

// Two triangles side by side, pointing the same way.
static void doubleTriangle(NSRect box, BOOL right) {
    CGFloat half = NSWidth(box) / 2;

    fillTriangle(NSMakeRect(NSMinX(box), NSMinY(box), half, NSHeight(box)), right);
    fillTriangle(NSMakeRect(NSMinX(box) + half, NSMinY(box), half, NSHeight(box)), right);
}

static void rewindTriangles(NSRect box) { doubleTriangle(box, NO); }
static void fastForward(NSRect box) { doubleTriangle(box, YES); }

// A triangle and a bar at the end it points to.
static void skipTo(NSRect box, BOOL end) {
    CGFloat bar = 2;
    NSRect triangle = NSMakeRect(end ? NSMinX(box) : NSMinX(box) + bar + 1, NSMinY(box),
                                 NSWidth(box) - bar - 1, NSHeight(box));

    fillTriangle(triangle, end);
    NSRectFill(NSMakeRect(end ? NSMaxX(box) - bar : NSMinX(box), NSMinY(box), bar, NSHeight(box)));
}

static void skipToEnd(NSRect box) { skipTo(box, YES); }
static void skipToStart(NSRect box) { skipTo(box, NO); }

static void recordStart(NSRect box) {
    CGFloat d = MIN(NSWidth(box), NSHeight(box));

    [[NSBezierPath bezierPathWithOvalInRect: centeredRect(box, d, d)] fill];
}

static void recordStop(NSRect box) {
    CGFloat d = MIN(NSWidth(box), NSHeight(box)) - 2;

    NSRectFill(centeredRect(box, d, d));
}

static void stopProgress(NSRect box) {
    NSRect r = NSInsetRect(centeredRect(box, MIN(NSWidth(box), NSHeight(box)), MIN(NSWidth(box), NSHeight(box))),
                           kLine, kLine);
    NSBezierPath *path = [NSBezierPath bezierPath];

    [path moveToPoint: NSMakePoint(NSMinX(r), NSMinY(r))];
    [path lineToPoint: NSMakePoint(NSMaxX(r), NSMaxY(r))];
    [path moveToPoint: NSMakePoint(NSMinX(r), NSMaxY(r))];
    [path lineToPoint: NSMakePoint(NSMaxX(r), NSMinY(r))];
    strokePath(path);
}

static void plus(NSRect box) {
    NSBezierPath *path = [NSBezierPath bezierPath];
    CGFloat d = MIN(NSWidth(box), NSHeight(box)) / 2 - kLine;

    [path moveToPoint: NSMakePoint(NSMidX(box) - d, NSMidY(box))];
    [path lineToPoint: NSMakePoint(NSMidX(box) + d, NSMidY(box))];
    [path moveToPoint: NSMakePoint(NSMidX(box), NSMidY(box) - d)];
    [path lineToPoint: NSMakePoint(NSMidX(box), NSMidY(box) + d)];
    strokePath(path);
}

static void minus(NSRect box) {
    NSBezierPath *path = [NSBezierPath bezierPath];
    CGFloat d = MIN(NSWidth(box), NSHeight(box)) / 2 - kLine;

    [path moveToPoint: NSMakePoint(NSMidX(box) - d, NSMidY(box))];
    [path lineToPoint: NSMakePoint(NSMidX(box) + d, NSMidY(box))];
    strokePath(path);
}

// An open circle with an arrowhead at its end, turning clockwise.
static void circularArrow(NSRect box) {
    CGFloat d = MIN(NSWidth(box), NSHeight(box)) - kLine - 1;
    NSPoint c = NSMakePoint(NSMidX(box), NSMidY(box) - 0.5);
    CGFloat r = d / 2;
    NSBezierPath *arc = [NSBezierPath bezierPath];

    [arc appendBezierPathWithArcWithCenter: c radius: r startAngle: 60 endAngle: 120 clockwise: YES];
    strokePath(arc);

    // the arrowhead at the end of the arc (angle 60), pointing along it
    CGFloat a = 60 * M_PI / 180;
    NSPoint end = NSMakePoint(c.x + r * cos(a), c.y + r * sin(a));
    CGFloat head = MAX(3, r * 0.7);
    NSBezierPath *tip = [NSBezierPath bezierPath];

    [tip moveToPoint: NSMakePoint(end.x - head * 0.2, end.y + head * 0.7)];
    [tip lineToPoint: NSMakePoint(end.x + head * 0.5, end.y - head * 0.1)];
    [tip lineToPoint: NSMakePoint(end.x - head * 0.6, end.y - head * 0.4)];
    [tip closePath];
    [tip fill];
}

static NSRect circleRect(NSRect box) {
    CGFloat d = MIN(NSWidth(box), NSHeight(box)) - 1;

    return centeredRect(box, d, d);
}

// A filled circle: the "freestanding" images show a symbol cut out of it.
static void filledCircleWithClearSymbol(NSRect box, void (^symbol)(NSRect inner)) {
    NSRect circle = circleRect(box);

    [[NSBezierPath bezierPathWithOvalInRect: circle] fill];
    [[NSGraphicsContext currentContext] saveGraphicsState];
    [[NSGraphicsContext currentContext] setCompositingOperation: NSCompositeClear];
    symbol(NSInsetRect(circle, NSWidth(circle) * 0.25, NSHeight(circle) * 0.25));
    [[NSGraphicsContext currentContext] restoreGraphicsState];
}

static void stopProgressFreestanding(NSRect box) {
    filledCircleWithClearSymbol(box, ^(NSRect inner) { stopProgress(inner); });
}

static void refreshFreestanding(NSRect box) {
    filledCircleWithClearSymbol(box, ^(NSRect inner) { circularArrow(NSInsetRect(inner, -1, -1)); });
}

static void followLinkFreestanding(NSRect box) {
    filledCircleWithClearSymbol(box, ^(NSRect inner) {
        NSBezierPath *path = [NSBezierPath bezierPath];

        [path moveToPoint: NSMakePoint(NSMinX(inner), NSMidY(inner))];
        [path lineToPoint: NSMakePoint(NSMaxX(inner), NSMidY(inner))];
        [path moveToPoint: NSMakePoint(NSMidX(inner), NSMaxY(inner))];
        [path lineToPoint: NSMakePoint(NSMaxX(inner), NSMidY(inner))];
        [path lineToPoint: NSMakePoint(NSMidX(inner), NSMinY(inner))];
        strokePath(path);
    });
}

static void revealFreestanding(NSRect box) {
    filledCircleWithClearSymbol(box, ^(NSRect inner) {
        // a magnifying glass
        CGFloat d = NSWidth(inner) * 0.7;
        NSRect lens = NSMakeRect(NSMinX(inner), NSMaxY(inner) - d, d, d);
        NSBezierPath *path = [NSBezierPath bezierPathWithOvalInRect: lens];

        [path moveToPoint: NSMakePoint(NSMaxX(lens) - d * 0.15, NSMinY(lens) + d * 0.15)];
        [path lineToPoint: NSMakePoint(NSMaxX(inner), NSMinY(inner))];
        strokePath(path);
    });
}

static void invalidDataFreestanding(NSRect box) {
    filledCircleWithClearSymbol(box, ^(NSRect inner) {
        NSBezierPath *path = [NSBezierPath bezierPath];

        [path moveToPoint: NSMakePoint(NSMidX(inner), NSMaxY(inner))];
        [path lineToPoint: NSMakePoint(NSMidX(inner), NSMinY(inner) + NSHeight(inner) * 0.35)];
        strokePath(path);
        [[NSBezierPath bezierPathWithRect: NSMakeRect(NSMidX(inner) - 1, NSMinY(inner) - 0.5, 2, 2)] fill];
    });
}

// A gear: a ring with teeth around it.
static void gear(NSRect box) {
    CGFloat d = MIN(NSWidth(box), NSHeight(box));
    NSPoint c = NSMakePoint(NSMidX(box), NSMidY(box));
    CGFloat body = d * 0.34, outer = d / 2 - 0.5, hole = d * 0.14;
    NSBezierPath *teeth = [NSBezierPath bezierPath];

    [[NSBezierPath bezierPathWithOvalInRect: NSMakeRect(c.x - body, c.y - body, 2 * body, 2 * body)] fill];
    for (int i = 0; i < 8; i++) {
        CGFloat a = i * M_PI / 4;
        [teeth moveToPoint: c];
        [teeth lineToPoint: NSMakePoint(c.x + outer * cos(a), c.y + outer * sin(a))];
    }
    [teeth setLineWidth: MAX(1.5, d * 0.16)];
    [teeth stroke];
    [[NSGraphicsContext currentContext] saveGraphicsState];
    [[NSGraphicsContext currentContext] setCompositingOperation: NSCompositeClear];
    [[NSBezierPath bezierPathWithOvalInRect: NSMakeRect(c.x - hole, c.y - hole, 2 * hole, 2 * hole)] fill];
    [[NSGraphicsContext currentContext] restoreGraphicsState];
}

static void smartBadge(NSRect box) {
    filledCircleWithClearSymbol(box, ^(NSRect inner) { gear(NSInsetRect(inner, -1, -1)); });
}

static void columnView(NSRect box) {
    NSRect r = NSInsetRect(box, 0.75, 0.75);
    NSBezierPath *path = [NSBezierPath bezierPathWithRect: r];

    for (int i = 1; i < 3; i++) {
        CGFloat x = floor(NSMinX(r) + NSWidth(r) * i / 3) + 0.5;
        [path moveToPoint: NSMakePoint(x, NSMinY(r))];
        [path lineToPoint: NSMakePoint(x, NSMaxY(r))];
    }
    [path setLineWidth: 1];
    [path stroke];
}

static void iconView(NSRect box) {
    CGFloat gap = 2, w = (NSWidth(box) - gap) / 2, h = (NSHeight(box) - gap) / 2;

    for (int x = 0; x < 2; x++)
        for (int y = 0; y < 2; y++)
            NSRectFill(NSMakeRect(NSMinX(box) + x * (w + gap), NSMinY(box) + y * (h + gap), w, h));
}

static void listView(NSRect box) {
    CGFloat row = NSHeight(box) / 3, bar = MAX(1, floor(row * 0.6));

    for (int i = 0; i < 3; i++) {
        CGFloat y = floor(NSMinY(box) + i * row + (row - bar) / 2);
        NSRectFill(NSMakeRect(NSMinX(box), y, bar, bar));
        NSRectFill(NSMakeRect(NSMinX(box) + bar + 2, y, NSWidth(box) - bar - 2, bar));
    }
}

static void flowView(NSRect box) {
    CGFloat side = floor(NSWidth(box) * 0.25), middle = NSWidth(box) - 2 * side - 2;

    NSRectFill(NSMakeRect(NSMinX(box), NSMinY(box) + 2, side, NSHeight(box) - 4));
    NSRectFill(NSMakeRect(NSMinX(box) + side + 1, NSMinY(box), middle, NSHeight(box)));
    NSRectFill(NSMakeRect(NSMaxX(box) - side, NSMinY(box) + 2, side, NSHeight(box) - 4));
}

static void slideshow(NSRect box) {
    NSBezierPath *frame = [NSBezierPath bezierPathWithRect: NSInsetRect(box, 0.75, 0.75)];

    [frame setLineWidth: 1.5];
    [frame stroke];
    fillTriangle(centeredRect(box, NSHeight(box) * 0.4, NSHeight(box) * 0.5), YES);
}

static void quickLook(NSRect box) {
    // an eye: two arcs meeting at the corners and a pupil
    NSBezierPath *path = [NSBezierPath bezierPath];
    CGFloat midY = NSMidY(box), h = NSHeight(box) / 2 - kLine;

    [path moveToPoint: NSMakePoint(NSMinX(box) + kLine, midY)];
    [path curveToPoint: NSMakePoint(NSMaxX(box) - kLine, midY)
         controlPoint1: NSMakePoint(NSMinX(box) + NSWidth(box) * 0.3, midY + h * 1.3)
         controlPoint2: NSMakePoint(NSMaxX(box) - NSWidth(box) * 0.3, midY + h * 1.3)];
    [path curveToPoint: NSMakePoint(NSMinX(box) + kLine, midY)
         controlPoint1: NSMakePoint(NSMaxX(box) - NSWidth(box) * 0.3, midY - h * 1.3)
         controlPoint2: NSMakePoint(NSMinX(box) + NSWidth(box) * 0.3, midY - h * 1.3)];
    strokePath(path);
    CGFloat d = NSHeight(box) * 0.45;
    [[NSBezierPath bezierPathWithOvalInRect: centeredRect(box, d, d)] fill];
}

static void home(NSRect box) {
    NSBezierPath *roof = [NSBezierPath bezierPath];
    CGFloat eaves = NSMinY(box) + NSHeight(box) * 0.55;

    [roof moveToPoint: NSMakePoint(NSMinX(box) + kLine, eaves)];
    [roof lineToPoint: NSMakePoint(NSMidX(box), NSMaxY(box) - kLine)];
    [roof lineToPoint: NSMakePoint(NSMaxX(box) - kLine, eaves)];
    strokePath(roof);
    NSRect walls = NSMakeRect(NSMinX(box) + NSWidth(box) * 0.2, NSMinY(box), NSWidth(box) * 0.6,
                              eaves - NSMinY(box));
    NSRectFill(walls);
    NSRectFillUsingOperation(NSMakeRect(NSMidX(walls) - 1.5, NSMinY(walls), 3, NSHeight(walls) * 0.6),
                             NSCompositeClear);
}

static void lock(NSRect box, BOOL locked) {
    CGFloat bodyHeight = floor(NSHeight(box) * 0.55);
    CGFloat bodyWidth = MIN(NSWidth(box), NSHeight(box) * 0.75);
    NSRect body = NSMakeRect(NSMidX(box) - bodyWidth / 2, NSMinY(box), bodyWidth, bodyHeight);
    CGFloat r = bodyWidth * 0.35 - kLine / 2;
    NSPoint c = NSMakePoint(NSMidX(body), NSMaxY(box) - r - kLine / 2);
    // an open lock has its left leg lifted out of the body
    CGFloat leftBottom = locked ? NSMaxY(body) : NSMaxY(body) + (c.y - NSMaxY(body)) * 0.6;
    NSBezierPath *shackle = [NSBezierPath bezierPath];

    NSRectFill(body);
    [shackle moveToPoint: NSMakePoint(c.x - r, leftBottom)];
    [shackle lineToPoint: NSMakePoint(c.x - r, c.y)];
    [shackle appendBezierPathWithArcWithCenter: c radius: r startAngle: 180 endAngle: 0 clockwise: YES];
    [shackle lineToPoint: NSMakePoint(c.x + r, NSMaxY(body))];
    [shackle setLineWidth: kLine];
    [shackle setLineCapStyle: NSButtLineCapStyle];
    [shackle stroke];
}

static void lockLocked(NSRect box) { lock(box, YES); }
static void lockUnlocked(NSRect box) { lock(box, NO); }

static void path(NSRect box) {
    CGFloat w = NSWidth(box) / 3;

    for (int i = 0; i < 3; i++) {
        NSRect segment = NSMakeRect(NSMinX(box) + i * w, NSMinY(box), w, NSHeight(box));
        NSBezierPath *p = [NSBezierPath bezierPath];

        [p moveToPoint: NSMakePoint(NSMinX(segment) + 1, NSMinY(segment) + 1)];
        [p lineToPoint: NSMakePoint(NSMaxX(segment) - 3, NSMinY(segment) + 1)];
        [p lineToPoint: NSMakePoint(NSMaxX(segment) - 1, NSMidY(segment))];
        [p lineToPoint: NSMakePoint(NSMaxX(segment) - 3, NSMaxY(segment) - 1)];
        [p lineToPoint: NSMakePoint(NSMinX(segment) + 1, NSMaxY(segment) - 1)];
        [p setLineWidth: 1];
        [p stroke];
    }
}

static void share(NSRect box) {
    NSBezierPath *tray = [NSBezierPath bezierPath];
    CGFloat trayTop = NSMinY(box) + NSHeight(box) * 0.55;

    [tray moveToPoint: NSMakePoint(NSMinX(box) + NSWidth(box) * 0.3, trayTop)];
    [tray lineToPoint: NSMakePoint(NSMinX(box) + kLine, trayTop)];
    [tray lineToPoint: NSMakePoint(NSMinX(box) + kLine, NSMinY(box) + kLine)];
    [tray lineToPoint: NSMakePoint(NSMaxX(box) - kLine, NSMinY(box) + kLine)];
    [tray lineToPoint: NSMakePoint(NSMaxX(box) - kLine, trayTop)];
    [tray lineToPoint: NSMakePoint(NSMaxX(box) - NSWidth(box) * 0.3, trayTop)];
    [tray moveToPoint: NSMakePoint(NSMidX(box), NSMinY(box) + NSHeight(box) * 0.35)];
    [tray lineToPoint: NSMakePoint(NSMidX(box), NSMaxY(box) - kLine)];
    [tray moveToPoint: NSMakePoint(NSMidX(box) - NSWidth(box) * 0.25, NSMaxY(box) - NSWidth(box) * 0.25 - kLine)];
    [tray lineToPoint: NSMakePoint(NSMidX(box), NSMaxY(box) - kLine)];
    [tray lineToPoint: NSMakePoint(NSMidX(box) + NSWidth(box) * 0.25, NSMaxY(box) - NSWidth(box) * 0.25 - kLine)];
    strokePath(tray);
}

static void bookmarks(NSRect box) {
    // an open book: two pages meeting in the middle
    NSBezierPath *path = [NSBezierPath bezierPath];
    CGFloat top = NSMaxY(box) - kLine, bottom = NSMinY(box) + kLine, sag = 1.5;

    [path moveToPoint: NSMakePoint(NSMidX(box), bottom)];
    [path lineToPoint: NSMakePoint(NSMidX(box), top - sag)];
    [path lineToPoint: NSMakePoint(NSMinX(box) + kLine, top)];
    [path lineToPoint: NSMakePoint(NSMinX(box) + kLine, bottom + sag)];
    [path lineToPoint: NSMakePoint(NSMidX(box), bottom)];
    [path lineToPoint: NSMakePoint(NSMaxX(box) - kLine, bottom + sag)];
    [path lineToPoint: NSMakePoint(NSMaxX(box) - kLine, top)];
    [path lineToPoint: NSMakePoint(NSMidX(box), top - sag)];
    strokePath(path);
}

// Two arrows along the diagonal, pointing out to the corners or in to the middle.
static void fullScreen(NSRect box, BOOL enter) {
    NSRect r = NSInsetRect(box, kLine, kLine);
    CGFloat head = NSWidth(r) * 0.35;
    NSBezierPath *path = [NSBezierPath bezierPath];
    NSPoint corners[2] = {NSMakePoint(NSMaxX(r), NSMaxY(r)), NSMakePoint(NSMinX(r), NSMinY(r))};
    NSPoint inner[2] = {NSMakePoint(NSMidX(r) + 1, NSMidY(r) + 1), NSMakePoint(NSMidX(r) - 1, NSMidY(r) - 1)};

    for (int i = 0; i < 2; i++) {
        NSPoint tip = enter ? corners[i] : inner[i], tail = enter ? inner[i] : corners[i];
        CGFloat sx = tip.x > tail.x ? -1 : 1, sy = tip.y > tail.y ? -1 : 1;

        [path moveToPoint: tail];
        [path lineToPoint: tip];
        [path moveToPoint: NSMakePoint(tip.x + sx * head, tip.y)];
        [path lineToPoint: tip];
        [path lineToPoint: NSMakePoint(tip.x, tip.y + sy * head)];
    }
    strokePath(path);
}

static void enterFullScreen(NSRect box) { fullScreen(box, YES); }
static void exitFullScreen(NSRect box) { fullScreen(box, NO); }

static void bluetooth(NSRect box) {
    NSBezierPath *path = [NSBezierPath bezierPath];
    CGFloat x = NSMidX(box), w = NSWidth(box) / 2 - 0.5, q = NSHeight(box) / 4;

    [path moveToPoint: NSMakePoint(x - w, NSMinY(box) + q)];
    [path lineToPoint: NSMakePoint(x + w, NSMaxY(box) - q)];
    [path lineToPoint: NSMakePoint(x, NSMaxY(box) - 0.5)];
    [path lineToPoint: NSMakePoint(x, NSMinY(box) + 0.5)];
    [path lineToPoint: NSMakePoint(x + w, NSMinY(box) + q)];
    [path lineToPoint: NSMakePoint(x - w, NSMaxY(box) - q)];
    [path setLineWidth: 1];
    [path setLineJoinStyle: NSRoundLineJoinStyle];
    [path stroke];
}

static void theater(NSRect box) {
    // a screen on a stand
    NSRect screen = NSMakeRect(NSMinX(box), NSMinY(box) + 3, NSWidth(box), NSHeight(box) - 3);
    NSBezierPath *frame = [NSBezierPath bezierPathWithRect: NSInsetRect(screen, 0.75, 0.75)];

    [frame setLineWidth: 1.5];
    [frame stroke];
    NSRectFill(NSMakeRect(NSMidX(box) - 3, NSMinY(box), 6, 1.5));
    NSRectFill(NSMakeRect(NSMidX(box) - 0.75, NSMinY(box), 1.5, 3));
}

static void search(NSRect box) {
    CGFloat d = MIN(NSWidth(box), NSHeight(box)) * 0.65;
    NSRect lens = NSMakeRect(NSMinX(box) + kLine, NSMaxY(box) - d - kLine, d, d);
    NSBezierPath *path = [NSBezierPath bezierPathWithOvalInRect: lens];

    [path moveToPoint: NSMakePoint(NSMaxX(lens) - d * 0.15, NSMinY(lens) + d * 0.15)];
    [path lineToPoint: NSMakePoint(NSMaxX(box) - kLine, NSMinY(box) + kLine)];
    strokePath(path);
}

static void speaker(NSRect box, int waves) {
    CGFloat h = NSHeight(box);
    NSBezierPath *body = [NSBezierPath bezierPath];

    [body moveToPoint: NSMakePoint(NSMinX(box), NSMidY(box) - h * 0.2)];
    [body lineToPoint: NSMakePoint(NSMinX(box) + h * 0.25, NSMidY(box) - h * 0.2)];
    [body lineToPoint: NSMakePoint(NSMinX(box) + h * 0.55, NSMinY(box))];
    [body lineToPoint: NSMakePoint(NSMinX(box) + h * 0.55, NSMaxY(box))];
    [body lineToPoint: NSMakePoint(NSMinX(box) + h * 0.25, NSMidY(box) + h * 0.2)];
    [body lineToPoint: NSMakePoint(NSMinX(box), NSMidY(box) + h * 0.2)];
    [body closePath];
    [body fill];
    NSPoint c = NSMakePoint(NSMinX(box) + h * 0.55, NSMidY(box));
    for (int i = 1; i <= waves; i++) {
        NSBezierPath *wave = [NSBezierPath bezierPath];
        [wave appendBezierPathWithArcWithCenter: c radius: h * 0.2 * i + 1 startAngle: -45 endAngle: 45];
        [wave setLineWidth: 1.2];
        [wave stroke];
    }
}

static void volumeDown(NSRect box) { speaker(box, 1); }
static void volumeUp(NSRect box) { speaker(box, 3); }

// QUIRK: the sort indicators are 9 x 9 point template images of a chevron about 1.25 points thick, black at 75%
// opacity, 7 points wide and 4 points high in the middle of the image (pointing up for ascending, down for
// descending), its tip flattened and its ends cut square. Evidence: black-box renders of
// +[NSImage imageNamed:@"NSAscendingSortIndicator"] / @"NSDescendingSortIndicator" over white on macOS 10.14.4 at
// 1x and 3x (tier 2): size 9 x 9, isTemplate YES, coverage rows 2..6 from the top (3..7 for descending), darkest
// (64,64,64). The outline below is our own polygon fitted to those renders.
// Test: appkit-table-header-aqua.m (test_quirk_sort_indicator_images)
static void sortChevron(NSRect box, BOOL up) {
    // (x, y) in a 9 x 9 box, y measured from the top for a chevron pointing up
    static const CGFloat outline[][2] = {{1.0, 5.23}, {4.23, 2.0}, {4.77, 2.0}, {8.0, 5.23}, {8.0, 6.0},
                                         {6.9, 6.0},  {4.5, 3.6},  {2.1, 6.0},  {1.0, 6.0}};
    NSBezierPath *path = [NSBezierPath bezierPath];
    CGFloat sx = NSWidth(box) / 9.0, sy = NSHeight(box) / 9.0;

    for (size_t i = 0; i < sizeof(outline) / sizeof(outline[0]); i++) {
        CGFloat y = up ? 9.0 - outline[i][1] : outline[i][1];
        NSPoint point = NSMakePoint(NSMinX(box) + outline[i][0] * sx, NSMinY(box) + y * sy);

        if (i == 0)
            [path moveToPoint: point];
        else
            [path lineToPoint: point];
    }
    [path closePath];
    [[NSColor colorWithCalibratedWhite: 0 alpha: 0.75] setFill];
    [path fill];
}
static void ascendingSortIndicator(NSRect box) { sortChevron(box, YES); }
static void descendingSortIndicator(NSRect box) { sortChevron(box, NO); }

// Point sizes from macOS 10.14.4. The Touch Bar images are 30 points high; their glyph is drawn in the
// middle, in the height given by kTouchBarGlyphHeight.
static const CGFloat kTouchBarGlyphHeight = 14;

static const NSSystemTemplate systemTemplates[] = {
        {@"NSActionTemplate", 14, 14, gear},
        {@"NSAscendingSortIndicator", 9, 9, ascendingSortIndicator},
        {@"NSDescendingSortIndicator", 9, 9, descendingSortIndicator},
        {@"NSBluetoothTemplate", 7, 14, bluetooth},
        {@"NSBookmarksTemplate", 17, 18, bookmarks},
        {@"NSColumnViewTemplate", 16, 10, columnView},
        {@"NSEnterFullScreenTemplate", 15, 15, enterFullScreen},
        {@"NSExitFullScreenTemplate", 15, 15, exitFullScreen},
        {@"NSFlowViewTemplate", 18, 10, flowView},
        {@"NSFollowLinkFreestandingTemplate", 14, 14, followLinkFreestanding},
        {@"NSGoBackTemplate", 9, 12, goLeft},
        {@"NSGoForwardTemplate", 9, 12, goRight},
        {@"NSGoLeftTemplate", 9, 12, goLeft},
        {@"NSGoRightTemplate", 9, 12, goRight},
        {@"NSHomeTemplate", 14, 14, home},
        {@"NSIChatTheaterTemplate", 15, 13, theater},
        {@"NSIconViewTemplate", 14, 10, iconView},
        {@"NSInvalidDataFreestandingTemplate", 14, 14, invalidDataFreestanding},
        {@"NSLeftFacingTriangleTemplate", 9, 12, leftTriangle},
        {@"NSListViewTemplate", 14, 10, listView},
        {@"NSLockLockedTemplate", 10, 14, lockLocked},
        {@"NSLockUnlockedTemplate", 10, 14, lockUnlocked},
        {@"NSPathTemplate", 16, 10, path},
        {@"NSQuickLookTemplate", 19, 12, quickLook},
        {@"NSRefreshFreestandingTemplate", 14, 14, refreshFreestanding},
        {@"NSRefreshTemplate", 11, 15, circularArrow},
        {@"NSRevealFreestandingTemplate", 14, 14, revealFreestanding},
        {@"NSRightFacingTriangleTemplate", 9, 12, rightTriangle},
        {@"NSShareTemplate", 11, 16, share},
        {@"NSSlideshowTemplate", 17, 14, slideshow},
        {@"NSSmartBadgeTemplate", 14, 14, smartBadge},
        {@"NSStopProgressFreestandingTemplate", 14, 14, stopProgressFreestanding},
        {@"NSStopProgressTemplate", 11, 11, stopProgress},

        {@"NSTouchBarAddTemplate", 14, 30, plus},
        {@"NSTouchBarBookmarksTemplate", 22, 30, bookmarks},
        {@"NSTouchBarEnterFullScreenTemplate", 18, 30, enterFullScreen},
        {@"NSTouchBarExitFullScreenTemplate", 18, 30, exitFullScreen},
        {@"NSTouchBarFastForwardTemplate", 22, 30, fastForward},
        {@"NSTouchBarGoBackTemplate", 10, 30, goLeft},
        {@"NSTouchBarGoDownTemplate", 16, 30, goDown},
        {@"NSTouchBarGoForwardTemplate", 10, 30, goRight},
        {@"NSTouchBarGoUpTemplate", 16, 30, goUp},
        {@"NSTouchBarIconViewTemplate", 20, 30, iconView},
        {@"NSTouchBarListViewTemplate", 18, 30, listView},
        {@"NSTouchBarPauseTemplate", 11, 30, pauseBars},
        {@"NSTouchBarPlayPauseTemplate", 23, 30, playPause},
        {@"NSTouchBarPlayTemplate", 14, 30, play},
        {@"NSTouchBarQuickLookTemplate", 22, 30, quickLook},
        {@"NSTouchBarRecordStartTemplate", 14, 30, recordStart},
        {@"NSTouchBarRecordStopTemplate", 12, 30, recordStop},
        {@"NSTouchBarRefreshTemplate", 19, 30, circularArrow},
        {@"NSTouchBarRemoveTemplate", 14, 30, minus},
        {@"NSTouchBarRewindTemplate", 22, 30, rewindTriangles},
        {@"NSTouchBarSearchTemplate", 19, 30, search},
        {@"NSTouchBarShareTemplate", 15, 30, share},
        {@"NSTouchBarSkipToEndTemplate", 12, 30, skipToEnd},
        {@"NSTouchBarSkipToStartTemplate", 12, 30, skipToStart},
        {@"NSTouchBarSlideshowTemplate", 22, 30, slideshow},
        {@"NSTouchBarVolumeDownTemplate", 15, 30, volumeDown},
        {@"NSTouchBarVolumeUpTemplate", 23, 30, volumeUp},
};

NSImage *NSImageSystemTemplateNamed(NSString *name) {
    if (![name hasSuffix: @"Template"] && ![name hasSuffix: @"SortIndicator"])
        return nil;

    for (size_t i = 0; i < sizeof(systemTemplates) / sizeof(systemTemplates[0]); i++) {
        const NSSystemTemplate *entry = &systemTemplates[i];

        if (![name isEqualToString: entry->name])
            continue;

        NSSize size = NSMakeSize(entry->width, entry->height);
        BOOL touchBar = [name hasPrefix: @"NSTouchBar"];
        NSSystemTemplateDraw draw = entry->draw;
        NSImage *image = [NSImage imageWithSize: size
                                        flipped: NO
                                 drawingHandler: ^BOOL(NSRect rect) {
            NSRect box = NSMakeRect(0, 0, size.width, size.height);

            if (touchBar)
                box = NSMakeRect(0, floor((size.height - kTouchBarGlyphHeight) / 2), size.width,
                                 kTouchBarGlyphHeight);
            [[NSColor blackColor] set];
            draw(box);
            return YES;
        }];

        [image setTemplate: YES];
        [image setName: name];
        return image;
    }
    return nil;
}
