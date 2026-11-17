// Copyright (C) 2026 Lubos Dolezel
// appkit-launch-url-event: an application launched to open a URL (its initial Apple Event is kAEGetURL, sent here
// with LSOpenApplication) and using AppKit's own handler for it gets, in this order:
// applicationWillFinishLaunching:, application:openURLs: with the URL, then applicationDidFinishLaunching: with
// NSApplicationLaunchIsDefaultLaunchKey = NO, without opening an untitled document and without waiting for another
// event (did-finish within 3 s of will-finish). A URL sent while it runs also reaches application:openURLs:.
// The program copies its own executable into a throw-away application bundle, which records its callbacks in
// log.txt next to the bundle. Run with no arguments. Prints "FAIL: ..." for each check that does not hold and exits
// 1 if any did. Link with -framework AppKit -framework CoreServices. Also passes on macOS 26.7.3.
#import <AppKit/AppKit.h>
#include <CoreServices/CoreServices.h>
#include <mach-o/dyld.h>
#include <stdlib.h>
#include <unistd.h>

#define BUNDLE_ID "org.darlinghq.test.launch-url-event"

static int failures;

static void expect(BOOL ok, NSString *what)
{
    if (!ok)
    {
        printf("FAIL: %s\n", [what UTF8String]);
        failures++;
    }
}

@interface Recorder : NSObject <NSApplicationDelegate>
@end

@implementation Recorder
- (void)log:(NSString *)line
{
    NSString *path = [[[[NSBundle mainBundle] bundlePath] stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"log.txt"];
    FILE *file = fopen([path fileSystemRepresentation], "a");
    fprintf(file, "%s\n", [line UTF8String]);
    fclose(file);
}
- (void)applicationWillFinishLaunching:(NSNotification *)n
{
    [self log:[NSString stringWithFormat:@"willFinish %f", CFAbsoluteTimeGetCurrent()]];
}
- (void)applicationDidFinishLaunching:(NSNotification *)n
{
    [self log:[NSString stringWithFormat:@"didFinish %f default=%d", CFAbsoluteTimeGetCurrent(),
        [n.userInfo[NSApplicationLaunchIsDefaultLaunchKey] boolValue]]];
    [NSApp performSelector:@selector(terminate:) withObject:nil afterDelay:4];
}
- (BOOL)applicationOpenUntitledFile:(NSApplication *)app
{
    [self log:@"openUntitled"];
    return YES;
}
- (void)application:(NSApplication *)app openURLs:(NSArray<NSURL *> *)urls
{
    [self log:[@"openURLs " stringByAppendingString:[[urls valueForKey:@"absoluteString"] componentsJoinedByString:@" "]]];
}
@end

static NSArray *waitForLog(NSString *path, NSString *needle)
{
    NSArray *lines = nil;
    for (int i = 0; i < 150; i++)
    {
        NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
        lines = [[text stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsSeparatedByString:@"\n"];
        if (text != nil && [text rangeOfString:needle].location != NSNotFound)
            return lines;
        usleep(100000);
    }
    return lines;
}

static double timeOf(NSArray *lines, NSString *name)
{
    for (NSString *line in lines)
        if ([line hasPrefix:[name stringByAppendingString:@" "]])
            return [[[line componentsSeparatedByString:@" "] objectAtIndex:1] doubleValue];
    return 0;
}

static OSStatus openURL(NSString *app, NSString *url)
{
    NSAppleEventDescriptor *target = [NSAppleEventDescriptor descriptorWithDescriptorType:typeApplicationBundleID
        data:[@BUNDLE_ID dataUsingEncoding:NSUTF8StringEncoding]];
    NSAppleEventDescriptor *event = [NSAppleEventDescriptor appleEventWithEventClass:kInternetEventClass eventID:kAEGetURL
        targetDescriptor:target returnID:kAutoGenerateReturnID transactionID:kAnyTransactionID];
    [event setParamDescriptor:[NSAppleEventDescriptor descriptorWithString:url] forKeyword:keyDirectObject];
    FSRef ref;
    FSPathMakeRef((const UInt8 *)[app fileSystemRepresentation], &ref, NULL);
    LSApplicationParameters params = { 0, kLSLaunchDefaults, &ref, NULL, NULL, NULL, (AppleEvent *)[event aeDesc] };
    return LSOpenApplication(&params, NULL);
}

int main(int argc, char **argv)
{
    @autoreleasepool
    {
        if ([[[NSBundle mainBundle] bundlePath] hasSuffix:@".app"])
        {
            NSApplication *app = [NSApplication sharedApplication];
            app.delegate = [[Recorder alloc] init];
            [app run];
            return 0;
        }

        char exe[PATH_MAX], real[PATH_MAX];
        uint32_t size = sizeof(exe);
        char template[] = "/tmp/appkit-launch-url-event.XXXXXX";
        if (_NSGetExecutablePath(exe, &size) != 0 || mkdtemp(template) == NULL || realpath(template, real) == NULL)
            return 2;
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *dir = [NSString stringWithUTF8String:real];
        NSString *app = [dir stringByAppendingPathComponent:@"URLs.app"];
        NSString *log = [dir stringByAppendingPathComponent:@"log.txt"];
        [fm createDirectoryAtPath:[app stringByAppendingPathComponent:@"Contents/MacOS"] withIntermediateDirectories:YES attributes:nil error:NULL];
        [fm copyItemAtPath:[NSString stringWithUTF8String:exe] toPath:[app stringByAppendingPathComponent:@"Contents/MacOS/URLs"] error:NULL];
        [@{ @"CFBundleExecutable": @"URLs", @"CFBundleIdentifier": @BUNDLE_ID, @"CFBundlePackageType": @"APPL",
            @"CFBundleName": @"URLs" } writeToFile:[app stringByAppendingPathComponent:@"Contents/Info.plist"] atomically:NO];
        expect(LSRegisterURL((CFURLRef)[NSURL fileURLWithPath:app], true) == noErr, @"the application cannot be registered");

        expect(openURL(app, @"darlingtest://first") == noErr, @"the launch failed");
        NSArray *lines = waitForLog(log, @"didFinish");
        NSArray *names = [lines valueForKey:@"description"];
        NSMutableArray *sequence = [NSMutableArray array];
        for (NSString *line in names)
            [sequence addObject:[[line componentsSeparatedByString:@" "] firstObject]];
        expect([sequence isEqual:@[ @"willFinish", @"openURLs", @"didFinish" ]],
            [NSString stringWithFormat:@"the launch gives %@", lines]);
        expect([lines containsObject:@"openURLs darlingtest://first"], [NSString stringWithFormat:@"the URL: %@", lines]);
        expect([[lines lastObject] hasSuffix:@"default=0"], [NSString stringWithFormat:@"the default launch key: %@", lines]);
        double wait = timeOf(lines, @"didFinish") - timeOf(lines, @"willFinish");
        expect(wait < 3, [NSString stringWithFormat:@"did-finish came %.2f s after will-finish", wait]);

        expect(openURL(app, @"darlingtest://second") == noErr, @"the second open failed");
        lines = waitForLog(log, @"darlingtest://second");
        expect([lines containsObject:@"openURLs darlingtest://second"], [NSString stringWithFormat:@"while running: %@", lines]);

        sleep(5);
        [fm removeItemAtPath:dir error:NULL];
    }
    if (failures)
        return 1;
    printf("PASS\n");
    return 0;
}
