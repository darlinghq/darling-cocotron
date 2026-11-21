/* Copyright (C) 2026 Lubos Dolezel */
// -[NSWindowController windowTitleForDocumentDisplayName:]: the default implementation returns the display name
// unchanged and subclasses override it to customize the title
// (https://developer.apple.com/documentation/appkit/nswindowcontroller/windowtitle(fordocumentdisplayname:)).
// The checks run in a child process inside an application bundle whose Info.plist has a CFBundleName, because the
// default used to append the bundle name and a plain executable has none, so a run without the bundle could not
// tell the old behavior from the documented one. The test copies itself into the bundle, so it needs no argument.
// Needs a window system session (it creates windows). Build without ARC.
#import <AppKit/AppKit.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void expect(BOOL condition, NSString *message) {
    if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}

@interface SuffixController : NSWindowController
@end
@implementation SuffixController
- (NSString *)windowTitleForDocumentDisplayName:(NSString *)displayName {
    return [displayName stringByAppendingString:@" - Top"];
}
@end

@interface TitledDocument : NSDocument
@end
@implementation TitledDocument
- (NSString *)displayName { return @"Report.txt"; }
@end

static void checks(void) {
    [NSApplication sharedApplication];
    expect([[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"] length] > 0,
           @"the process runs in a bundle that has a CFBundleName");

    NSWindowController *controller = [[NSWindowController alloc] init];
    expect([[controller windowTitleForDocumentDisplayName:@"Report.txt"] isEqualToString:@"Report.txt"],
           @"the default title is the display name unchanged");
    expect([[controller windowTitleForDocumentDisplayName:@""] isEqualToString:@""],
           @"an empty display name stays empty");

    // A subclass override is what -synchronizeWindowTitleWithDocumentName applies to the window.
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 100, 100)
                                                   styleMask:NSWindowStyleMaskTitled
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES];
    SuffixController *custom = [[SuffixController alloc] initWithWindow:window];
    TitledDocument *document = [[TitledDocument alloc] init];
    [document addWindowController:custom];
    [custom synchronizeWindowTitleWithDocumentName];
    expect([[window title] isEqualToString:@"Report.txt - Top"], @"an override sets the window title");

    NSWindow *plainWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 100, 100)
                                                        styleMask:NSWindowStyleMaskTitled
                                                          backing:NSBackingStoreBuffered
                                                            defer:YES];
    NSWindowController *plain = [[NSWindowController alloc] initWithWindow:plainWindow];
    [document addWindowController:plain];
    [plain synchronizeWindowTitleWithDocumentName];
    expect([[plainWindow title] isEqualToString:@"Report.txt"], @"the default sets the document's display name");
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc == 2 && strcmp(argv[1], "bundle-child") == 0) {
            checks();
            return 0;
        }

        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *scratch = [NSTemporaryDirectory() stringByAppendingPathComponent:
                [NSString stringWithFormat:@"window-controller-title-%d", getpid()]];
        NSString *app = [scratch stringByAppendingPathComponent:@"Titled.app"];
        NSString *macos = [app stringByAppendingPathComponent:@"Contents/MacOS"];
        expect([fm createDirectoryAtPath:macos withIntermediateDirectories:YES attributes:nil error:NULL],
               @"create the bundle directory");
        NSString *exe = [macos stringByAppendingPathComponent:@"probe"];
        expect([fm copyItemAtPath:[NSString stringWithUTF8String:argv[0]] toPath:exe error:NULL],
               @"copy the executable into the bundle");
        NSDictionary *info = @{ @"CFBundleExecutable": @"probe", @"CFBundleIdentifier": @"test.window-title",
                                @"CFBundlePackageType": @"APPL", @"CFBundleName": @"Titled" };
        expect([info writeToFile:[app stringByAppendingPathComponent:@"Contents/Info.plist"] atomically:NO],
               @"write the Info.plist");

        NSTask *task = [[NSTask alloc] init];
        [task setLaunchPath:exe];
        [task setArguments:@[ @"bundle-child" ]];
        [task launch];
        [task waitUntilExit];
        int status = [task terminationStatus];
        [task release];
        [fm removeItemAtPath:scratch error:NULL];
        expect(status == 0, @"the checks pass inside the bundle");
        printf("OK\n");
    }
    return 0;
}
