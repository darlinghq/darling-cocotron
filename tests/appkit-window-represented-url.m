#import <AppKit/AppKit.h>
#include <stdlib.h>

static void expect(BOOL condition, NSString *message)
{
    if (!condition)
    {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

int main(void)
{
    @autoreleasepool
    {
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 100)
                                                       styleMask:NSWindowStyleMaskTitled
                                                         backing:NSBackingStoreBuffered
                                                           defer:YES];
        expect(window.representedURL == nil, @"no represented URL initially");

        NSURL *archive = [NSURL fileURLWithPath:@"/Users/me/system.logarchive"];
        window.representedURL = archive;
        expect([window.representedURL isEqual:archive], @"represented URL is kept");
        expect([window.representedFilename isEqual:@"/Users/me/system.logarchive"], @"a file URL sets the filename");

        window.representedFilename = @"/var/log/system.log";
        expect([window.representedURL isEqual:[NSURL fileURLWithPath:@"/var/log/system.log"]],
               @"the filename sets a file URL");

        NSURL *remote = [NSURL URLWithString:@"https://example.com/log"];
        window.representedURL = remote;
        expect([window.representedURL isEqual:remote], @"non-file URLs are kept");
        expect(window.representedFilename == nil, @"a non-file URL has no filename");

        window.representedURL = nil;
        expect(window.representedURL == nil && window.representedFilename == nil, @"clearing the URL clears both");

        [window release];
        NSLog(@"PASS: NSWindow representedURL");
    }
    return 0;
}
