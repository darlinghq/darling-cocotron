/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// RTFD data (the serialized RTFD file wrapper): -[NSAttributedString initWithRTFD:documentAttributes:],
// -initWithRTFDFileWrapper:documentAttributes:, -RTFDFromRange:documentAttributes:, and the text view's
// -RTFDFromRange: and -replaceCharactersInRange:withRTFD:. The sample is what macOS 26.7.3 returns for
// "A", an attachment of the file pic.png holding "PNGDATA", and "B"; Mac OS X 10.14.4 returns the same
// bytes apart from the order of the entries. Runs unchanged against Apple's frameworks.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(cond, what) do { if (!(cond)) { printf("FAIL: %s\n", what); failures++; } } while (0)

static NSString *const macSample = @"cnRmZAAAAAADAAAAAwAAAAcAAABUWFQucnRmAQAAAC4HAAAAcGljLnBuZ6ABAABKAAAADwAAAAEAAACYAQAAe1xydGYxXGFuc2lcYW5zaWNwZzEyNTJcY29jb2FydGYyODcwClxjb2NvYXRleHRzY2FsaW5nMFxjb2NvYXBsYXRmb3JtMHtcZm9udHRibFxmMFxmc3dpc3NcZmNoYXJzZXQwIEhlbHZldGljYTt9CntcY29sb3J0Ymw7XHJlZDI1NVxncmVlbjI1NVxibHVlMjU1O30Ke1wqXGV4cGFuZGVkY29sb3J0Ymw7O30KXHBhcmRcdHg1NjBcdHgxMTIwXHR4MTY4MFx0eDIyNDBcdHgyODAwXHR4MzM2MFx0eDM5MjBcdHg0NDgwXHR4NTA0MFx0eDU2MDBcdHg2MTYwXHR4NjcyMFxwYXJkaXJuYXR1cmFsXHBhcnRpZ2h0ZW5mYWN0b3IwCgpcZjBcZnMyNCBcY2YwIEF7e1xOZVhUR3JhcGhpYyBwaWMucG5nIFx3aWR0aDAgXGhlaWdodDAgXGFwcGxlYXR0YWNobWVudHBhZGRpbmcwIFxhcHBsZWVtYmVkdHlwZTAgXGFwcGxlYXFjCn2sfUJ9AQAAAEIAAAACAAAABwAAAFRYVC5ydGYHAAAAcGljLnBuZxAAAAAQAAAAaVn3arYBAAAAAAAAAAAAAGlZ92q2AQAAAAAAAAAAAAABAAAABwAAAFBOR0RBVEE=";

static NSAttributedString *sampleText(void) {
    NSFileWrapper *file = [[NSFileWrapper alloc] initRegularFileWithContents: [@"PNGDATA" dataUsingEncoding: NSUTF8StringEncoding]];
    [file setPreferredFilename: @"pic.png"];
    NSTextAttachment *attachment = [[NSTextAttachment alloc] initWithFileWrapper: file];
    NSMutableAttributedString *text = [[NSMutableAttributedString alloc] initWithString: @"A"];
    [text appendAttributedString: [NSAttributedString attributedStringWithAttachment: attachment]];
    [text appendAttributedString: [[NSAttributedString alloc] initWithString: @"B"]];
    return text;
}

