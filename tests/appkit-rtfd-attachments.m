/*
 * Writing and reading RTFD documents with attachments. The first argument is
 * the directory with the RTFD fixtures written by macOS (rtfd/Attachment*.rtfd
 * of the fixture tree), used for reading. No window server needed.
 */
#import <AppKit/AppKit.h>
#include <stdlib.h>

static int failures;

static void expect(BOOL condition, NSString *message) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", [message UTF8String]);
        failures++;
    }
}

static BOOL loadRTFD(NSString *path, NSString **string, NSUInteger *attachments) {
    NSTextView *reader = [[[NSTextView alloc] initWithFrame: NSMakeRect(0, 0, 300, 100)] autorelease];
    if (![reader readRTFDFromFile: path])
        return NO;
    NSTextStorage *storage = [reader textStorage];
    *string = [storage string];
    *attachments = 0;
    for (NSUInteger i = 0; i < [storage length]; i++)
        if ([storage attribute: NSAttachmentAttributeName atIndex: i effectiveRange: NULL] != nil)
            (*attachments)++;
    return YES;
}

// Writing: attachment files go next to TXT.rtf, referenced with their size in
// twips and followed by the placeholder byte.
static void test_quirk_rtfd_attachment_layout(void) {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent: @"appkit-rtfd-attachments.rtfd"];
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
    NSFileWrapper *note = [[[NSFileWrapper alloc] initRegularFileWithContents: [@"note" dataUsingEncoding: NSUTF8StringEncoding]] autorelease];
    [note setPreferredFilename: @"note.txt"];
    NSTextAttachment *noteAttachment = [[[NSTextAttachment alloc] initWithFileWrapper: note] autorelease];

    NSMutableAttributedString *text = [[[NSMutableAttributedString alloc] initWithString: @"before "] autorelease];
    [text appendAttributedString: [NSAttributedString attributedStringWithAttachment: attachment]];
    [text appendAttributedString: [[[NSAttributedString alloc] initWithString: @" and "] autorelease]];
    [text appendAttributedString: [NSAttributedString attributedStringWithAttachment: noteAttachment]];
    [text appendAttributedString: [[[NSAttributedString alloc] initWithString: @" after"] autorelease]];

    NSTextView *view = [[[NSTextView alloc] initWithFrame: NSMakeRect(0, 0, 300, 100)] autorelease];
    [[view textStorage] setAttributedString: text];
    expect([view writeRTFDToFile: path atomically: YES], @"writeRTFDToFile:atomically:");

    NSData *stored = [NSData dataWithContentsOfFile: [path stringByAppendingPathComponent: @"picture.png"]];
    expect([stored isEqualToData: payload], @"attachment file stored in the .rtfd");
    NSData *rtf = [NSData dataWithContentsOfFile: [path stringByAppendingPathComponent: @"TXT.rtf"]];
    NSString *rtfString = [[[NSString alloc] initWithData: rtf encoding: NSISOLatin1StringEncoding] autorelease];
    expect([rtfString rangeOfString: @"{{\\NeXTGraphic picture.png \\width40 \\height60"].location != NSNotFound,
           @"TXT.rtf references the image with its size in twips");
    expect([rtfString rangeOfString: @"{{\\NeXTGraphic note.txt \\width640 \\height640"].location != NSNotFound,
           @"a non-image file is 32 points square");
    const unsigned char placeholder[] = {'}', 0xAC, '}'};
    expect([rtf rangeOfData: [NSData dataWithBytes: placeholder length: 3]
                    options: 0 range: NSMakeRange(0, [rtf length])].location != NSNotFound,
           @"the group is followed by a raw 0xAC byte");

    NSString *string = nil;
    NSUInteger count = 0;
    expect(loadRTFD(path, &string, &count), @"readRTFDFromFile:");
    expect([string isEqualToString: [text string]], @"text round-trips with one attachment character each");
    expect(count == 2, @"both attachments round-trip");
}

// Reading: whatever follows an attachment group inside its enclosing group is
// ignored, as with the placeholder byte the platform writes.
static void test_quirk_rtfd_attachment_placeholder_ignored(NSString *dir) {
    NSArray *names = @[@"Attachment", @"Attachment-no-placeholder", @"Attachment-letter-instead",
                       @"Attachment-doubled", @"Attachment-hex-escape"];
    for (NSString *name in names) {
        NSString *path = [dir stringByAppendingPathComponent: [name stringByAppendingString: @".rtfd"]];
        NSString *string = nil;
        NSUInteger count = 0;
        if (!loadRTFD(path, &string, &count)) {
            expect(NO, [@"cannot read " stringByAppendingString: name]);
            continue;
        }
        expect([string isEqualToString: @"Before \uFFFC middle \uFFFC after\n"],
               [@"text of " stringByAppendingString: name]);
        expect(count == 2, [@"two attachments in " stringByAppendingString: name]);
    }
}

static void test_unreadable_file_keeps_text(void) {
    NSTextView *view = [[[NSTextView alloc] initWithFrame: NSMakeRect(0, 0, 300, 100)] autorelease];
    [view setString: @"keep me"];
    expect(![view readRTFDFromFile: @"/nonexistent/none.rtfd"], @"readRTFDFromFile: fails for a missing file");
    expect([[view string] isEqualToString: @"keep me"], @"the text is left alone");
}

static void testDocumentData(void) {
    NSAttributedString *plain = [[[NSAttributedString alloc] initWithString: @"plain text"] autorelease];
    NSData *data = [plain dataFromRange: NSMakeRange(0, [plain length])
                     documentAttributes: @{NSDocumentTypeDocumentAttribute: NSPlainTextDocumentType}
                                  error: NULL];
    expect([[[[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding] autorelease]
                   isEqualToString: @"plain text"],
           @"plain text document data");
    NSAttributedString *back = [[[NSAttributedString alloc]
            initWithData: data
                 options: @{NSDocumentTypeDocumentAttribute: NSPlainTextDocumentType}
      documentAttributes: NULL
                   error: NULL] autorelease];
    expect([[back string] isEqualToString: @"plain text"], @"plain text reads back");
    NSError *error = nil;
    expect([plain dataFromRange: NSMakeRange(0, 1)
              documentAttributes: @{NSDocumentTypeDocumentAttribute: @"bogus"}
                           error: &error] == nil && error != nil,
           @"an unknown document type fails with an error");
    expect(![plain containsAttachments], @"no attachments in plain text");
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s <rtfd fixture directory>\n", argv[0]);
        return 2;
    }
    @autoreleasepool {
        test_quirk_rtfd_attachment_layout();
        test_quirk_rtfd_attachment_placeholder_ignored([NSString stringWithUTF8String: argv[1]]);
        test_unreadable_file_keeps_text();
        testDocumentData();
    }
    if (failures)
        return 1;
    puts("rtfd attachments: PASS");
    return 0;
}
