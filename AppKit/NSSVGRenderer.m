/*
 * Copyright (C) 2026 Darling Developers
 */
#import "NSSVGRenderer.h"
#import <AppKit/NSAffineTransform.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSGraphicsContext.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSCharacterSet.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSString.h>
#import <Foundation/NSXMLParser.h>
#include <ctype.h>
#include <math.h>
#include <stdlib.h>

@interface _NSSVGState : NSObject <NSCopying> {
@public
    NSColor *_fillColor;
    NSColor *_strokeColor;
    CGFloat _fillOpacity;
    CGFloat _strokeOpacity;
    CGFloat _opacity;
    CGFloat _lineWidth;
    NSWindingRule _windingRule;
    NSLineCapStyle _lineCap;
    NSLineJoinStyle _lineJoin;
    BOOL _hasFill;
    BOOL _hasStroke;
}
@end

@implementation _NSSVGState
- (instancetype) init {
    if ((self = [super init])) {
        _fillColor = [[NSColor blackColor] retain];
        _strokeColor = nil;
        _fillOpacity = 1.0;
        _strokeOpacity = 1.0;
        _opacity = 1.0;
        _lineWidth = 1.0;
        _windingRule = NSNonZeroWindingRule;
        _lineCap = NSButtLineCapStyle;
        _lineJoin = NSMiterLineJoinStyle;
        _hasFill = YES;
        _hasStroke = NO;
    }
    return self;
}
- (id) copyWithZone: (NSZone *) zone {
    _NSSVGState *c = [[_NSSVGState allocWithZone: zone] init];
    [c->_fillColor release];
    c->_fillColor = [_fillColor retain];
    [c->_strokeColor release];
    c->_strokeColor = [_strokeColor retain];
    c->_fillOpacity = _fillOpacity;
    c->_strokeOpacity = _strokeOpacity;
    c->_opacity = _opacity;
    c->_lineWidth = _lineWidth;
    c->_windingRule = _windingRule;
    c->_lineCap = _lineCap;
    c->_lineJoin = _lineJoin;
    c->_hasFill = _hasFill;
    c->_hasStroke = _hasStroke;
    return c;
}
- (void) dealloc {
    [_fillColor release];
    [_strokeColor release];
    [super dealloc];
}
@end

