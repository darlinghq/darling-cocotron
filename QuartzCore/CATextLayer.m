/*
 This file is part of Darling.

 Copyright (C) 2019 Lubos Dolezel

 Darling is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Darling is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with Darling.  If not, see <http://www.gnu.org/licenses/>.
*/

#import <QuartzCore/CATextLayer.h>
#import <CoreText/CTFont.h>

NSString *const kCAAlignmentNatural = @"natural";
NSString *const kCAAlignmentLeft = @"left";
NSString *const kCAAlignmentRight = @"right";
NSString *const kCAAlignmentCenter = @"center";
NSString *const kCAAlignmentJustified = @"justified";

NSString *const kCATruncationNone = @"none";
NSString *const kCATruncationStart = @"start";
NSString *const kCATruncationEnd = @"end";
NSString *const kCATruncationMiddle = @"middle";

static void replaceColor(CGColorRef *slot, CGColorRef value) {
    if (*slot == value)
        return;
    if (value)
        CGColorRetain(value);
    if (*slot)
        CGColorRelease(*slot);
    *slot = value;
}

// Name accessors of the font objects createGraphicsFont accepts (KTFont's
// -copyName, NSFont's -fontName), declared here to avoid importing their
// headers.
@interface NSObject (CATextLayerFontNames)
- (CFStringRef) copyName;
- (NSString *) fontName;
@end

// A graphics font for the layer's font property: a CGFont, a font name, or a
// font object with a name (NSFont, CTFont). Falls back to Helvetica and other
// common families when the name can't be resolved.
static CGFontRef createGraphicsFont(CFTypeRef font) {
    NSString *name = nil;
    id object = (id) font;

    // CGFontRef and CTFontRef are the O2Font and KTFont classes here. Neither
    // answers -fontName, and CoreText's CTFontCopyGraphicsFont and
    // CTFontCopyPostScriptName are stubs.
    if ([object isKindOfClass: NSClassFromString(@"O2Font")])
        return CGFontRetain((CGFontRef) font);

    if ([object isKindOfClass: [NSString class]])
        name = object;
    else if ([object isKindOfClass: NSClassFromString(@"KTFont")] &&
             [object respondsToSelector: @selector(copyName)])
        name = [(NSString *) [object copyName] autorelease];
    else if ([object respondsToSelector: @selector(fontName)])
        name = [object fontName];

    NSMutableArray *candidates = [NSMutableArray array];
    if (name != nil)
        [candidates addObject: name];
    [candidates addObjectsFromArray: @[ @"Helvetica", @"Arial", @"DejaVu Sans" ]];

    for (NSString *candidate in candidates) {
        CGFontRef result = CGFontCreateWithFontName((CFStringRef) candidate);
        if (result != NULL)
            return result;
    }
    return NULL;
}

// Glyphs and advances for a line of text; the caller frees both arrays.
static CGFloat layoutLine(CTFontRef font, NSString *line, CGGlyph **outGlyphs,
                          CGSize **outAdvances)
{
    NSUInteger length = [line length];
    UniChar *characters = malloc(MAX(length, 1) * sizeof(UniChar));
    CGGlyph *glyphs = malloc(MAX(length, 1) * sizeof(CGGlyph));
    CGSize *advances = malloc(MAX(length, 1) * sizeof(CGSize));
    CGFloat width = 0;

    if (length > 0) {
        [line getCharacters: characters range: NSMakeRange(0, length)];
        CTFontGetGlyphsForCharacters(font, characters, glyphs, length);
        CTFontGetAdvancesForGlyphs(font, 0, glyphs, advances, length);
        for (NSUInteger i = 0; i < length; i++)
            width += advances[i].width;
    }
    free(characters);

    if (outGlyphs)
        *outGlyphs = glyphs;
    else
        free(glyphs);
    if (outAdvances)
        *outAdvances = advances;
    else
        free(advances);
    return width;
}

@implementation CATextLayer

- init {
    self = [super init];
    if (self != nil) {
        _fontSize = 36;
        _foregroundColor = CGColorCreateGenericRGB(1, 1, 1, 1);
        _alignmentMode = [kCAAlignmentNatural copy];
        _truncationMode = [kCATruncationNone copy];
        _needsDisplay = YES;
    }
    return self;
}

- (void) dealloc {
    [_string release];
    if (_font)
        CFRelease(_font);
    if (_foregroundColor)
        CGColorRelease(_foregroundColor);
    [_alignmentMode release];
    [_truncationMode release];
    [super dealloc];
}

- (id) string {
    return _string;
}

- (void) setString: (id) string {
    string = [string copy];
    [_string release];
    _string = string;
    [self setNeedsDisplay];
}

- (CFTypeRef) font {
    return _font;
}

- (void) setFont: (CFTypeRef) font {
    if (font)
        CFRetain(font);
    if (_font)
        CFRelease(_font);
    _font = font;
    [self setNeedsDisplay];
}

- (CGFloat) fontSize {
    return _fontSize;
}

