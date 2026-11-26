/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * Darling's own drawings of a few system symbols, glyphs for common symbol names
 * rendered from the Adwaita symbolic icons in SystemSymbols (see
 * SystemSymbols/COPYING.Adwaita), and the generic glyph drawn for every other
 * symbol name. They are not Apple's symbol artwork.
 */
#import "NSSVGRenderer.h"
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSImage.h>
#import <Foundation/NSBundle.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDictionary.h>
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

static const struct {
    const char *symbol;
    const char *svg;
} adwaitaSymbols[] = {
    { "arrow.clockwise", "view-refresh-symbolic" },
    { "arrow.counterclockwise", "edit-undo-symbolic" },
    { "arrow.up.forward.app", "focus-windows-symbolic" },
    { "arrow.up.right", "go-next-symbolic" },
    { "arrow.up.right.square", "focus-windows-symbolic" },
    { "book", "user-bookmarks-symbolic" },
    { "book.closed", "user-bookmarks-symbolic" },
    { "book.closed.fill", "user-bookmarks-symbolic" },
    { "bookmark", "user-bookmarks-symbolic" },
    { "bookmark.fill", "user-bookmarks-symbolic" },
    { "bubble.left.and.bubble.right", "chat-message-new-symbolic" },
    { "checkmark", "checkbox-checked-symbolic" },
    { "checkmark.circle", "checkbox-checked-symbolic" },
    { "chevron.down", "go-down-symbolic" },
    { "chevron.left", "go-previous-symbolic" },
    { "chevron.right", "go-next-symbolic" },
    { "chevron.right.2", "go-next-symbolic" },
    { "chevron.up", "go-up-symbolic" },
    { "doc", "document-new-symbolic" },
    { "doc.badge.gearshape", "preferences-system-symbolic" },
    { "doc.badge.gearshape.fill", "preferences-system-symbolic" },
    { "doc.plaintext", "document-new-symbolic" },
    { "doc.text", "document-new-symbolic" },
    { "ellipsis", "view-more-horizontal-symbolic" },
    { "ellipsis.circle", "view-more-horizontal-symbolic" },
    { "ellipsis.rectangle", "view-more-horizontal-symbolic" },
    { "ellipsis.rectangle.fill", "view-more-horizontal-symbolic" },
    { "envelope", "mail-unread-symbolic" },
    { "envelope.open", "mail-read-symbolic" },
    { "exclamationmark.triangle", "dialog-warning-symbolic" },
    { "eyeglasses", "view-reveal-symbolic" },
    { "eye.slash", "view-conceal-symbolic" },
    { "flag", "emoji-flags-symbolic" },
    { "gear", "preferences-system-symbolic" },
    { "gearshape", "preferences-system-symbolic" },
    { "gearshape.fill", "preferences-system-symbolic" },
    { "info", "dialog-information-symbolic" },
    { "info.circle", "dialog-information-symbolic" },
    { "info.circle.fill", "dialog-information-symbolic" },
    { "link", "insert-link-symbolic" },
    { "list", "view-list-symbolic" },
    { "list.bullet", "view-list-bullet-symbolic" },
    { "lock", "system-lock-screen-symbolic" },
    { "macwindow.stack", "focus-windows-symbolic" },
    { "magnifyingglass", "system-search-symbolic" },
    { "minus", "list-remove-symbolic" },
    { "minus.circle", "list-remove-symbolic" },
    { "minus.magnifyingglass", "zoom-out-symbolic" },
    { "paperclip", "mail-attachment-symbolic" },
    { "pause", "media-playback-pause-symbolic" },
    { "pencil", "document-edit-symbolic" },
    { "photo", "image-x-generic-symbolic" },
    { "pin", "view-pin-symbolic" },
    { "play", "media-playback-start-symbolic" },
    { "plus", "list-add-symbolic" },
    { "plus.circle", "list-add-symbolic" },
    { "plus.magnifyingglass", "zoom-in-symbolic" },
    { "plus.rectangle", "list-add-symbolic" },
    { "plus.square.dashed", "list-add-symbolic" },
    { "point.3.connected.trianglepath.dotted", "network-workgroup-symbolic" },
    { "printer", "document-print-symbolic" },
    { "questionmark.circle", "system-help-symbolic" },
    { "record", "media-record-symbolic" },
    { "rectangle.split.3x1", "view-dual-symbolic" },
    { "share", "document-send-symbolic" },
    { "sidebar", "sidebar-show-symbolic" },
    { "sidebar.left", "sidebar-show-symbolic" },
    { "sidebar.right", "sidebar-show-right-symbolic" },
    { "sparkles", "star-new-symbolic" },
    { "square.and.arrow.up", "document-send-symbolic" },
    { "square.and.pencil", "document-edit-symbolic" },
    { "square.grid.2x2", "view-grid-symbolic" },
    { "square.grid.3x2", "view-grid-symbolic" },
    { "star", "starred-symbolic" },
    { "star.fill", "starred-symbolic" },
    { "stop", "media-playback-stop-symbolic" },
    { "tag", "bookmark-new-symbolic" },
    { "text.page", "document-new-symbolic" },
    { "text.quote", "format-text-rich-symbolic" },
    { "trash", "user-trash-symbolic" },
    { "trash.fill", "user-trash-symbolic" },
    { "tray.and.arrow.down", "folder-download-symbolic" },
    { "xmark", "window-close-symbolic" },
    { "xmark.circle", "window-close-symbolic" },
    { "xmark.octagon", "dialog-error-symbolic" },
};

