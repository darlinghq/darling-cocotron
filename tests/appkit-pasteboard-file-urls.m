// CFLAGS: -framework Foundation -framework AppKit
// Copyright (C) 2026 Lubos Dolezel
//
// File URLs on a pasteboard: written as NSURL objects, written as the older
// NSFilenamesPboardType list, and read back with the URL reading options
// (NSPasteboard and NSURL's NSPasteboardReading documentation). What the
// documentation leaves open was observed on macOS 26.7.3 and 10.14.4
// (darling's tests/collection-view.md); the program passes unchanged on both.
// Uses a uniquely named pasteboard and two files it makes in the temporary
// directory.
//
// Prints PASS or FAIL lines, then ALL PASSED or FAILED n.
#import <AppKit/AppKit.h>
#include <stdarg.h>
#include <stdio.h>

static int failures;
static void expect(BOOL ok, const char *format, ...) __attribute__((format(printf, 2, 3)));
static void expect(BOOL ok, const char *format, ...)
{
    va_list args;
    va_start(args, format);
    printf(ok ? "PASS: " : "FAIL: ");
    vprintf(format, args);
    printf("\n");
    va_end(args);
    if (!ok)
        failures++;
}

static NSString *text, *image; // the two files: a text file and a PNG image

static NSArray *pathsOf(NSArray *urls)
{
    NSMutableArray *paths = [NSMutableArray array];
    for (id url in urls)
        [paths addObject: [url isKindOfClass: [NSURL class]] ? ([url isFileURL] ? [url path] : [url absoluteString])
                                                             : [url description]];
    return paths;
}

static NSString *joined(NSArray *array)
{
    return [array componentsJoinedByString: @","];
}

static NSArray *readURLs(NSPasteboard *pasteboard, NSDictionary *options)
{
    return [pasteboard readObjectsForClasses: @[[NSURL class]] options: options];
}

static void test_written_urls_are_items(NSPasteboard *pasteboard)
{
    [pasteboard clearContents];
    BOOL wrote = [pasteboard writeObjects: @[[NSURL fileURLWithPath: text], [NSURL fileURLWithPath: image]]];
    expect(wrote, "two file URLs are written");
    NSArray *items = [pasteboard pasteboardItems];
    expect([items count] == 2, "they are two items (%lu)", (unsigned long) [items count]);
    for (NSPasteboardItem *item in items)
        expect([[item types] containsObject: NSPasteboardTypeFileURL], "an item has public.file-url (%s)",
               [joined([item types]) UTF8String]);
    NSArray *urls = readURLs(pasteboard, nil);
    expect([joined(pathsOf(urls)) isEqual: joined(@[text, image])], "they read back as the two file URLs, in order (%s)",
           [joined(pathsOf(urls)) UTF8String]);
    id filenames = [pasteboard propertyListForType: NSFilenamesPboardType];
    expect([filenames isEqual: @[text, image]], "NSFilenamesPboardType gives their paths (%s)",
           [[filenames description] UTF8String]);
}

