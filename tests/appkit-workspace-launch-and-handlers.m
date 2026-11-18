/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// NSWorkspace on LaunchServices: openApplicationAtURL:configuration:completionHandler:,
// openURLs:withApplicationAtURL:configuration:completionHandler:, launchApplicationAtURL:options:
// configuration:error:, URLsForApplicationsToOpenURL:, URLsForApplicationsWithBundleIdentifier:,
// iconForContentType: and the three setDefaultApplicationAtURL: variants, with a helper application (a copy
// of this program in a bundle; it runs as the helper when started from inside a .app). An application that
// does not exist gets NSCocoaErrorDomain / NSFileReadNoSuchFileError from every call. Prints PASS on
// success. Needs a window system session (X11 or Wayland) and changes the default handlers of a
// throw-away scheme and file type, so it is not for a Mac user account.
#import <AppKit/AppKit.h>
#import <CoreServices/CoreServices.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static int failures;

static void expect(BOOL condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

static BOOL runsFromBundle(void) {
    return [[[NSBundle mainBundle] executablePath] containsString: @".app/Contents/MacOS/"];
}

static void expectMissingApplicationError(NSError *error, const char *what) {
    NSString *text = [NSString stringWithFormat: @"%s: NSCocoaErrorDomain / NSFileReadNoSuchFileError", what];
    expect(error != nil && [error.domain isEqualToString: NSCocoaErrorDomain] &&
                   error.code == NSFileReadNoSuchFileError,
           [text UTF8String]);
}

static void endApplication(NSRunningApplication *app) {
    if (app == nil)
        return;
    [app terminate];
    for (int i = 0; i < 100 && ![app isTerminated]; i++)
        usleep(100 * 1000);
    if (![app isTerminated])
        kill([app processIdentifier], SIGKILL);
}

int main(void) {
    @autoreleasepool {
        if (runsFromBundle()) {
            [NSApplication sharedApplication];
            NSDate *end = [NSDate dateWithTimeIntervalSinceNow: 90];
            while ([end timeIntervalSinceNow] > 0)
                CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, false);
            return 3;
        }

        NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *tag = [NSString stringWithFormat: @"%d", (int) getpid()];
        NSString *apps = [NSHomeDirectory() stringByAppendingPathComponent: @"Applications"];
        NSString *bundle = [apps stringByAppendingPathComponent: [NSString stringWithFormat: @"darlingws%@.app", tag]];
        NSString *macos = [bundle stringByAppendingPathComponent: @"Contents/MacOS"];
        NSString *identifier = [@"org.darlinghq.test.workspace" stringByAppendingString: tag];
        NSString *scheme = [@"darlingwsscheme" stringByAppendingString: tag];
        NSString *extension = [@"dws" stringByAppendingString: tag];
        [fm createDirectoryAtPath: macos withIntermediateDirectories: YES attributes: nil error: NULL];
        [fm copyItemAtPath: [[NSBundle mainBundle] executablePath]
                    toPath: [macos stringByAppendingPathComponent: @"helper"]
                     error: NULL];
        [@{
            @"CFBundleIdentifier" : identifier,
            @"CFBundleExecutable" : @"helper",
            @"CFBundlePackageType" : @"APPL",
            @"CFBundleName" : @"helper",
            @"CFBundleVersion" : @"1",
            @"LSUIElement" : @YES,
            @"CFBundleURLTypes" : @[ @{@"CFBundleURLName" : identifier, @"CFBundleURLSchemes" : @[ scheme ]} ],
            @"CFBundleDocumentTypes" :
                @[ @{@"CFBundleTypeName" : @"Test", @"CFBundleTypeRole" : @"Editor", @"CFBundleTypeExtensions" : @[ extension ]} ],
        } writeToFile: [bundle stringByAppendingPathComponent: @"Contents/Info.plist"] atomically: YES];
        NSURL *bundleURL = [NSURL fileURLWithPath: bundle isDirectory: YES];
        NSURL *missing = [NSURL fileURLWithPath: @"/nonexistent/Nope.app" isDirectory: YES];
        NSURL *file = [NSURL fileURLWithPath: [@"/tmp/darlingws-document." stringByAppendingString: extension]];
        expect(LSRegisterURL((CFURLRef) bundleURL, true) == noErr, "helper registered");

        // Icons by content type.
        expect([workspace iconForContentType: UTTypePlainText] != nil, "an icon for plain text");
        expect([workspace iconForContentType: UTTypeFolder] != nil, "an icon for folders");

        // Applications for items.
        NSArray *byIdentifier = [workspace URLsForApplicationsWithBundleIdentifier: identifier];
        expect([byIdentifier count] == 1, "the registered helper is found by its identifier");
        NSArray *unknown = [workspace URLsForApplicationsWithBundleIdentifier: @"org.darlinghq.test.nosuch"];
        expect(unknown != nil && [unknown count] == 0, "an unknown identifier gives an empty array");
        NSArray *forScheme = [workspace URLsForApplicationsToOpenURL: [NSURL URLWithString: [scheme stringByAppendingString: @"://x"]]];
        expect([forScheme count] == 1, "the helper opens its URL scheme");
        NSArray *forFile = [workspace URLsForApplicationsToOpenURL: file];
        expect([forFile count] == 1, "the helper opens files with its extension");
        NSArray *forWeb = [workspace URLsForApplicationsToOpenURL: [NSURL URLWithString: @"https://example.com/"]];
        expect(forWeb != nil, "a web URL gets an array, possibly empty");
        expect([[workspace URLsForApplicationsToOpenURL: [NSURL URLWithString: @"darlingnosuchscheme://x"]] count] == 0,
               "an unregistered scheme has no applications");

        // Default applications.
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        __block NSError *result = nil;
        void (^handler)(NSError *) = ^(NSError *error) {
            result = [error retain];
            dispatch_semaphore_signal(done);
        };
        UTType *type = [UTType typeWithFilenameExtension: extension];
        expect(type != nil, "a content type for the extension");

        [workspace setDefaultApplicationAtURL: bundleURL toOpenURLsWithScheme: scheme completionHandler: handler];
        dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
        expect(result == nil, "the default for a scheme is set");
        CFStringRef schemeHandler = LSCopyDefaultHandlerForURLScheme((CFStringRef) scheme);
        expect(schemeHandler != NULL && [(NSString *) schemeHandler caseInsensitiveCompare: identifier] == NSOrderedSame,
               "the scheme's default is the helper");
        if (schemeHandler != NULL)
            CFRelease(schemeHandler);
        [result release];

        result = nil;
        [workspace setDefaultApplicationAtURL: bundleURL toOpenContentType: type completionHandler: handler];
        dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
        expect(result == nil, "the default for a content type is set");
        CFStringRef typeHandler = LSCopyDefaultRoleHandlerForContentType((CFStringRef) type.identifier, kLSRolesAll);
        expect(typeHandler != NULL && [(NSString *) typeHandler caseInsensitiveCompare: identifier] == NSOrderedSame,
               "the content type's default is the helper");
        if (typeHandler != NULL)
            CFRelease(typeHandler);
        [result release];

        result = nil;
        [workspace setDefaultApplicationAtURL: bundleURL toOpenFileAtURL: file completionHandler: handler];
        dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
        expect(result == nil, "the default for a file is set");
        [result release];

        for (int variant = 0; variant < 3; variant++) {
            result = nil;
            if (variant == 0)
                [workspace setDefaultApplicationAtURL: missing toOpenURLsWithScheme: scheme completionHandler: handler];
            else if (variant == 1)
                [workspace setDefaultApplicationAtURL: missing toOpenContentType: type completionHandler: handler];
            else
                [workspace setDefaultApplicationAtURL: missing toOpenFileAtURL: file completionHandler: handler];
            dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
            expectMissingApplicationError(result, "setDefaultApplicationAtURL: for a missing application");
            [result release];
        }

        // Errors for an application that does not exist.
        NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration];
        __block NSError *openError = nil;
        __block NSRunningApplication *openApp = (NSRunningApplication *) @"unset";
        [workspace openApplicationAtURL: missing
                          configuration: configuration
                      completionHandler: ^(NSRunningApplication *app, NSError *error) {
                          openApp = app;
                          openError = [error retain];
                          dispatch_semaphore_signal(done);
                      }];
        dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
        expect(openApp == nil, "no application for a missing one");
        expectMissingApplicationError(openError, "openApplicationAtURL:");
        [openError release];
        openError = nil;
        [workspace openURLs: @[ file ]
                withApplicationAtURL: missing
                       configuration: configuration
                   completionHandler: ^(NSRunningApplication *app, NSError *error) {
                       openError = [error retain];
                       dispatch_semaphore_signal(done);
                   }];
        dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
        expectMissingApplicationError(openError, "openURLs:withApplicationAtURL:");
        [openError release];
        NSError *launchError = nil;
        expect([workspace launchApplicationAtURL: missing options: 0 configuration: @{} error: &launchError] == nil,
               "launchApplicationAtURL: of a missing application gives nil");
        expectMissingApplicationError(launchError, "launchApplicationAtURL:");

        // Applications that LaunchServices starts are launchd jobs and take their environment from launchd:
        // give it the window system settings of this process.
        const char *settings[] = {"DISPLAY", "WAYLAND_DISPLAY", "XDG_RUNTIME_DIR", "DARLING_APPKIT_BACKEND"};
        for (size_t i = 0; i < sizeof(settings) / sizeof(settings[0]); i++) {
            const char *name = settings[i];
            const char *value = getenv(name);
            if (value != NULL) {
                NSString *command = [NSString stringWithFormat: @"launchctl setenv %s '%s' >/dev/null 2>&1", name, value];
                system([command UTF8String]);
            }
        }

        // Opening the helper.
        __block NSRunningApplication *opened = nil;
        __block NSError *error1 = nil;
        [workspace openApplicationAtURL: bundleURL
                          configuration: configuration
                      completionHandler: ^(NSRunningApplication *app, NSError *error) {
                          opened = [app retain];
                          error1 = [error retain];
                          dispatch_semaphore_signal(done);
                      }];
        expect(dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC)) == 0,
               "the open completes");
        expect(error1 == nil, "opening the helper succeeds");
        expect(opened != nil, "the open gives the running application");
        if (opened != nil) {
            expect([[[opened.bundleURL path] stringByResolvingSymlinksInPath] isEqualToString:
                                                 [bundle stringByResolvingSymlinksInPath]],
                   "it is the helper");
            expect([opened.bundleIdentifier isEqualToString: identifier], "with the helper's identifier");
        }
        [error1 release];

        // A document for the running helper (the application has no handler: the request still succeeds).
        __block NSError *error2 = nil;
        [workspace openURLs: @[ file ]
                withApplicationAtURL: bundleURL
                       configuration: configuration
                   completionHandler: ^(NSRunningApplication *app, NSError *error) {
                       error2 = [error retain];
                       dispatch_semaphore_signal(done);
                   }];
        dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC));
        expect(error2 == nil, "opening a document with the helper succeeds");
        [error2 release];
        endApplication(opened);
        [opened release];

        NSError *error3 = nil;
        NSRunningApplication *launched = [workspace launchApplicationAtURL: bundleURL
                                                                   options: NSWorkspaceLaunchNewInstance
                                                             configuration: @{}
                                                                     error: &error3];
        expect(launched != nil && error3 == nil, "launchApplicationAtURL: starts the helper");
        endApplication(launched);

        [fm removeItemAtPath: bundle error: NULL];
    }
    if (failures == 0)
        printf("PASS\n");
    return failures == 0 ? 0 : 1;
}