static NSColor *parseSVGColor(NSString *str, BOOL *isNone) {
    *isNone = NO;
    if (str == nil)
        return nil;
    NSString *s = [[str stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    if ([s length] == 0 || [s isEqualToString: @"none"]) {
        *isNone = YES;
        return nil;
    }
    if ([s isEqualToString: @"black"] || [s isEqualToString: @"currentcolor"])
        return [NSColor blackColor];
    if ([s isEqualToString: @"white"])
        return [NSColor whiteColor];
    if ([s isEqualToString: @"red"])
        return [NSColor colorWithCalibratedRed: 1 green: 0 blue: 0 alpha: 1];
    if ([s isEqualToString: @"green"])
        return [NSColor colorWithCalibratedRed: 0 green: 0.5 blue: 0 alpha: 1];
    if ([s isEqualToString: @"blue"])
        return [NSColor colorWithCalibratedRed: 0 green: 0 blue: 1 alpha: 1];
    if ([s isEqualToString: @"transparent"])
        return [NSColor clearColor];
    if ([s hasPrefix: @"#"]) {
        unsigned int val = 0;
        const char *hex = [[s substringFromIndex: 1] UTF8String];
        size_t len = strlen(hex);
        if (sscanf(hex, "%x", &val) == 1) {
            if (len == 3) {
                return [NSColor colorWithCalibratedRed: ((val >> 8) & 0xF) / 15.0
                                                 green: ((val >> 4) & 0xF) / 15.0
                                                  blue: (val & 0xF) / 15.0
                                                 alpha: 1.0];
            } else if (len == 6) {
                return [NSColor colorWithCalibratedRed: ((val >> 16) & 0xFF) / 255.0
                                                 green: ((val >> 8) & 0xFF) / 255.0
                                                  blue: (val & 0xFF) / 255.0
                                                 alpha: 1.0];
            } else if (len == 8) {
                return [NSColor colorWithCalibratedRed: ((val >> 24) & 0xFF) / 255.0
                                                 green: ((val >> 16) & 0xFF) / 255.0
                                                  blue: ((val >> 8) & 0xFF) / 255.0
                                                 alpha: (val & 0xFF) / 255.0];
            }
        }
    }
    if ([s hasPrefix: @"rgb("] && [s hasSuffix: @")"]) {
        NSArray *parts = [[s substringWithRange: NSMakeRange(4, [s length] - 5)] componentsSeparatedByString: @","];
        if ([parts count] >= 3) {
            CGFloat r = [[parts objectAtIndex: 0] doubleValue] / 255.0;
            CGFloat g = [[parts objectAtIndex: 1] doubleValue] / 255.0;
            CGFloat b = [[parts objectAtIndex: 2] doubleValue] / 255.0;
            CGFloat a = [parts count] >= 4 ? [[parts objectAtIndex: 3] doubleValue] : 1.0;
            return [NSColor colorWithCalibratedRed: r green: g blue: b alpha: a];
        }
    }
    return [NSColor blackColor];
}

static void skipWSComma(const char **p) {
    while (**p && (isspace((unsigned char) **p) || **p == ','))
        (*p)++;
}

static BOOL readNumber(const char **p, CGFloat *out) {
    skipWSComma(p);
    if (!**p)
        return NO;
    char *end = NULL;
    double v = strtod(*p, &end);
    if (end == *p)
        return NO;
    *p = end;
    *out = (CGFloat) v;
    return YES;
}

static BOOL readFlag(const char **p, BOOL *out) {
    skipWSComma(p);
    if (**p == '0' || **p == '1') {
        *out = (**p == '1');
        (*p)++;
        return YES;
    }
    return NO;
}

// Converts an SVG elliptical arc from (x1, y1) to (x2, y2) into cubic Bezier segments.
static void appendSVGArc(NSBezierPath *path, CGFloat x1, CGFloat y1, CGFloat rx, CGFloat ry,
                         CGFloat phiDeg, BOOL largeArc, BOOL sweep, CGFloat x2, CGFloat y2) {
    if (!isfinite(x1) || !isfinite(y1) || !isfinite(rx) || !isfinite(ry) ||
        !isfinite(phiDeg) || !isfinite(x2) || !isfinite(y2))
        return;
    if (x1 == x2 && y1 == y2)
        return;
    if (rx == 0 || ry == 0) {
        [path lineToPoint: NSMakePoint(x2, y2)];
        return;
    }
    rx = fabs(rx);
    ry = fabs(ry);
    CGFloat phi = phiDeg * M_PI / 180.0;
    CGFloat cosPhi = cos(phi), sinPhi = sin(phi);
    CGFloat dx2 = (x1 - x2) * 0.5, dy2 = (y1 - y2) * 0.5;
    CGFloat x1p = cosPhi * dx2 + sinPhi * dy2;
    CGFloat y1p = -sinPhi * dx2 + cosPhi * dy2;

    CGFloat rx2 = rx * rx, ry2 = ry * ry;
    CGFloat x1p2 = x1p * x1p, y1p2 = y1p * y1p;
    CGFloat lambda = x1p2 / rx2 + y1p2 / ry2;
    if (lambda > 1.0) {
        CGFloat s = sqrt(lambda);
        rx *= s;
        ry *= s;
        rx2 = rx * rx;
        ry2 = ry * ry;
    }

    CGFloat num = MAX(0.0, rx2 * ry2 - rx2 * y1p2 - ry2 * x1p2);
    CGFloat den = rx2 * y1p2 + ry2 * x1p2;
    CGFloat factor = (den > 0) ? sqrt(num / den) : 0.0;
    if (largeArc == sweep)
        factor = -factor;
    CGFloat cxp = factor * (rx * y1p) / ry;
    CGFloat cyp = factor * (-ry * x1p) / rx;

    CGFloat cx = cosPhi * cxp - sinPhi * cyp + (x1 + x2) * 0.5;
    CGFloat cy = sinPhi * cxp + cosPhi * cyp + (y1 + y2) * 0.5;

    CGFloat ux = (x1p - cxp) / rx, uy = (y1p - cyp) / ry;
    CGFloat vx = (-x1p - cxp) / rx, vy = (-y1p - cyp) / ry;
    CGFloat n1 = sqrt(ux * ux + uy * uy);
    if (n1 == 0 || !isfinite(n1))
        return;
    CGFloat theta1 = acos(MAX(-1.0, MIN(1.0, ux / n1)));
    if (uy < 0)
        theta1 = -theta1;

    CGFloat n2 = sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy));
    if (n2 == 0 || !isfinite(n2))
        return;
    CGFloat dot = ux * vx + uy * vy;
    CGFloat dtheta = acos(MAX(-1.0, MIN(1.0, dot / n2)));
    if (ux * vy - uy * vx < 0)
        dtheta = -dtheta;
    if (!sweep && dtheta > 0)
        dtheta -= 2.0 * M_PI;
    else if (sweep && dtheta < 0)
        dtheta += 2.0 * M_PI;
    if (!isfinite(dtheta) || fabs(dtheta) < 1e-9)
        return;

    int segs = MAX(1, (int) ceil(fabs(dtheta) / (M_PI * 0.5)));
    CGFloat delta = dtheta / segs;
    CGFloat t = (8.0 / 3.0) * sin(delta * 0.25) * sin(delta * 0.25) / sin(delta * 0.5);

    for (int i = 0; i < segs; i++) {
        CGFloat a1 = theta1 + i * delta;
        CGFloat a2 = a1 + delta;
        CGFloat c1 = cos(a1), s1 = sin(a1), c2 = cos(a2), s2 = sin(a2);
        CGFloat e1x = c1 - t * s1, e1y = s1 + t * c1;
        CGFloat e2x = c2 + t * s2, e2y = s2 - t * c2;

        NSPoint cp1 = NSMakePoint(cx + cosPhi * rx * e1x - sinPhi * ry * e1y,
                                  cy + sinPhi * rx * e1x + cosPhi * ry * e1y);
        NSPoint cp2 = NSMakePoint(cx + cosPhi * rx * e2x - sinPhi * ry * e2y,
                                  cy + sinPhi * rx * e2x + cosPhi * ry * e2y);
        NSPoint end = NSMakePoint(cx + cosPhi * rx * c2 - sinPhi * ry * s2,
                                  cy + sinPhi * rx * c2 + cosPhi * ry * s2);
        [path curveToPoint: end controlPoint1: cp1 controlPoint2: cp2];
    }
}