static void test_filenames_read_as_urls(NSPasteboard *pasteboard)
{
    [pasteboard declareTypes: @[NSFilenamesPboardType] owner: nil];
    BOOL set = [pasteboard setPropertyList: @[text, image] forType: NSFilenamesPboardType];
    expect(set, "a list of filenames is set");
    expect([[pasteboard types] containsObject: NSPasteboardTypeFileURL],
           "a pasteboard holding filenames has public.file-url among its types (%s)",
           [joined([pasteboard types]) UTF8String]);
    expect([[pasteboard availableTypeFromArray: @[NSPasteboardTypeFileURL]] isEqual: NSPasteboardTypeFileURL],
           "availableTypeFromArray: finds public.file-url");
    NSString *first = [[NSURL fileURLWithPath: text] absoluteString];
    NSString *string = [pasteboard stringForType: NSPasteboardTypeFileURL];
    expect([string isEqual: first], "stringForType: public.file-url is the first file's URL (%s)", [string UTF8String]);
    NSData *data = [pasteboard dataForType: NSPasteboardTypeFileURL];
    expect([data isEqual: [first dataUsingEncoding: NSUTF8StringEncoding]], "dataForType: public.file-url is it too (%s)",
           [[[[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding] autorelease] UTF8String]);
    NSArray *items = [pasteboard pasteboardItems];
    expect([items count] == 2, "the filenames are two items (%lu)", (unsigned long) [items count]);
    NSArray *urls = readURLs(pasteboard, nil);
    expect([urls count] == 2 && [[urls objectAtIndex: 0] isFileURL] &&
               [joined(pathsOf(urls)) isEqual: joined(@[text, image])],
           "the filenames read as file URLs, in order (%s)", [joined(pathsOf(urls)) UTF8String]);
}

static void test_file_urls_only(NSPasteboard *pasteboard)
{
    [pasteboard clearContents];
    [pasteboard writeObjects: @[[NSURL URLWithString: @"https://example.com/page"], [NSURL fileURLWithPath: text]]];
    NSArray *all = readURLs(pasteboard, nil);
    expect([all count] == 2, "both URLs read without options (%s)", [joined(pathsOf(all)) UTF8String]);
    NSDictionary *options = @{NSPasteboardURLReadingFileURLsOnlyKey: @YES};
    NSArray *files = readURLs(pasteboard, options);
    expect([joined(pathsOf(files)) isEqual: text], "NSPasteboardURLReadingFileURLsOnlyKey keeps the file URL only (%s)",
           [joined(pathsOf(files)) UTF8String]);
    expect([pasteboard canReadObjectForClasses: @[[NSURL class]] options: options],
           "canReadObjectForClasses:options: agrees that one is readable");

    [pasteboard clearContents];
    [pasteboard writeObjects: @[[NSURL URLWithString: @"https://example.com/page"]]];
    expect([readURLs(pasteboard, options) count] == 0, "with only a web URL, nothing is read as a file URL");
    expect(![pasteboard canReadObjectForClasses: @[[NSURL class]] options: options],
           "and canReadObjectForClasses:options: agrees");
}

static void test_contents_conform_to_types(NSPasteboard *pasteboard)
{
    [pasteboard clearContents];
    [pasteboard writeObjects: @[[NSURL fileURLWithPath: text], [NSURL fileURLWithPath: image]]];
    NSDictionary *images = @{NSPasteboardURLReadingFileURLsOnlyKey: @YES,
                             NSPasteboardURLReadingContentsConformToTypesKey: @[@"public.image"]};
    NSArray *urls = readURLs(pasteboard, images);
    expect([joined(pathsOf(urls)) isEqual: image], "NSPasteboardURLReadingContentsConformToTypesKey keeps the image (%s)",
           [joined(pathsOf(urls)) UTF8String]);
    expect([pasteboard canReadObjectForClasses: @[[NSURL class]] options: images],
           "canReadObjectForClasses:options: agrees that the image is readable");
    NSDictionary *movies = @{NSPasteboardURLReadingFileURLsOnlyKey: @YES,
                             NSPasteboardURLReadingContentsConformToTypesKey: @[@"public.movie"]};
    expect([readURLs(pasteboard, movies) count] == 0, "no file conforms to public.movie");
    expect(![pasteboard canReadObjectForClasses: @[[NSURL class]] options: movies],
           "and canReadObjectForClasses:options: agrees");
}

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [NSApplication sharedApplication];
    NSString *directory = [NSTemporaryDirectory() stringByResolvingSymlinksInPath];
    NSString *unique = [[NSProcessInfo processInfo] globallyUniqueString];
    text = [[directory stringByAppendingPathComponent: [unique stringByAppendingString: @"-notes.txt"]] retain];
    image = [[directory stringByAppendingPathComponent: [unique stringByAppendingString: @"-picture.png"]] retain];
    [[@"notes" dataUsingEncoding: NSUTF8StringEncoding] writeToFile: text atomically: NO];
    static const unsigned char png[] = {0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n'};
    [[NSData dataWithBytes: png length: sizeof png] writeToFile: image atomically: NO];

    NSPasteboard *pasteboard = [NSPasteboard pasteboardWithUniqueName];
    test_written_urls_are_items(pasteboard);
    test_filenames_read_as_urls(pasteboard);
    test_file_urls_only(pasteboard);
    test_contents_conform_to_types(pasteboard);
    [pasteboard releaseGlobally];

    [[NSFileManager defaultManager] removeItemAtPath: text error: NULL];
    [[NSFileManager defaultManager] removeItemAtPath: image error: NULL];
    [text release];
    [image release];
    [pool release];
    if (failures)
        printf("FAILED %d\n", failures);
    else
        printf("ALL PASSED\n");
    return failures != 0;
}