static const char *svgNameForSymbol(NSString *name) {
    const char *string = [name UTF8String];
    if (string == NULL)
        return NULL;
    for (size_t i = 0; i < sizeof(adwaitaSymbols) / sizeof(adwaitaSymbols[0]); i++)
        if (strcmp(adwaitaSymbols[i].symbol, string) == 0)
            return adwaitaSymbols[i].svg;
    return NULL;
}

static NSData *svgDataForName(const char *svgName) {
    static NSMutableDictionary *cache = nil;
    @synchronized([NSImage class]) {
        if (cache == nil)
            cache = [[NSMutableDictionary alloc] init];
        NSString *key = [NSString stringWithUTF8String: svgName];
        id cached = [cache objectForKey: key];
        if (cached != nil)
            return cached == (id) [NSNull null] ? nil : cached;
        NSBundle *bundle = [NSBundle bundleForClass: [NSImage class]];
        NSString *path = [bundle pathForResource: key ofType: @"svg" inDirectory: @"SystemSymbols"];
        NSData *data = path ? [NSData dataWithContentsOfFile: path] : nil;
        [cache setObject: data ? (id) data : (id) [NSNull null] forKey: key];
        return data;
    }
}

static NSBitmapImageRep *renderedRepForSymbol(const char *svgName, NSSize size) {
    static NSMutableDictionary *repCache = nil;
    @synchronized([NSImage class]) {
        if (repCache == nil)
            repCache = [[NSMutableDictionary alloc] init];
        NSString *key = [NSString stringWithFormat: @"%s:%.0fx%.0f", svgName, size.width, size.height];
        id cached = [repCache objectForKey: key];
        if (cached != nil)
            return cached == (id) [NSNull null] ? nil : cached;
        NSData *data = svgDataForName(svgName);
        NSBitmapImageRep *rep = data != nil ? NSRenderSVGData(data, size, 2.0) : nil;
        [repCache setObject: rep ? (id) rep : (id) [NSNull null] forKey: key];
        return rep;
    }
}

BOOL NSImageSymbolHasGlyph(NSString *name) {
    return drawerForName(name) != NULL || svgNameForSymbol(name) != NULL;
}

// Draws the symbol in black into rect; the image is a template, so drawing
// tints it.
void NSImageSymbolDrawGlyph(NSString *name, NSRect rect) {
    GlyphDrawer draw = drawerForName(name);
    if (draw != NULL) {
        CGFloat line = MAX(1.0, floor(NSWidth(rect) / 12.0));
        NSRect box = NSInsetRect(rect, line * 1.5, line * 1.5);
        [[NSColor blackColor] set];
        draw(box, line);
        return;
    }
    const char *svgName = svgNameForSymbol(name);
    if (svgName != NULL) {
        NSBitmapImageRep *rep = renderedRepForSymbol(svgName, rect.size);
        if (rep != nil) {
            [rep drawInRect: rect];
            return;
        }
    }
    CGFloat line = MAX(1.0, floor(NSWidth(rect) / 12.0));
    NSRect box = NSInsetRect(rect, line * 1.5, line * 1.5);
    [[NSColor blackColor] set];
    drawPlaceholder(box, line);
}
