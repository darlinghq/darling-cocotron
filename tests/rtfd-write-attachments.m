#import <AppKit/AppKit.h>
#include <stdlib.h>

// -[NSText writeRTFDToFile:atomically:] (what Stickies saves notes with) must
// store attachment files in the .rtfd and reference them from TXT.rtf, so the
// reader brings them back.
static void expect(BOOL condition, NSString *message) {
    if (!condition) {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

int main(void) {
    @autoreleasepool {
        NSString *path = [NSHomeDirectory()
                stringByAppendingPathComponent: @"rtfd-write-attachments.rtfd"];
        [[NSFileManager defaultManager] removeItemAtPath: path error: NULL];

        // A 2x3-pixel PNG.
        static const unsigned char png[] = {
            0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
            0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x03, 0x08, 0x02, 0x00, 0x00, 0x00, 0x36, 0x88, 0x49,
            0xd6, 0x00, 0x00, 0x00, 0x10, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0xf8, 0xcf, 0xc0, 0x00,
            0x44, 0x0c, 0x28, 0x14, 0x00, 0x44, 0xd0, 0x05, 0xfb, 0xa4, 0xcf, 0xde, 0x80, 0x00, 0x00, 0x00,
            0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82};
        NSData *payload = [NSData dataWithBytes: png length: sizeof(png)];
        NSFileWrapper *file = [[[NSFileWrapper alloc] initRegularFileWithContents: payload] autorelease];
        [file setPreferredFilename: @"picture.png"];
        NSTextAttachment *attachment = [[[NSTextAttachment alloc] initWithFileWrapper: file] autorelease];

        NSMutableAttributedString *text = [[[NSMutableAttributedString alloc] initWithString: @"before "] autorelease];
        [text appendAttributedString: [NSAttributedString attributedStringWithAttachment: attachment]];
        [text appendAttributedString: [[[NSAttributedString alloc] initWithString: @" after"] autorelease]];

        NSTextView *view = [[[NSTextView alloc] initWithFrame: NSMakeRect(0, 0, 300, 100)] autorelease];
        [[view textStorage] setAttributedString: text];
        expect([view writeRTFDToFile: path atomically: YES], @"writeRTFDToFile:atomically:");

        NSData *stored = [NSData dataWithContentsOfFile: [path stringByAppendingPathComponent: @"picture.png"]];
        expect([stored isEqualToData: payload], @"attachment file stored in the .rtfd");
        NSString *rtf = [NSString stringWithContentsOfFile: [path stringByAppendingPathComponent: @"TXT.rtf"]
                                                  encoding: NSISOLatin1StringEncoding
                                                     error: NULL];
        expect([rtf rangeOfString: @"\\NeXTGraphic picture.png \\width40 \\height60"].location != NSNotFound,
               @"TXT.rtf references the attachment with its size in twips");

        NSTextView *reader = [[[NSTextView alloc] initWithFrame: NSMakeRect(0, 0, 300, 100)] autorelease];
        expect([reader readRTFDFromFile: path], @"readRTFDFromFile:");
        NSTextStorage *read = [reader textStorage];
        expect([[read string] isEqualToString: [text string]], @"text round-trips with one attachment character");
        NSTextAttachment *readAttachment = [read attribute: NSAttachmentAttributeName
                                                   atIndex: [@"before " length]
                                            effectiveRange: NULL];
        expect([[[readAttachment fileWrapper] regularFileContents] isEqualToData: payload],
               @"attachment contents round-trip");
        NSLog(@"PASS: rtfd-write-attachments");
    }
    return 0;
}