static NSBezierPath *parseSVGPathData(NSString *d) {
    NSBezierPath *path = [NSBezierPath bezierPath];
    const char *p = [d UTF8String];
    if (!p)
        return path;

    CGFloat cx = 0, cy = 0, sx = 0, sy = 0;
    CGFloat lastCpX = 0, lastCpY = 0;
    char cmd = 0, prevCmd = 0;

    while (*p) {
        skipWSComma(&p);
        if (!*p)
            break;
        if (isalpha((unsigned char) *p)) {
            cmd = *p++;
        } else if (cmd == 0) {
            break;
        } else if (cmd == 'M') {
            cmd = 'L';
        } else if (cmd == 'm') {
            cmd = 'l';
        }

        BOOL rel = islower((unsigned char) cmd);
        char uc = (char) toupper((unsigned char) cmd);

        if (uc == 'Z') {
            [path closePath];
            cx = sx;
            cy = sy;
            prevCmd = cmd;
            cmd = 0;
            continue;
        }

        CGFloat a, b, c, d1, e, f;
        if (uc == 'M') {
            if (!readNumber(&p, &a) || !readNumber(&p, &b)) break;
            if (rel) { a += cx; b += cy; }
            [path moveToPoint: NSMakePoint(a, b)];
            cx = sx = a; cy = sy = b;
            prevCmd = cmd;
            cmd = rel ? 'l' : 'L';
        } else if (uc == 'L') {
            if (!readNumber(&p, &a) || !readNumber(&p, &b)) break;
            if (rel) { a += cx; b += cy; }
            [path lineToPoint: NSMakePoint(a, b)];
            cx = a; cy = b;
            prevCmd = cmd;
        } else if (uc == 'H') {
            if (!readNumber(&p, &a)) break;
            if (rel) a += cx;
            [path lineToPoint: NSMakePoint(a, cy)];
            cx = a;
            prevCmd = cmd;
        } else if (uc == 'V') {
            if (!readNumber(&p, &b)) break;
            if (rel) b += cy;
            [path lineToPoint: NSMakePoint(cx, b)];
            cy = b;
            prevCmd = cmd;
        } else if (uc == 'C') {
            if (!readNumber(&p, &a) || !readNumber(&p, &b) ||
                !readNumber(&p, &c) || !readNumber(&p, &d1) ||
                !readNumber(&p, &e) || !readNumber(&p, &f)) break;
            if (rel) { a += cx; b += cy; c += cx; d1 += cy; e += cx; f += cy; }
            [path curveToPoint: NSMakePoint(e, f) controlPoint1: NSMakePoint(a, b) controlPoint2: NSMakePoint(c, d1)];
            lastCpX = c; lastCpY = d1;
            cx = e; cy = f;
            prevCmd = cmd;
        } else if (uc == 'S') {
            if (!readNumber(&p, &c) || !readNumber(&p, &d1) ||
                !readNumber(&p, &e) || !readNumber(&p, &f)) break;
            if (rel) { c += cx; d1 += cy; e += cx; f += cy; }
            char puc = (char) toupper((unsigned char) prevCmd);
            if (puc == 'C' || puc == 'S') {
                a = 2 * cx - lastCpX; b = 2 * cy - lastCpY;
            } else {
                a = cx; b = cy;
            }
            [path curveToPoint: NSMakePoint(e, f) controlPoint1: NSMakePoint(a, b) controlPoint2: NSMakePoint(c, d1)];
            lastCpX = c; lastCpY = d1;
            cx = e; cy = f;
            prevCmd = cmd;
        } else if (uc == 'Q') {
            if (!readNumber(&p, &a) || !readNumber(&p, &b) ||
                !readNumber(&p, &e) || !readNumber(&p, &f)) break;
            if (rel) { a += cx; b += cy; e += cx; f += cy; }
            CGFloat cp1x = cx + (2.0 / 3.0) * (a - cx);
            CGFloat cp1y = cy + (2.0 / 3.0) * (b - cy);
            CGFloat cp2x = e + (2.0 / 3.0) * (a - e);
            CGFloat cp2y = f + (2.0 / 3.0) * (b - f);
            [path curveToPoint: NSMakePoint(e, f) controlPoint1: NSMakePoint(cp1x, cp1y) controlPoint2: NSMakePoint(cp2x, cp2y)];
            lastCpX = a; lastCpY = b;
            cx = e; cy = f;
            prevCmd = cmd;
        } else if (uc == 'T') {
            if (!readNumber(&p, &e) || !readNumber(&p, &f)) break;
            if (rel) { e += cx; f += cy; }
            char puc = (char) toupper((unsigned char) prevCmd);
            if (puc == 'Q' || puc == 'T') {
                a = 2 * cx - lastCpX; b = 2 * cy - lastCpY;
            } else {
                a = cx; b = cy;
            }
            CGFloat cp1x = cx + (2.0 / 3.0) * (a - cx);
            CGFloat cp1y = cy + (2.0 / 3.0) * (b - cy);
            CGFloat cp2x = e + (2.0 / 3.0) * (a - e);
            CGFloat cp2y = f + (2.0 / 3.0) * (b - f);
            [path curveToPoint: NSMakePoint(e, f) controlPoint1: NSMakePoint(cp1x, cp1y) controlPoint2: NSMakePoint(cp2x, cp2y)];
            lastCpX = a; lastCpY = b;
            cx = e; cy = f;
            prevCmd = cmd;
        } else if (uc == 'A') {
            BOOL largeArc = NO, sweep = NO;
            if (!readNumber(&p, &a) || !readNumber(&p, &b) || !readNumber(&p, &c) ||
                !readFlag(&p, &largeArc) || !readFlag(&p, &sweep) ||
                !readNumber(&p, &e) || !readNumber(&p, &f)) break;
            if (rel) { e += cx; f += cy; }
            appendSVGArc(path, cx, cy, a, b, c, largeArc, sweep, e, f);
            cx = e; cy = f;
            prevCmd = cmd;
        } else {
            break;
        }
    }
    return path;
}

