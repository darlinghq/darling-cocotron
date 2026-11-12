/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * Decoding of NSTextStorage, NSParagraphStyle, NSTextTab, NSBezierPath and
 * NSCachedImageRep from NSArchiver (typedstream) data. The first argument is
 * the directory with the *.typedstream fixtures written by NSArchiver on
 * macOS (textstorage, paragraphstyle, texttab, bezierpath). No window server
 * needed.
 */
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(BOOL ok, const char *what)
{
    if (!ok) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

static id unarchive(NSString *dir, NSString *name)
{
    NSData *data = [NSData dataWithContentsOfFile:
            [dir stringByAppendingPathComponent: [name stringByAppendingString: @".typedstream"]]];
    if (data == nil) {
        fprintf(stderr, "FAIL: cannot read fixture %s\n", [name UTF8String]);
        failures++;
        return nil;
    }
    @try {
        return [NSUnarchiver unarchiveObjectWithData: data];
    } @catch (NSException *e) {
        fprintf(stderr, "FAIL: decoding %s raised %s: %s\n", [name UTF8String],
                [[e name] UTF8String], [[e reason] UTF8String]);
        failures++;
        return nil;
    }
}

static void test_quirk_typedstream_text_tab(NSString *dir)
{
    NSTextTab *tab = unarchive(dir, @"texttab");
    expect([tab isKindOfClass: [NSTextTab class]], "texttab decodes to an NSTextTab");
    expect([tab tabStopType] == NSRightTabStopType, "tab type is right");
    expect([tab location] == 144, "tab location is 144");
}

static void test_quirk_typedstream_paragraph_style(NSString *dir)
{
    NSParagraphStyle *style = unarchive(dir, @"paragraphstyle");
    expect([style isKindOfClass: [NSParagraphStyle class]], "paragraphstyle decodes to an NSParagraphStyle");
    expect([style alignment] == NSCenterTextAlignment, "alignment is centred");
    expect([style lineSpacing] == 2, "line spacing is 2");
    expect([style paragraphSpacing] == 6, "paragraph spacing is 6");
    expect([style headIndent] == 5, "head indent is 5");
    expect([style tailIndent] == -5, "tail indent is -5");
    expect([style firstLineHeadIndent] == 10, "first line head indent is 10");
    expect([[style tabStops] count] == 2, "two tab stops");
    expect([[[style tabStops] objectAtIndex: 0] location] == 36, "first tab stop at 36");
}

// Bytes written by NSArchiver on macOS 26.7.3 for NSMutableParagraphStyle values
// (MAC-EVIDENCE.md MC26.12, mac-fixtures/typedstream/mac26-paragraphstyle-bezier-hex.txt).
static NSParagraphStyle *decodeBytes(const unsigned char *bytes, size_t length)
{
    @try {
        return [NSUnarchiver unarchiveObjectWithData: [NSData dataWithBytes: bytes length: length]];
    } @catch (NSException *e) {
        fprintf(stderr, "FAIL: decoding paragraph style raised %s: %s\n", [[e name] UTF8String], [[e reason] UTF8String]);
        failures++;
        return nil;
    }
}

static const unsigned char firstLine[] = {0x04, 0x0b, 0x73, 0x74, 0x72, 0x65, 0x61, 0x6d, 0x74, 0x79, 0x70, 0x65, 0x64, 0x81, 0xe8, 0x03, 0x84, 0x01, 0x40, 0x84, 0x84, 0x84, 0x17, 0x4e, 0x53, 0x4d, 0x75, 0x74, 0x61, 0x62, 0x6c, 0x65, 0x50, 0x61, 0x72, 0x61, 0x67, 0x72, 0x61, 0x70, 0x68, 0x53, 0x74, 0x79, 0x6c, 0x65, 0x00, 0x84, 0x84, 0x10, 0x4e, 0x53, 0x50, 0x61, 0x72, 0x61, 0x67, 0x72, 0x61, 0x70, 0x68, 0x53, 0x74, 0x79, 0x6c, 0x65, 0x00, 0x84, 0x84, 0x08, 0x4e, 0x53, 0x4f, 0x62, 0x6a, 0x65, 0x63, 0x74, 0x00, 0x85, 0x84, 0x04, 0x43, 0x43, 0x40, 0x53, 0x04, 0x00, 0x85, 0x10, 0x84, 0x04, 0x5b, 0x31, 0x66, 0x5d, 0x0a, 0x86};
static const unsigned char indents[] = {0x04, 0x0b, 0x73, 0x74, 0x72, 0x65, 0x61, 0x6d, 0x74, 0x79, 0x70, 0x65, 0x64, 0x81, 0xe8, 0x03, 0x84, 0x01, 0x40, 0x84, 0x84, 0x84, 0x17, 0x4e, 0x53, 0x4d, 0x75, 0x74, 0x61, 0x62, 0x6c, 0x65, 0x50, 0x61, 0x72, 0x61, 0x67, 0x72, 0x61, 0x70, 0x68, 0x53, 0x74, 0x79, 0x6c, 0x65, 0x00, 0x84, 0x84, 0x10, 0x4e, 0x53, 0x50, 0x61, 0x72, 0x61, 0x67, 0x72, 0x61, 0x70, 0x68, 0x53, 0x74, 0x79, 0x6c, 0x65, 0x00, 0x84, 0x84, 0x08, 0x4e, 0x53, 0x4f, 0x62, 0x6a, 0x65, 0x63, 0x74, 0x00, 0x85, 0x84, 0x04, 0x43, 0x43, 0x40, 0x53, 0x04, 0x00, 0x85, 0x0c, 0x84, 0x04, 0x5b, 0x32, 0x66, 0x5d, 0x14, 0x1e, 0x86};
static const unsigned char truncTail[] = {0x04, 0x0b, 0x73, 0x74, 0x72, 0x65, 0x61, 0x6d, 0x74, 0x79, 0x70, 0x65, 0x64, 0x81, 0xe8, 0x03, 0x84, 0x01, 0x40, 0x84, 0x84, 0x84, 0x17, 0x4e, 0x53, 0x4d, 0x75, 0x74, 0x61, 0x62, 0x6c, 0x65, 0x50, 0x61, 0x72, 0x61, 0x67, 0x72, 0x61, 0x70, 0x68, 0x53, 0x74, 0x79, 0x6c, 0x65, 0x00, 0x84, 0x84, 0x10, 0x4e, 0x53, 0x50, 0x61, 0x72, 0x61, 0x67, 0x72, 0x61, 0x70, 0x68, 0x53, 0x74, 0x79, 0x6c, 0x65, 0x00, 0x84, 0x84, 0x08, 0x4e, 0x53, 0x4f, 0x62, 0x6a, 0x65, 0x63, 0x74, 0x00, 0x85, 0x84, 0x04, 0x43, 0x43, 0x40, 0x53, 0x04, 0x04, 0x85, 0x00, 0x86};
static const unsigned char hyph[] = {0x04, 0x0b, 0x73, 0x74, 0x72, 0x65, 0x61, 0x6d, 0x74, 0x79, 0x70, 0x65, 0x64, 0x81, 0xe8, 0x03, 0x84, 0x01, 0x40, 0x84, 0x84, 0x84, 0x17, 0x4e, 0x53, 0x4d, 0x75, 0x74, 0x61, 0x62, 0x6c, 0x65, 0x50, 0x61, 0x72, 0x61, 0x67, 0x72, 0x61, 0x70, 0x68, 0x53, 0x74, 0x79, 0x6c, 0x65, 0x00, 0x84, 0x84, 0x10, 0x4e, 0x53, 0x50, 0x61, 0x72, 0x61, 0x67, 0x72, 0x61, 0x70, 0x68, 0x53, 0x74, 0x79, 0x6c, 0x65, 0x00, 0x84, 0x84, 0x08, 0x4e, 0x53, 0x4f, 0x62, 0x6a, 0x65, 0x63, 0x74, 0x00, 0x85, 0x84, 0x04, 0x43, 0x43, 0x40, 0x53, 0x04, 0x00, 0x85, 0x81, 0x00, 0x04, 0x84, 0x04, 0x5b, 0x31, 0x66, 0x5d, 0x83, 0x00, 0x00, 0x00, 0x3f, 0x86};
static const unsigned char before[] = {0x04, 0x0b, 0x73, 0x74, 0x72, 0x65, 0x61, 0x6d, 0x74, 0x79, 0x70, 0x65, 0x64, 0x81, 0xe8, 0x03, 0x84, 0x01, 0x40, 0x84, 0x84, 0x84, 0x17, 0x4e, 0x53, 0x4d, 0x75, 0x74, 0x61, 0x62, 0x6c, 0x65, 0x50, 0x61, 0x72, 0x61, 0x67, 0x72, 0x61, 0x70, 0x68, 0x53, 0x74, 0x79, 0x6c, 0x65, 0x00, 0x84, 0x84, 0x10, 0x4e, 0x53, 0x50, 0x61, 0x72, 0x61, 0x67, 0x72, 0x61, 0x70, 0x68, 0x53, 0x74, 0x79, 0x6c, 0x65, 0x00, 0x84, 0x84, 0x08, 0x4e, 0x53, 0x4f, 0x62, 0x6a, 0x65, 0x63, 0x74, 0x00, 0x85, 0x84, 0x04, 0x43, 0x43, 0x40, 0x53, 0x04, 0x00, 0x85, 0x81, 0x00, 0x01, 0x84, 0x04, 0x5b, 0x31, 0x66, 0x5d, 0x08, 0x86};
static const unsigned char mult[] = {0x04, 0x0b, 0x73, 0x74, 0x72, 0x65, 0x61, 0x6d, 0x74, 0x79, 0x70, 0x65, 0x64, 0x81, 0xe8, 0x03, 0x84, 0x01, 0x40, 0x84, 0x84, 0x84, 0x17, 0x4e, 0x53, 0x4d, 0x75, 0x74, 0x61, 0x62, 0x6c, 0x65, 0x50, 0x61, 0x72, 0x61, 0x67, 0x72, 0x61, 0x70, 0x68, 0x53, 0x74, 0x79, 0x6c, 0x65, 0x00, 0x84, 0x84, 0x10, 0x4e, 0x53, 0x50, 0x61, 0x72, 0x61, 0x67, 0x72, 0x61, 0x70, 0x68, 0x53, 0x74, 0x79, 0x6c, 0x65, 0x00, 0x84, 0x84, 0x08, 0x4e, 0x53, 0x4f, 0x62, 0x6a, 0x65, 0x63, 0x74, 0x00, 0x85, 0x84, 0x04, 0x43, 0x43, 0x40, 0x53, 0x04, 0x00, 0x85, 0x81, 0x80, 0x00, 0x84, 0x04, 0x5b, 0x31, 0x66, 0x5d, 0x83, 0x00, 0x00, 0xc0, 0x3f, 0x86};

// QUIRK test (macOS 26.7.3): the paragraph style flag map, including 0x10
// (first line head indent) and the 2-byte flags above 0xff.
static void test_quirk_typedstream_paragraph_style_flags(void)
{
    NSParagraphStyle *style = decodeBytes(firstLine, sizeof(firstLine));
    expect(style != nil && [style firstLineHeadIndent] == 10 && [style headIndent] == 0,
           "flag 0x10 is the first line head indent");
    style = decodeBytes(indents, sizeof(indents));
    expect(style != nil && [style headIndent] == 20 && [style tailIndent] == 30 &&
                   [style firstLineHeadIndent] == 0,
           "flags 0x0c are the head and tail indents");
    style = decodeBytes(truncTail, sizeof(truncTail));
    expect(style != nil && [style lineBreakMode] == NSLineBreakByTruncatingTail,
           "the second byte is the line break mode");
    style = decodeBytes(hyph, sizeof(hyph));
    expect(style != nil && [style hyphenationFactor] == 0.5f, "flag 0x400 is the hyphenation factor");
    style = decodeBytes(before, sizeof(before));
    expect(style != nil && [style paragraphSpacingBefore] == 8, "flag 0x100 is the paragraph spacing before");
    style = decodeBytes(mult, sizeof(mult));
    expect(style != nil && [style lineHeightMultiple] == 1.5f, "flag 0x80 is the line height multiple");
}

static void test_quirk_typedstream_bezier_path(NSString *dir)
{
    NSBezierPath *path = unarchive(dir, @"bezierpath");
    expect([path isKindOfClass: [NSBezierPath class]], "bezierpath decodes to an NSBezierPath");
    expect([path elementCount] == 6, "six path elements");
    NSPoint points[3];
    expect([path elementAtIndex: 2 associatedPoints: points] == NSCurveToBezierPathElement,
           "third element is a curve");
    expect(points[0].x == 150 && points[0].y == 10 && points[1].x == 150 && points[1].y == 100 &&
                   points[2].x == 100 && points[2].y == 100,
           "curve control and end points");
    expect([path elementAtIndex: 3] == NSClosePathBezierPathElement, "fourth element closes");
    expect([path lineWidth] == 2.5, "line width");
    expect([path windingRule] == NSEvenOddWindingRule, "even-odd winding");
    expect([path lineCapStyle] == NSRoundLineCapStyle, "round cap");
    expect([path lineJoinStyle] == NSBevelLineJoinStyle, "bevel join");
    expect([path miterLimit] == 4, "miter limit");
    expect([path flatness] == 0.5, "flatness");
    CGFloat dashes[2] = {0, 0};
    CGFloat phase = 0;
    int dashCount = 0;
    [path getLineDash: dashes count: &dashCount phase: &phase];
    expect(dashCount == 2 && dashes[0] == 4 && dashes[1] == 2 && phase == 1, "dash pattern {4, 2} phase 1");
}

static void test_quirk_typedstream_text_storage(NSString *dir)
{
    NSTextStorage *storage = unarchive(dir, @"textstorage");
    expect([storage isKindOfClass: [NSTextStorage class]], "textstorage decodes to an NSTextStorage");
    expect([[storage string] isEqualToString: @"Plain \tBold red\nSecond paragraph é"],
           "the string is restored");
    NSRange effective;
    expect([[storage attribute: NSUnderlineStyleAttributeName atIndex: 0 effectiveRange: &effective]
                    intValue] == 1 &&
                   NSEqualRanges(effective, NSMakeRange(0, 5)),
           "the underline run covers 0..5");
    expect([storage attribute: NSUnderlineStyleAttributeName atIndex: 6 effectiveRange: NULL] == nil,
           "no underline after the run");
    // -attribute:atIndex:effectiveRange: need not give the longest range; ask for it.
    NSParagraphStyle *style = [storage attribute: NSParagraphStyleAttributeName
                                         atIndex: 0
                           longestEffectiveRange: &effective
                                         inRange: NSMakeRange(0, [storage length])];
    expect(style != nil && [style alignment] == NSCenterTextAlignment &&
                   NSEqualRanges(effective, NSMakeRange(0, 16)),
           "the paragraph style run covers 0..16");
    expect([storage attribute: NSParagraphStyleAttributeName atIndex: 20 effectiveRange: NULL] == nil,
           "the second paragraph has no style");
    expect([storage attribute: NSFontAttributeName atIndex: 8 effectiveRange: NULL] != nil,
           "a font is present in the bold run");
    expect([storage attribute: NSForegroundColorAttributeName atIndex: 13 effectiveRange: NULL] != nil,
           "a foreground colour is present in the red run");
}

// Writes the cached image rep layout by hand through a root object and reads it
// with the real class.
@interface CachedRepBox : NSObject <NSCoding> {
@public
    NSData *tiff;
    id rep;
}
@end

@implementation CachedRepBox
- (void) encodeWithCoder: (NSCoder *) coder
{
    char flag = 0;
    int zero = 0;
    [coder encodeDataObject: tiff];
    [coder encodeValueOfObjCType: "c" at: &flag];
    [coder encodeValuesOfObjCTypes: "iii", &zero, &zero, &zero];
}
- (id) initWithCoder: (NSCoder *) coder
{
    rep = [[NSCachedImageRep alloc] initWithCoder: coder];
    return self;
}
@end

static void test_quirk_typedstream_cached_image_rep(void)
{
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc]
            initWithBitmapDataPlanes: NULL pixelsWide: 4 pixelsHigh: 2 bitsPerSample: 8
                     samplesPerPixel: 4 hasAlpha: YES isPlanar: NO
                      colorSpaceName: NSDeviceRGBColorSpace bytesPerRow: 0 bitsPerPixel: 0];
    CachedRepBox *box = [[CachedRepBox alloc] init];
    box->tiff = [bitmap TIFFRepresentation];
    NSData *archive = [NSArchiver archivedDataWithRootObject: box];
    CachedRepBox *back = [NSUnarchiver unarchiveObjectWithData: archive];
    expect([back->rep isKindOfClass: [NSBitmapImageRep class]], "the cached rep decodes to a bitmap rep");
    expect([back->rep pixelsWide] == 4 && [back->rep pixelsHigh] == 2, "the bitmap keeps its size");
}

int main(int argc, char **argv)
{
    if (argc < 2) {
        fprintf(stderr, "usage: %s <fixture directory>\n", argv[0]);
        return 2;
    }
    @autoreleasepool {
        NSString *dir = [NSString stringWithUTF8String: argv[1]];
        test_quirk_typedstream_text_tab(dir);
        test_quirk_typedstream_paragraph_style(dir);
        test_quirk_typedstream_paragraph_style_flags();
        test_quirk_typedstream_bezier_path(dir);
        test_quirk_typedstream_text_storage(dir);
        test_quirk_typedstream_cached_image_rep();
    }
    if (failures)
        return 1;
    puts("typedstream text: PASS");
    return 0;
}
