/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * NSTextAttachmentCell sizes itself from the attachment's image, and the
 * layout manager advances the pen by the attachment's width and lets the line
 * grow to its height. No window server needed.
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

static NSData *pngData(NSInteger width, NSInteger height)
{
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
            initWithBitmapDataPlanes: NULL pixelsWide: width pixelsHigh: height bitsPerSample: 8
                     samplesPerPixel: 4 hasAlpha: YES isPlanar: NO
                      colorSpaceName: NSDeviceRGBColorSpace bytesPerRow: 0 bitsPerPixel: 0];
    memset([rep bitmapData], 0x80, [rep bytesPerRow] * height);
    return [rep representationUsingType: NSPNGFileType properties: @{}];
}

int main(void)
{
    @autoreleasepool {
        NSFileWrapper *wrapper = [[NSFileWrapper alloc] initRegularFileWithContents: pngData(40, 60)];
        [wrapper setPreferredFilename: @"picture.png"];
        NSTextAttachment *attachment = [[NSTextAttachment alloc] initWithFileWrapper: wrapper];
        NSTextAttachmentCell *cell = (NSTextAttachmentCell *) [attachment attachmentCell];
        expect(cell != nil, "an attachment made from a file wrapper has a cell");
        expect([cell attachment] == attachment, "the cell points back to its attachment");
        NSSize size = [cell cellSize];
        expect(size.width == 40 && size.height == 60, "the cell is the size of the image");

        NSRect frame = [cell cellFrameForTextContainer: nil
                                  proposedLineFragment: NSMakeRect(0, 0, 20, 100)
                                         glyphPosition: NSZeroPoint
                                        characterIndex: 0];
        expect(frame.size.width <= 20 && frame.size.height == 60,
               "a wide attachment is limited to the line fragment width");

        // Draw into a bitmap: the cell must not crash and must paint inside its frame.
        NSBitmapImageRep *target = [[NSBitmapImageRep alloc]
                initWithBitmapDataPlanes: NULL pixelsWide: 80 pixelsHigh: 80 bitsPerSample: 8
                         samplesPerPixel: 4 hasAlpha: YES isPlanar: NO
                          colorSpaceName: NSDeviceRGBColorSpace bytesPerRow: 0 bitsPerPixel: 0];
        memset([target bitmapData], 0, [target bytesPerRow] * 80);
        [NSGraphicsContext saveGraphicsState];
        [NSGraphicsContext setCurrentContext: [NSGraphicsContext graphicsContextWithBitmapImageRep: target]];
        [cell drawWithFrame: NSMakeRect(0, 0, 40, 60) inView: nil];
        [NSGraphicsContext restoreGraphicsState];
        const unsigned char *pixels = [target bitmapData];
        // The bitmap's first row is the top, so the frame at the origin (60 high, bottom left) covers rows 20 to 79.
        NSUInteger inside = 50 * [target bytesPerRow] + 10 * 4;
        expect(pixels[inside + 3] != 0, "a pixel inside the frame was painted");
        expect(pixels[3] == 0, "a pixel outside the frame was not painted");

        // Layout: "a", the attachment, "b".
        NSMutableAttributedString *text = [[NSMutableAttributedString alloc] initWithString: @"a"];
        [text appendAttributedString: [NSAttributedString attributedStringWithAttachment: attachment]];
        [text appendAttributedString: [[NSAttributedString alloc] initWithString: @"b"]];
        NSTextStorage *storage = [[NSTextStorage alloc] initWithAttributedString: text];
        NSLayoutManager *manager = [[NSLayoutManager alloc] init];
        NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize: NSMakeSize(400, 1000)];
        [manager addTextContainer: container];
        [storage addLayoutManager: manager];
        [manager ensureLayoutForTextContainer: container];

        CGFloat attachmentX = [manager locationForGlyphAtIndex: 1].x;
        CGFloat nextX = [manager locationForGlyphAtIndex: 2].x;
        expect(fabs((nextX - attachmentX) - 40) < 0.5, "the pen advances by the attachment's width");
        NSRect line = [manager lineFragmentRectForGlyphAtIndex: 1 effectiveRange: NULL];
        expect(line.size.height >= 60, "the line is at least as tall as the attachment");
    }
    if (failures)
        return 1;
    puts("text attachment layout: PASS");
    return 0;
}