static void applySVGTransform(NSString *transformStr) {
    if ([transformStr length] == 0)
        return;
    const char *p = [transformStr UTF8String];
    while (*p) {
        while (*p && (isspace((unsigned char) *p) || *p == ','))
            p++;
        if (!*p)
            break;
        const char *nameStart = p;
        while (*p && isalpha((unsigned char) *p))
            p++;
        size_t nlen = (size_t) (p - nameStart);
        while (*p && *p != '(')
            p++;
        if (*p != '(')
            break;
        p++;
        CGFloat vals[6] = {0};
        int count = 0;
        while (count < 6 && readNumber(&p, &vals[count]))
            count++;
        while (*p && *p != ')')
            p++;
        if (*p == ')')
            p++;

        NSAffineTransform *xf = [NSAffineTransform transform];
        if (nlen == 9 && strncmp(nameStart, "translate", 9) == 0 && count >= 1) {
            [xf translateXBy: vals[0] yBy: count >= 2 ? vals[1] : 0];
        } else if (nlen == 5 && strncmp(nameStart, "scale", 5) == 0 && count >= 1) {
            [xf scaleXBy: vals[0] yBy: count >= 2 ? vals[1] : vals[0]];
        } else if (nlen == 6 && strncmp(nameStart, "rotate", 6) == 0 && count >= 1) {
            if (count >= 3) {
                [xf translateXBy: vals[1] yBy: vals[2]];
                [xf rotateByDegrees: vals[0]];
                [xf translateXBy: -vals[1] yBy: -vals[2]];
            } else {
                [xf rotateByDegrees: vals[0]];
            }
        } else if (nlen == 6 && strncmp(nameStart, "matrix", 6) == 0 && count == 6) {
            NSAffineTransformStruct s = { vals[0], vals[1], vals[2], vals[3], vals[4], vals[5] };
            [xf setTransformStruct: s];
        }
        [xf concat];
    }
}

