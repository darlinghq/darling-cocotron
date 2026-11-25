#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern CGContextRef CGPDFContextCreateWithURL(CFURLRef, const CGRect *, CFDictionaryRef)
    __attribute__((weak_import));

// Contract: the CoreGraphics documentation page for CGPDFContextCreateWithURL.
// It returns a new PDF context that stores the PDF at the URL, or NULL if a
// context could not be created; mediaBox is the default page media box (NULL
// means 612 by 792); the context is released with CGContextRelease.
// The page does not say which inputs make creation fail. A URL in a missing directory
// gives NULL on macOS 26.7.3 and 10.14.4 (observed). The checks that a NULL URL (a crash
// on macOS) and a request for encryption (macOS creates the context; here
// CGPDFContextCreate refuses it, the PDF writer cannot encrypt) return NULL, and that a
// refused encryption request neither creates a file nor touches an existing one, are
// placeholder pins of this implementation, not macOS behaviour.

static int drawOnePage(CGContextRef context) {
    CGPDFContextBeginPage(context, NULL);
    CGContextSetRGBFillColor(context, 1, 0, 0, 1);
    CGContextFillRect(context, CGRectMake(10, 10, 50, 50));
    CGPDFContextEndPage(context);
    CGPDFContextClose(context);
    return 0;
}

// Runs every check inside dir; main removes dir whichever way this returns.
static int run(NSString *dir) {
    {
        NSString *path = [dir stringByAppendingPathComponent:@"out.pdf"];
        NSURL *url = [NSURL fileURLWithPath:path];

        // A page drawn into the context ends up in a PDF file at the URL.
        CGRect box = CGRectMake(0, 0, 200, 100);
        CGContextRef context = CGPDFContextCreateWithURL((CFURLRef)url, &box, NULL);
        if (!context) return 10;
        drawOnePage(context);
        CGContextRelease(context);

        NSData *file = [NSData dataWithContentsOfFile:path];
        if ([file length] < 5 || memcmp([file bytes], "%PDF-", 5) != 0) return 11;
        CGPDFDocumentRef document = CGPDFDocumentCreateWithURL((CFURLRef)url);
        if (!document) return 12;
        if (CGPDFDocumentGetNumberOfPages(document) != 1) return 13;
        CGPDFPageRef page = CGPDFDocumentGetPage(document, 1);
        if (!page) return 14;
        CGRect pageBox = CGPDFPageGetBoxRect(page, kCGPDFMediaBox);
        if (pageBox.size.width != 200 || pageBox.size.height != 100) return 15;
        CGPDFDocumentRelease(document);

        // Without a media box the default page is 612 by 792 points.
        NSString *path2 = [dir stringByAppendingPathComponent:@"default.pdf"];
        NSURL *url2 = [NSURL fileURLWithPath:path2];
        context = CGPDFContextCreateWithURL((CFURLRef)url2, NULL, NULL);
        if (!context) return 20;
        drawOnePage(context);
        CGContextRelease(context);
        document = CGPDFDocumentCreateWithURL((CFURLRef)url2);
        if (!document) return 21;
        page = CGPDFDocumentGetPage(document, 1);
        if (!page) return 22;
        pageBox = CGPDFPageGetBoxRect(page, kCGPDFMediaBox);
        if (pageBox.size.width != 612 || pageBox.size.height != 792) return 23;
        CGPDFDocumentRelease(document);

        // Placeholder pins (see the top of the file).
        if (CGPDFContextCreateWithURL(NULL, &box, NULL)) return 30;
        NSURL *missingDir = [NSURL fileURLWithPath:
            [dir stringByAppendingPathComponent:@"no-such-dir/out.pdf"]];
        if (CGPDFContextCreateWithURL((CFURLRef)missingDir, &box, NULL)) return 31;
        // A non-file URL is not pinned: macOS 26.7.3 and 10.14.4 return a context for an http URL, this
        // implementation returns NULL (the data consumer is for files only).
        NSDictionary *secret = [NSDictionary dictionaryWithObject:@"secret"
                                    forKey:(id)kCGPDFContextUserPassword];
        NSString *encPath = [dir stringByAppendingPathComponent:@"enc.pdf"];
        NSURL *url3 = [NSURL fileURLWithPath:encPath];
        if (CGPDFContextCreateWithURL((CFURLRef)url3, &box, (CFDictionaryRef)secret)) return 33;
        // A refused request does not create the file ...
        if ([[NSFileManager defaultManager] fileExistsAtPath:encPath]) return 34;
        // ... and does not touch a file that is already there.
        NSData *keep = [@"existing contents" dataUsingEncoding:NSASCIIStringEncoding];
        if (![keep writeToFile:encPath atomically:NO]) return 35;
        if (CGPDFContextCreateWithURL((CFURLRef)url3, &box, (CFDictionaryRef)secret)) return 36;
        if (![[NSData dataWithContentsOfFile:encPath] isEqualToData:keep]) return 37;
    }
    return 0;
}

int main(void) {
    @autoreleasepool {
        if (&CGPDFContextCreateWithURL == NULL) {
            fputs("CGPDFContextCreateWithURL is absent\n", stderr);
            return 5;
        }
        char tmpl[] = "/tmp/cgpdf-with-url-XXXXXX";
        if (!mkdtemp(tmpl)) return 6;
        NSString *dir = [NSString stringWithUTF8String:tmpl];
        int result = run(dir);
        [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
        if (result == 0)
            puts("CGPDFContextCreateWithURL passed");
        return result;
    }
}
