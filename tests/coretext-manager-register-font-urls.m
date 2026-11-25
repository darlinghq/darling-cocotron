/* Copyright (C) 2026 Lubos Dolezel */
/* CTFontManagerRegisterFontURLs registers the fonts of files and hands the
 * errors of those that failed to its handler: once, before it returns, with
 * done set (observed on macOS 26.7.3). The error codes are those of
 * CTFontManagerErrors.h; an empty list gets EINVAL. kCTFontDownloadableAttribute
 * and kCTFontDownloadedAttribute are 0 for an installed font. */
#import <Foundation/Foundation.h>
#import <CoreText/CoreText.h>
#include <errno.h>
#include <stdio.h>
#include <unistd.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

// Registers the URLs; returns the errors of the one handler call, or nil
// when the handler was not called exactly once, with done, before returning.
static NSArray *registerURLs(NSArray *urls)
{
    __block int calls = 0;
    __block BOOL done = NO;
    __block NSArray *errors = nil;
    CTFontManagerRegisterFontURLs((CFArrayRef) urls, kCTFontManagerScopeProcess, true, ^bool(CFArrayRef list, bool last) {
        calls++;
        done = last;
        errors = [[(NSArray *) list copy] autorelease];
        return true;
    });
    return calls == 1 && done ? errors : nil;
}

static BOOL isFontError(NSError *error, CFIndex code, NSURL *url)
{
    NSArray *urls = [[error userInfo] objectForKey: (NSString *) kCTFontManagerErrorFontURLsKey];
    return [[error domain] isEqualToString: (NSString *) kCTFontManagerErrorDomain] && [error code] == code
        && [urls count] == 1 && [[urls objectAtIndex: 0] isEqual: url];
}

int main(void)
{
    @autoreleasepool {
        CHECK([(NSString *) kCTFontDownloadableAttribute isEqualToString: @"NSCTFontDownloadableAttribute"]);
        CHECK([(NSString *) kCTFontDownloadedAttribute isEqualToString: @"NSCTFontDownloadedAttribute"]);

        CTFontRef installed = CTFontCreateWithName(CFSTR("Helvetica"), 12, NULL);
        CFTypeRef downloadable = CTFontCopyAttribute(installed, kCTFontDownloadableAttribute);
        CFTypeRef downloaded = CTFontCopyAttribute(installed, kCTFontDownloadedAttribute);
        // Quirk: a CFNumber 0 rather than kCFBooleanFalse (macOS 26.7.3).
        CHECK(downloadable != NULL && CFGetTypeID(downloadable) == CFNumberGetTypeID() && [(NSNumber *) downloadable intValue] == 0);
        CHECK(downloaded != NULL && CFGetTypeID(downloaded) == CFNumberGetTypeID() && [(NSNumber *) downloaded intValue] == 0);
        CHECK(downloaded != kCFBooleanFalse);
        if (downloadable != NULL)
            CFRelease(downloadable);
        if (downloaded != NULL)
            CFRelease(downloaded);

        // A copy of an installed font's file, at a path that was never registered.
        NSURL *source = [(NSURL *) CTFontCopyAttribute(installed, kCTFontURLAttribute) autorelease];
        CFRelease(installed);
        CHECK(source != nil);
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                [NSString stringWithFormat: @"register-font-urls-%d.%@", getpid(), [[source path] pathExtension]]];
        NSURL *font = [NSURL fileURLWithPath: path];
        [[NSFileManager defaultManager] removeItemAtURL: font error: NULL];
        CHECK([[NSFileManager defaultManager] copyItemAtURL: source toURL: font error: NULL]);

        NSArray *errors = registerURLs(@[font]);
        CHECK(errors != nil && [errors count] == 0);

        // Registered already, missing, not a font: an error each, in order.
        NSURL *missing = [NSURL fileURLWithPath: @"/nonexistent/font.ttf"];
        NSString *textPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                [NSString stringWithFormat: @"register-font-urls-%d.txt", getpid()]];
        [@"not a font" writeToFile: textPath atomically: NO encoding: NSUTF8StringEncoding error: NULL];
        NSURL *text = [NSURL fileURLWithPath: textPath];
        errors = registerURLs(@[font, missing, text]);
        CHECK(errors != nil && [errors count] == 3);
        if ([errors count] == 3) {
            CHECK(isFontError([errors objectAtIndex: 0], kCTFontManagerErrorAlreadyRegistered, font));
            CHECK(isFontError([errors objectAtIndex: 1], kCTFontManagerErrorFileNotFound, missing));
            CHECK(isFontError([errors objectAtIndex: 2], kCTFontManagerErrorUnrecognizedFormat, text));
        }

        errors = registerURLs(@[]);
        CHECK(errors != nil && [errors count] == 1);
        if ([errors count] == 1) {
            NSError *error = [errors objectAtIndex: 0];
            CHECK([[error domain] isEqualToString: NSPOSIXErrorDomain] && [error code] == EINVAL);
        }

        // No handler is fine.
        CTFontManagerRegisterFontURLs((CFArrayRef) @[font], kCTFontManagerScopeProcess, false, NULL);

        [[NSFileManager defaultManager] removeItemAtURL: font error: NULL];
        [[NSFileManager defaultManager] removeItemAtURL: text error: NULL];
    }
    if (failures == 0)
        printf("PASS\n");
    return failures != 0;
}
