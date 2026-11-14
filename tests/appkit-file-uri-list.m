/*
 Copyright (C) 2026 Darling Developers

 Licensed under the MIT license, the same as the rest of this project.
*/
// The text/uri-list conversion the clipboard and drag-and-drop code of every window
// backend shares (RFC 2483, file: URIs, RFC 3986 percent-encoding). Host paths appear
// in the guest below /Volumes/SystemRoot. Needs no window server.
#import <AppKit/AppKit.h>
#include <stdio.h>

NSArray *DarlingFilenamesFromURIList(NSData *data);
NSData *DarlingURIListFromFilenames(NSArray *filenames);

static int failures;

static void expect(BOOL pass, const char *name) {
    if (!pass) {
        fprintf(stderr, "FAIL: %s\n", name);
        failures++;
    }
}

static NSData *bytes(NSString *s) {
    return [s dataUsingEncoding: NSUTF8StringEncoding];
}

int main(void) {
    @autoreleasepool {
        NSArray *files = @[@"/Volumes/SystemRoot/tmp/a b#%日本語", @"/Volumes/SystemRoot/tmp/new\nline"];
        NSData *wire = DarlingURIListFromFilenames(files);
        expect([wire isEqual: bytes(@"file:///tmp/a%20b%23%25%E6%97%A5%E6%9C%AC%E8%AA%9E\r\nfile:///tmp/new%0Aline\r\n")],
               "exact UTF-8 escaping and CRLF");
        expect([DarlingFilenamesFromURIList(wire) isEqual: files], "multi-file round trip");
        expect([DarlingFilenamesFromURIList(bytes(@"# comment\r\n\nFILE://LOCALHOST/tmp/a\r\nfile:/tmp/b\n"))
                       isEqual: @[@"/Volumes/SystemRoot/tmp/a", @"/Volumes/SystemRoot/tmp/b"]],
               "comments, blank lines, localhost and scheme case");

        for (NSString *bad in @[@"file://remote/tmp/a", @"file:relative", @"file:///a?query", @"file:///a#fragment",
                                @"file:///a%", @"file:///a%GG", @"file:///a%00", @"file:///a%FF",
                                @"file:///a/../b", @"file:///a/%2e%2e/b", @"file:////server/share",
                                @"https://example.com/a", @"file:///raw space", @"file:///raw\rbreak",
                                @"file:///a%2Fb", @"file:///a%2fb"]) {
            expect(DarlingFilenamesFromURIList(bytes(bad)) == nil, [bad UTF8String]);
            expect(DarlingFilenamesFromURIList(bytes([@"file:///valid\n" stringByAppendingString: bad])) == nil,
                   "an invalid entry rejects the whole list");
        }

        expect(DarlingURIListFromFilenames(@[@"/tmp/guest-only"]) == nil, "guest-only path refused");
        expect(DarlingURIListFromFilenames(@[@"/Volumes/SystemRoot/tmp/ok", @"/tmp/guest-only"]) == nil,
               "a mixed export is all or nothing");
        expect(DarlingURIListFromFilenames(@[@"/Volumes/SystemRooted/tmp/no"]) == nil, "host boundary is exact");
        expect(DarlingURIListFromFilenames(@[@"/Volumes/SystemRoot/tmp/../no"]) == nil, "parent traversal refused");
        expect(DarlingURIListFromFilenames(@[@42]) == nil, "non-string entry refused");
        expect(DarlingURIListFromFilenames(@[]) == nil, "empty export refused");
        expect(DarlingFilenamesFromURIList(bytes(@"# only comment\n")) == nil, "a list without entries refused");

        char nul[] = "file:///tmp/a\0hidden";
        expect(DarlingFilenamesFromURIList([NSData dataWithBytes: nul length: sizeof(nul) - 1]) == nil,
               "embedded NUL refused");
        NSString *longPath = [@"/Volumes/SystemRoot/" stringByPaddingToLength: 4096 withString: @"a" startingAtIndex: 0];
        expect(DarlingURIListFromFilenames(@[longPath]) == nil, "path length bound");
        expect(DarlingFilenamesFromURIList(bytes([@"file:///" stringByPaddingToLength: 16384 withString: @"a/"
                                                                    startingAtIndex: 0])) == nil,
               "overlong path refused");
        expect(DarlingFilenamesFromURIList(bytes([@"" stringByPaddingToLength: 4097 withString: @"\n"
                                                                startingAtIndex: 0])) == nil,
               "excessive blank records refused before splitting");
        NSMutableArray *many = [NSMutableArray array];
        for (int i = 0; i < 4097; i++)
            [many addObject: @"/Volumes/SystemRoot/tmp/a"];
        expect(DarlingURIListFromFilenames(many) == nil, "excessive record count refused");
    }
    printf(failures ? "FAIL\n" : "PASS\n");
    return failures ? 1 : 0;
}