@interface _NSSVGParserDelegate : NSObject <NSXMLParserDelegate> {
@public
    NSMutableArray *_stateStack;
    NSSize _pointSize;
    CGFloat _scale;
    NSBitmapImageRep *_rep;
    NSGraphicsContext *_savedContext;
    NSUInteger _svgDepth;
    BOOL _contextActive;
}
@end

@implementation _NSSVGParserDelegate

- (instancetype) initWithPointSize: (NSSize) pointSize scale: (CGFloat) scale {
    if ((self = [super init])) {
        _stateStack = [[NSMutableArray alloc] initWithObjects: [[[_NSSVGState alloc] init] autorelease], nil];
        _pointSize = pointSize;
        _scale = (isfinite(scale) && scale > 0) ? scale : 1.0;
    }
    return self;
}

- (void) _teardownContext {
    if (!_contextActive)
        return;
    while ([_stateStack count] > 1) {
        [_stateStack removeLastObject];
        [NSGraphicsContext restoreGraphicsState];
    }
    [NSGraphicsContext setCurrentContext: _savedContext];
    [_savedContext release];
    _savedContext = nil;
    _contextActive = NO;
}

- (void) dealloc {
    [self _teardownContext];
    [_stateStack release];
    [_rep release];
    [super dealloc];
}