- (void) setFontSize: (CGFloat) size {
    _fontSize = size;
    [self setNeedsDisplay];
}

- (CGColorRef) foregroundColor {
    return _foregroundColor;
}

- (void) setForegroundColor: (CGColorRef) color {
    replaceColor(&_foregroundColor, color);
    [self setNeedsDisplay];
}

- (BOOL) isWrapped {
    return _wrapped;
}

- (void) setWrapped: (BOOL) wrapped {
    _wrapped = wrapped;
    [self setNeedsDisplay];
}

- (NSString *) alignmentMode {
    return _alignmentMode;
}

- (void) setAlignmentMode: (NSString *) mode {
    mode = [mode copy];
    [_alignmentMode release];
    _alignmentMode = mode;
    [self setNeedsDisplay];
}

- (NSString *) truncationMode {
    return _truncationMode;
}

- (void) setTruncationMode: (NSString *) mode {
    mode = [mode copy];
    [_truncationMode release];
    _truncationMode = mode;
    [self setNeedsDisplay];
}

- (BOOL) allowsFontSubpixelQuantization {
    return _allowsFontSubpixelQuantization;
}

- (void) setAllowsFontSubpixelQuantization: (BOOL) value {
    _allowsFontSubpixelQuantization = value;
}

// Splits the text at line breaks and, when wrapped, at spaces to fit the width.
- (NSArray *) _linesForText: (NSString *) text
                       font: (CTFontRef) font
                      width: (CGFloat) width
{
    // Line enumeration treats CRLF as one break; splitting at every newline
    // character would add an empty line for each CRLF.
    NSMutableArray *paragraphs = [NSMutableArray array];
    [text enumerateLinesUsingBlock: ^(NSString *line, BOOL *stop) {
        [paragraphs addObject: line];
    }];
    if (!_wrapped || width <= 0)
        return paragraphs;

    NSMutableArray *lines = [NSMutableArray array];
    for (NSString *paragraph in paragraphs) {
        NSMutableString *current = [NSMutableString string];
        for (NSString *word in [paragraph componentsSeparatedByString: @" "]) {
            NSString *candidate =
                    [current length] ? [current stringByAppendingFormat: @" %@", word]
                                     : word;
            if ([current length] && layoutLine(font, candidate, NULL, NULL) > width) {
                [lines addObject: [[current copy] autorelease]];
                [current setString: word];
            } else {
                [current setString: candidate];
            }
        }
        [lines addObject: [[current copy] autorelease]];
    }
    return lines;
}

// Lines are laid out from the top of the bounds down, aligned per alignmentMode.
- (void) drawInContext: (CGContextRef) context {
    [super drawInContext: context];

    NSString *text = nil;
    if ([_string isKindOfClass: [NSAttributedString class]])
        text = [_string string];
    else if ([_string isKindOfClass: [NSString class]])
        text = _string;
    if ([text length] == 0 || _fontSize <= 0 || _foregroundColor == NULL)
        return;

    CGFontRef graphicsFont = createGraphicsFont(_font);
    if (graphicsFont == NULL)
        return;
    CTFontRef font =
            CTFontCreateWithGraphicsFont(graphicsFont, _fontSize, NULL, NULL);
    if (font == NULL) {
        CGFontRelease(graphicsFont);
        return;
    }

    CGRect bounds = [self bounds];
    CGFloat ascent = CTFontGetAscent(font);
    CGFloat descent = fabs(CTFontGetDescent(font));
    CGFloat lineHeight = ceil(ascent + descent + CTFontGetLeading(font));

    CGContextSaveGState(context);
    CGContextSetFillColorWithColor(context, _foregroundColor);
    CGContextSetFont(context, graphicsFont);
    CGContextSetFontSize(context, _fontSize);
    CGContextSetTextMatrix(context, CGAffineTransformIdentity);

    CGFloat baseline = CGRectGetMaxY(bounds) - ascent;
    for (NSString *line in [self _linesForText: text
                                          font: font
                                         width: bounds.size.width]) {
        if (baseline + ascent < CGRectGetMinY(bounds))
            break;

        CGGlyph *glyphs;
        CGSize *advances;
        CGFloat width = layoutLine(font, line, &glyphs, &advances);

        CGFloat x = CGRectGetMinX(bounds);
        if ([_alignmentMode isEqualToString: kCAAlignmentRight])
            x = CGRectGetMaxX(bounds) - width;
        else if ([_alignmentMode isEqualToString: kCAAlignmentCenter])
            x = CGRectGetMinX(bounds) + (bounds.size.width - width) / 2;

        if ([line length] > 0) {
            CGContextSetTextPosition(context, x, baseline);
            CGContextShowGlyphsWithAdvances(context, glyphs, advances,
                                            [line length]);
        }
        free(glyphs);
        free(advances);
        baseline -= lineHeight;
    }

    CGContextRestoreGState(context);
    CFRelease(font);
    CGFontRelease(graphicsFont);
}

@end
