// Copyright (C) 2026 Lubos Dolezel
//
// An NSPrintOperation that prints (not a PDF operation) makes the PDF file that the print settings of its
// print info name as their destination, once the print info saves the job (the job disposition
// NSPrintSaveJob and a path: what the print panel makes of its Print button). No display connection is needed.
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static int failures;
#define CHECK(cond, msg) do { if (!(cond)) { printf("FAIL: %s\n", msg); failures++; } } while (0)

@interface PrintedView : NSView
@end
@implementation PrintedView
- (void) drawRect: (NSRect) rect {
    [[NSColor blackColor] set];
    NSRectFill(NSMakeRect(10, 10, 100, 100));
}
@end

int main(void) {
    @autoreleasepool {
        char dir[] = "/tmp/appkit-print-operation.XXXXXX";
        NSString *path;

        CHECK(mkdtemp(dir) != NULL, "temporary directory");
        path = [[NSString stringWithUTF8String: dir] stringByAppendingPathComponent: @"job.pdf"];

        NSPrintInfo *info = [[[NSPrintInfo alloc] init] autorelease];
        [info setPaperSize: NSMakeSize(595, 842)];
        [info setOrientation: NSLandscapeOrientation];

        NSView *view = [[[PrintedView alloc] initWithFrame: NSMakeRect(0, 0, 400, 300)] autorelease];
        NSPrintOperation *operation = [NSPrintOperation printOperationWithView: view printInfo: info];
        [[operation printInfo] setJobDisposition: NSPrintSaveJob];
        [[[operation printInfo] dictionary] setObject: path forKey: NSPrintSavePath];
        [operation setShowsPrintPanel: NO];
        [operation setShowsProgressPanel: NO];
        CHECK([operation runOperation], "the operation ran");

        NSURL *url = [NSURL fileURLWithPath: path];
        CGPDFDocumentRef document = CGPDFDocumentCreateWithURL((CFURLRef) url);
        CHECK(document != NULL, "the file is a PDF");
        if (document) {
            CHECK(CGPDFDocumentGetNumberOfPages(document) == 1, "the view is one page");
            CGPDFDocumentRelease(document);
        }
        unlink([path fileSystemRepresentation]);
        rmdir(dir);
    }
    printf(failures ? "FAIL appkit-print-operation-pdf-job\n" : "PASS appkit-print-operation-pdf-job\n");
    return failures != 0;
}