- (void) parser: (NSXMLParser *) parser didStartElement: (NSString *) elementName
   namespaceURI: (NSString *) namespaceURI qualifiedName: (NSString *) qName
     attributes: (NSDictionary *) attrs
{
    if ([elementName isEqualToString: @"svg"]) {
        _svgDepth++;
        if (_rep == nil && _svgDepth == 1) {
            CGFloat w = [[attrs objectForKey: @"width"] doubleValue];
            CGFloat h = [[attrs objectForKey: @"height"] doubleValue];
            if (!isfinite(w) || w < 0) w = 0;
            if (!isfinite(h) || h < 0) h = 0;
            CGFloat vbX = 0, vbY = 0, vbW = w, vbH = h;
            NSString *viewBox = [attrs objectForKey: @"viewBox"];
            if (viewBox != nil) {
                const char *p = [viewBox UTF8String];
                CGFloat x, y, vw, vh;
                if (p && readNumber(&p, &x) && readNumber(&p, &y) && readNumber(&p, &vw) && readNumber(&p, &vh) &&
                    isfinite(x) && isfinite(y) && isfinite(vw) && isfinite(vh)) {
                    vbX = x; vbY = y; vbW = vw; vbH = vh;
                }
            }
            if (vbW <= 0) vbW = 16;
            if (vbH <= 0) vbH = 16;
            if (!isfinite(_pointSize.width) || !isfinite(_pointSize.height) ||
                _pointSize.width <= 0 || _pointSize.height <= 0)
                _pointSize = NSMakeSize(w > 0 ? w : vbW, h > 0 ? h : vbH);
            CGFloat rawW = _pointSize.width * _scale;
            CGFloat rawH = _pointSize.height * _scale;
            if (!isfinite(rawW) || !isfinite(rawH) || rawW > 16384 || rawH > 16384)
                return;
            NSInteger pxW = MAX(1, MIN(16384, (NSInteger) ceil(rawW)));
            NSInteger pxH = MAX(1, MIN(16384, (NSInteger) ceil(rawH)));

            _rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes: NULL pixelsWide: pxW pixelsHigh: pxH
                                                        bitsPerSample: 8 samplesPerPixel: 4 hasAlpha: YES isPlanar: NO
                                                       colorSpaceName: NSDeviceRGBColorSpace
                                                          bytesPerRow: pxW * 4 bitsPerPixel: 32];
            if (_rep == nil)
                return;
            [_rep setSize: _pointSize];
            _savedContext = [[NSGraphicsContext currentContext] retain];
            [NSGraphicsContext setCurrentContext: [NSGraphicsContext graphicsContextWithBitmapImageRep: _rep]];
            _contextActive = YES;

            NSAffineTransform *xf = [NSAffineTransform transform];
            [xf translateXBy: 0 yBy: pxH];
            [xf scaleXBy: (CGFloat) pxW / vbW yBy: -(CGFloat) pxH / vbH];
            [xf translateXBy: -vbX yBy: -vbY];
            [xf concat];
            return;
        }
    }

    if (!_contextActive)
        return;

    [NSGraphicsContext saveGraphicsState];
    _NSSVGState *state = [[_stateStack lastObject] copy];
    [_stateStack addObject: state];
    [state release];

    NSString *fillAttr = [attrs objectForKey: @"fill"];
    if (fillAttr != nil) {
        BOOL none = NO;
        NSColor *c = parseSVGColor(fillAttr, &none);
        [state->_fillColor release];
        state->_fillColor = [c retain];
        state->_hasFill = !none;
    }
    NSString *strokeAttr = [attrs objectForKey: @"stroke"];
    if (strokeAttr != nil) {
        BOOL none = NO;
        NSColor *c = parseSVGColor(strokeAttr, &none);
        [state->_strokeColor release];
        state->_strokeColor = [c retain];
        state->_hasStroke = !none;
    }
    if ([attrs objectForKey: @"fill-opacity"] != nil)
        state->_fillOpacity = [[attrs objectForKey: @"fill-opacity"] doubleValue];
    if ([attrs objectForKey: @"stroke-opacity"] != nil)
        state->_strokeOpacity = [[attrs objectForKey: @"stroke-opacity"] doubleValue];
    if ([attrs objectForKey: @"opacity"] != nil)
        state->_opacity *= [[attrs objectForKey: @"opacity"] doubleValue];
    if ([attrs objectForKey: @"stroke-width"] != nil)
        state->_lineWidth = [[attrs objectForKey: @"stroke-width"] doubleValue];
    if ([[attrs objectForKey: @"fill-rule"] isEqualToString: @"evenodd"])
        state->_windingRule = NSEvenOddWindingRule;
    else if ([[attrs objectForKey: @"fill-rule"] isEqualToString: @"nonzero"])
        state->_windingRule = NSNonZeroWindingRule;

    NSString *cap = [attrs objectForKey: @"stroke-linecap"];
    if ([cap isEqualToString: @"round"]) state->_lineCap = NSRoundLineCapStyle;
    else if ([cap isEqualToString: @"square"]) state->_lineCap = NSSquareLineCapStyle;
    else if ([cap isEqualToString: @"butt"]) state->_lineCap = NSButtLineCapStyle;

    NSString *join = [attrs objectForKey: @"stroke-linejoin"];
    if ([join isEqualToString: @"round"]) state->_lineJoin = NSRoundLineJoinStyle;
    else if ([join isEqualToString: @"bevel"]) state->_lineJoin = NSBevelLineJoinStyle;
    else if ([join isEqualToString: @"miter"]) state->_lineJoin = NSMiterLineJoinStyle;

    applySVGTransform([attrs objectForKey: @"transform"]);

    NSBezierPath *path = nil;
    if ([elementName isEqualToString: @"path"]) {
        path = parseSVGPathData([attrs objectForKey: @"d"]);
    } else if ([elementName isEqualToString: @"rect"]) {
        CGFloat x = [[attrs objectForKey: @"x"] doubleValue];
        CGFloat y = [[attrs objectForKey: @"y"] doubleValue];
        CGFloat w = [[attrs objectForKey: @"width"] doubleValue];
        CGFloat h = [[attrs objectForKey: @"height"] doubleValue];
        CGFloat rx = [[attrs objectForKey: @"rx"] doubleValue];
        CGFloat ry = [[attrs objectForKey: @"ry"] doubleValue];
        if (w > 0 && h > 0) {
            if (rx > 0 || ry > 0) {
                if (rx == 0) rx = ry;
                if (ry == 0) ry = rx;
                path = [NSBezierPath bezierPathWithRoundedRect: NSMakeRect(x, y, w, h) xRadius: rx yRadius: ry];
            } else {
                path = [NSBezierPath bezierPathWithRect: NSMakeRect(x, y, w, h)];
            }
        }
    } else if ([elementName isEqualToString: @"circle"]) {
        CGFloat cx = [[attrs objectForKey: @"cx"] doubleValue];
        CGFloat cy = [[attrs objectForKey: @"cy"] doubleValue];
        CGFloat r = [[attrs objectForKey: @"r"] doubleValue];
        if (r > 0)
            path = [NSBezierPath bezierPathWithOvalInRect: NSMakeRect(cx - r, cy - r, 2 * r, 2 * r)];
    } else if ([elementName isEqualToString: @"ellipse"]) {
        CGFloat cx = [[attrs objectForKey: @"cx"] doubleValue];
        CGFloat cy = [[attrs objectForKey: @"cy"] doubleValue];
        CGFloat rx = [[attrs objectForKey: @"rx"] doubleValue];
        CGFloat ry = [[attrs objectForKey: @"ry"] doubleValue];
        if (rx > 0 && ry > 0)
            path = [NSBezierPath bezierPathWithOvalInRect: NSMakeRect(cx - rx, cy - ry, 2 * rx, 2 * ry)];
    } else if ([elementName isEqualToString: @"line"]) {
        path = [NSBezierPath bezierPath];
        [path moveToPoint: NSMakePoint([[attrs objectForKey: @"x1"] doubleValue], [[attrs objectForKey: @"y1"] doubleValue])];
        [path lineToPoint: NSMakePoint([[attrs objectForKey: @"x2"] doubleValue], [[attrs objectForKey: @"y2"] doubleValue])];
    } else if ([elementName isEqualToString: @"polyline"] || [elementName isEqualToString: @"polygon"]) {
        NSString *pts = [attrs objectForKey: @"points"];
        const char *p = [pts UTF8String];
        if (p) {
            path = [NSBezierPath bezierPath];
            CGFloat x, y;
            BOOL first = YES;
            while (readNumber(&p, &x) && readNumber(&p, &y)) {
                if (first) { [path moveToPoint: NSMakePoint(x, y)]; first = NO; }
                else [path lineToPoint: NSMakePoint(x, y)];
            }
            if ([elementName isEqualToString: @"polygon"] && !first)
                [path closePath];
        }
    }

    if (path != nil && ![path isEmpty]) {
        if (state->_hasFill && state->_fillColor != nil) {
            [path setWindingRule: state->_windingRule];
            CGFloat alpha = [state->_fillColor alphaComponent] * state->_fillOpacity * state->_opacity;
            [[state->_fillColor colorWithAlphaComponent: alpha] setFill];
            [path fill];
        }
        if (state->_hasStroke && state->_strokeColor != nil && state->_lineWidth > 0) {
            [path setLineWidth: state->_lineWidth];
            [path setLineCapStyle: state->_lineCap];
            [path setLineJoinStyle: state->_lineJoin];
            CGFloat alpha = [state->_strokeColor alphaComponent] * state->_strokeOpacity * state->_opacity;
            [[state->_strokeColor colorWithAlphaComponent: alpha] setStroke];
            [path stroke];
        }
    }
}

- (void) parser: (NSXMLParser *) parser didEndElement: (NSString *) elementName
   namespaceURI: (NSString *) namespaceURI qualifiedName: (NSString *) qName
{
    if ([elementName isEqualToString: @"svg"]) {
        if (_svgDepth > 0)
            _svgDepth--;
        if (_svgDepth == 0) {
            [self _teardownContext];
            return;
        }
    }
    if (_contextActive && [_stateStack count] > 1) {
        [_stateStack removeLastObject];
        [NSGraphicsContext restoreGraphicsState];
    }
}

@end

NSBitmapImageRep *NSRenderSVGData(NSData *svgData, NSSize pointSize, CGFloat scale) {
    if ([svgData length] == 0)
        return nil;
    _NSSVGParserDelegate *delegate = [[_NSSVGParserDelegate alloc] initWithPointSize: pointSize scale: scale];
    NSXMLParser *parser = [[NSXMLParser alloc] initWithData: svgData];
    [parser setDelegate: delegate];
    BOOL ok = [parser parse];
    NSBitmapImageRep *rep = ok ? [[delegate->_rep retain] autorelease] : nil;
    [parser release];
    [delegate release];
    return rep;
}
