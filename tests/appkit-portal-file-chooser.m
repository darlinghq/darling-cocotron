// Copyright (C) 2026 Lubos Dolezel
//
// Licensed under the MIT license, the same as the rest of this project.
//
// The panels through a file chooser portal, one scenario per run; the host script run.py in
// appkit-portal-file-chooser/ starts a private session bus with a fake portal and checks what the portal
// was asked and what this program got. Darling only.
//
//   appkit-portal-file-chooser MODE [SETTING]
//
// Modes: open (modal, several files), single (modal, one file), folder (modal, folders only), save (modal,
// type with an extension), sheet (begin a sheet on a window), begin (modeless with a completion handler),
// accessory (an accessory view: the built-in panel is used), delegate (a filtering delegate: built-in panel),
// plain (no portal is asked for: the built-in panel).
//
// SETTING says where the DesktopFileChooser preference is set, in this process only (the values are removed
// again before exit): "domain" (default) sets it in the org.darlinghq.AppKit domain, "app" in the
// application's own domain, "app-off" sets it in the domain but NO in the application's domain (the
// application's value wins: built-in panel), "off" sets nothing (built-in panel).
//
// A built-in panel is cancelled by this program once it is up. Each run prints
// "RESULT <response> <path>|<path>..." and "DONE".
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

@interface FilteringDelegate : NSObject <NSOpenSavePanelDelegate>
@end
@implementation FilteringDelegate
- (BOOL) panel: (id) sender shouldEnableURL: (NSURL *) url {
    return YES;
}
@end

static void report(NSInteger response, NSArray *paths) {
    printf("RESULT %ld %s\n", (long) response, [[paths componentsJoinedByString: @"|"] UTF8String]);
    fflush(stdout);
}

static void spin(BOOL (^done)(void), NSTimeInterval limit) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow: limit];
    while (!done() && [end timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                 beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
}

static NSArray *pathsOf(NSSavePanel *panel) {
    if ([panel isKindOfClass: [NSOpenPanel class]]) {
        NSMutableArray *paths = [NSMutableArray array];
        for (NSURL *url in [(NSOpenPanel *) panel URLs])
            [paths addObject: [url path]];
        return paths;
    }
    return [panel URL] != nil ? @[ [[panel URL] path] ] : @[];
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 2)
            return 2;
        const char *mode = argv[1];
        const char *setting = argc > 2 ? argv[2] : "domain";
        CFStringRef key = CFSTR("DesktopFileChooser");
        CFStringRef domain = CFSTR("org.darlinghq.AppKit");
        if (!strcmp(setting, "domain") || !strcmp(setting, "app-off"))
            CFPreferencesSetAppValue(key, kCFBooleanTrue, domain);
        if (!strcmp(setting, "app"))
            CFPreferencesSetAppValue(key, kCFBooleanTrue, kCFPreferencesCurrentApplication);
        if (!strcmp(setting, "app-off"))
            CFPreferencesSetAppValue(key, kCFBooleanFalse, kCFPreferencesCurrentApplication);
        [NSApplication sharedApplication];

        NSSavePanel *panel = nil;
        if (!strcmp(mode, "save")) {
            panel = [NSSavePanel savePanel];
            [panel setNameFieldStringValue: @"Report"];
            [panel setAllowedFileTypes: @[ @"txt" ]];
            [panel setPrompt: @"Export"];
        } else if (!strcmp(mode, "folder")) {
            NSOpenPanel *open = [NSOpenPanel openPanel];
            [open setCanChooseFiles: NO];
            [open setCanChooseDirectories: YES];
            panel = open;
        } else {
            NSOpenPanel *open = [NSOpenPanel openPanel];
            [open setAllowsMultipleSelection: strcmp(mode, "single") != 0];
            [open setAllowedFileTypes: @[ @"txt" ]];
            // A small folder: the built-in panel lists the folder it is given even before it is shown.
            const char *start = getenv("PORTAL_TEST_DIR");
            if (start != NULL)
                [open setDirectoryURL: [NSURL fileURLWithPath: [@"/Volumes/SystemRoot" stringByAppendingString: [NSString stringWithUTF8String: start]]]];
            [open setMessage: @"Choose notes"];
            panel = open;
            if (!strcmp(mode, "accessory"))
                [panel setAccessoryView: [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 50, 20)] autorelease]];
            if (!strcmp(mode, "delegate"))
                [panel setDelegate: [[FilteringDelegate new] autorelease]];
        }

        BOOL builtIn = !strcmp(mode, "accessory") || !strcmp(mode, "delegate") || !strcmp(mode, "plain");
        // The built-in panel waits for the user; stop it. A portal run is answered long before the later
        // cancel, which only ends a run that wrongly shows the built-in panel.
        [panel performSelector: @selector(cancel:) withObject: nil afterDelay: builtIn ? 1.5 : 10
                       inModes: @[ NSDefaultRunLoopMode, NSModalPanelRunLoopMode ]];

        if (!strcmp(mode, "begin")) {
            __block BOOL finished = NO;
            [panel beginWithCompletionHandler: ^(NSModalResponse response) {
                report(response, pathsOf(panel));
                finished = YES;
            }];
            printf("RETURNED\n");
            fflush(stdout);
            spin(^{ return finished; }, 20);
        } else if (!strcmp(mode, "sheet")) {
            NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 300, 200)
                                                            styleMask: NSTitledWindowMask
                                                              backing: NSBackingStoreBuffered
                                                                defer: NO];
            [window makeKeyAndOrderFront: nil];
            spin(^{ return NO; }, 1);
            __block BOOL finished = NO;
            [panel beginSheetModalForWindow: window
                          completionHandler: ^(NSModalResponse response) {
                report(response, pathsOf(panel));
                finished = YES;
            }];
            printf("RETURNED\n");
            fflush(stdout);
            spin(^{ return finished; }, 20);
        } else {
            NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 300, 200)
                                                            styleMask: NSTitledWindowMask
                                                              backing: NSBackingStoreBuffered
                                                                defer: NO];
            [window makeKeyAndOrderFront: nil];
            spin(^{ return NO; }, 1);
            NSInteger response = [panel runModal];
            report(response, pathsOf(panel));
        }
        printf("DONE\n");
        CFPreferencesSetAppValue(key, NULL, domain);
        CFPreferencesSetAppValue(key, NULL, kCFPreferencesCurrentApplication);
    }
    return 0;
}