static void checkAttachedText(NSAttributedString *text, const char *what) {
    char message[96];

    snprintf(message, sizeof message, "%s: text", what);
    CHECK(text != nil && [[text string] isEqual: @"A￼B"], message);
    if ([text length] != 3)
        return;
    NSTextAttachment *attachment = [text attribute: NSAttachmentAttributeName atIndex: 1 effectiveRange: NULL];
    NSFileWrapper *wrapper = [attachment fileWrapper];
    snprintf(message, sizeof message, "%s: attachment file", what);
    CHECK(wrapper != nil && [[wrapper regularFileContents] isEqualToData: [@"PNGDATA" dataUsingEncoding: NSUTF8StringEncoding]], message);
    snprintf(message, sizeof message, "%s: attachment name", what);
    CHECK([[wrapper preferredFilename] isEqual: @"pic.png"], message);
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSAttributedString *text = sampleText();

        // Writing: RTFD data is the serialized wrapper, which holds TXT.rtf and the attachment.
        NSData *rtfd = [text RTFDFromRange: NSMakeRange(0, [text length]) documentAttributes: @{}];
        CHECK([rtfd length] > 12 && memcmp([rtfd bytes], "rtfd", 4) == 0, "RTFD data starts with the rtfd header");
        NSFileWrapper *wrapper = [[NSFileWrapper alloc] initWithSerializedRepresentation: rtfd];
        CHECK([wrapper isDirectory] && [[wrapper fileWrappers] objectForKey: @"TXT.rtf"] != nil &&
              [[wrapper fileWrappers] objectForKey: @"pic.png"] != nil, "serialized wrapper has TXT.rtf and pic.png");
        NSData *rtf = [[[wrapper fileWrappers] objectForKey: @"TXT.rtf"] regularFileContents];
        CHECK([rtf length] > 5 && memcmp([rtf bytes], "{\\rtf", 5) == 0, "TXT.rtf is RTF");

        // Reading what we wrote, and what macOS wrote.
        NSDictionary *attributes = nil;
        checkAttachedText([[NSAttributedString alloc] initWithRTFD: rtfd documentAttributes: &attributes], "own data");
        CHECK([[attributes objectForKey: NSDocumentTypeDocumentAttribute] isEqual: NSRTFDTextDocumentType], "document type attribute");
        NSData *mac = [[NSData alloc] initWithBase64EncodedString: macSample options: 0];
        checkAttachedText([[NSAttributedString alloc] initWithRTFD: mac documentAttributes: NULL], "macOS sample");

        // The wrapper variant.
        checkAttachedText([[NSAttributedString alloc] initWithRTFDFileWrapper: wrapper documentAttributes: NULL], "wrapper");
        NSFileWrapper *direct = [text RTFDFileWrapperFromRange: NSMakeRange(0, [text length]) documentAttributes: @{}];
        checkAttachedText([[NSAttributedString alloc] initWithRTFDFileWrapper: direct documentAttributes: NULL], "direct wrapper");

        // Plain text.
        NSAttributedString *plain = [[NSAttributedString alloc] initWithString: @"Hello"];
        NSData *plainData = [plain RTFDFromRange: NSMakeRange(0, 5) documentAttributes: @{}];
        NSAttributedString *plainBack = [[NSAttributedString alloc] initWithRTFD: plainData documentAttributes: NULL];
        CHECK([[plainBack string] isEqual: @"Hello"], "plain text round trip");

        // Input that is not RTFD gives nil.
        NSData *plainRTF = [plain RTFFromRange: NSMakeRange(0, 5) documentAttributes: @{}];
        CHECK([[NSAttributedString alloc] initWithRTFD: plainRTF documentAttributes: NULL] == nil, "plain RTF is not RTFD");
        CHECK([[NSAttributedString alloc] initWithRTFD: [NSData data] documentAttributes: NULL] == nil, "empty data");
        CHECK([[NSAttributedString alloc] initWithRTFD: [NSData dataWithBytes: "junk" length: 4] documentAttributes: NULL] == nil, "junk data");
        NSFileWrapper *noText = [[NSFileWrapper alloc] initDirectoryWithFileWrappers: @{}];
        CHECK([[NSAttributedString alloc] initWithRTFDFileWrapper: noText documentAttributes: NULL] == nil, "directory without TXT.rtf");
        NSFileWrapper *file = [[NSFileWrapper alloc] initRegularFileWithContents: [@"x" dataUsingEncoding: NSUTF8StringEncoding]];
        CHECK([[NSAttributedString alloc] initWithRTFDFileWrapper: file documentAttributes: NULL] == nil, "regular file wrapper");

        // The text view reads and writes the same data.
        NSTextView *view = [[NSTextView alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)];
        [[view textStorage] setAttributedString: text];
        NSData *viewData = [view RTFDFromRange: NSMakeRange(0, [text length])];
        CHECK([viewData length] > 12 && memcmp([viewData bytes], "rtfd", 4) == 0, "text view RTFD data");
        NSTextView *other = [[NSTextView alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)];
        [other setRichText: YES];
        [other replaceCharactersInRange: NSMakeRange(0, 0) withRTFD: viewData];
        checkAttachedText([other textStorage], "text view replaceCharactersInRange:withRTFD:");
    }
    printf(failures ? "FAIL\n" : "PASS\n");
    return failures != 0;
}
