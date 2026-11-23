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
// accessory (an accessory view with no control: the built-in panel is used), accessory-text (an accessory view with
// a text field, which the portal cannot show: built-in panel), choices (an open panel whose accessory view is a
// pop-up button with its label and a check box: the portal gets them as choices and the controls get the answers,
// printed as "CONTROLS ..."), choices-save (a save panel whose pop-up's action changes the allowed file type),
// delegate (a filtering delegate: built-in panel),
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

// An accessory view of an encoding pop-up with its label, and a check box, as in a text editor's open panel;
// remembers how often the actions were sent.
@interface Accessory : NSObject {
@public
    NSView *view;
    NSPopUpButton *popUp;
    NSButton *check;
    NSSavePanel *panel;
    int popUpActions, checkActions;
}
@end
@implementation Accessory
- (instancetype) initWithPanel: (NSSavePanel *) aPanel saveTypes: (BOOL) saveTypes {
    self = [super init];
    panel = aPanel;
    view = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 320, 70)];
    NSTextField *label = [[[NSTextField alloc] initWithFrame: NSMakeRect(8, 40, 100, 20)] autorelease];
    [label setStringValue: saveTypes ? @"File Format:" : @"Plain Text Encoding:"];
    [label setEditable: NO];
    [label setBezeled: NO];
    [label setDrawsBackground: NO];
    [view addSubview: label];
    popUp = [[NSPopUpButton alloc] initWithFrame: NSMakeRect(112, 38, 190, 24) pullsDown: NO];
    [popUp addItemsWithTitles: saveTypes ? @[ @"Plain text", @"Rich text" ]
                                         : @[ @"Automatic", @"Unicode (UTF-8)", @"Western (ISO Latin 1)" ]];
    [popUp setTarget: self];
    [popUp setAction: @selector(popUpChanged:)];
    [view addSubview: popUp];
    check = [[NSButton alloc] initWithFrame: NSMakeRect(112, 8, 200, 20)];
    [check setButtonType: NSSwitchButton];
    [check setTitle: @"Ignore rich text commands"];
    [check setTarget: self];
    [check setAction: @selector(checkChanged:)];
    [view addSubview: check];
    return self;
}
- (void) popUpChanged: (id) sender {
    popUpActions++;
    [panel setAllowedFileTypes: [popUp indexOfSelectedItem] == 1 ? @[ @"rtf" ] : @[ @"txt" ]];
}
- (void) checkChanged: (id) sender {
    checkActions++;
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
        Accessory *accessory = nil;
        if (!strcmp(mode, "save") || !strcmp(mode, "choices-save")) {
            panel = [NSSavePanel savePanel];
            [panel setNameFieldStringValue: @"Report"];
            [panel setAllowedFileTypes: @[ @"txt" ]];
            [panel setPrompt: @"Export"];
            if (!strcmp(mode, "choices-save")) {
                [panel setAllowedFileTypes: nil];
                accessory = [[Accessory alloc] initWithPanel: panel saveTypes: YES];
                [panel setAccessoryView: accessory->view];
            }
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
            if (!strcmp(mode, "accessory-text")) {
                NSView *view = [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 200, 30)] autorelease];
                [view addSubview: [[[NSTextField alloc] initWithFrame: NSMakeRect(5, 5, 150, 20)] autorelease]];
                [panel setAccessoryView: view];
            }
            if (!strcmp(mode, "choices")) {
                accessory = [[Accessory alloc] initWithPanel: panel saveTypes: NO];
                [panel setAccessoryView: accessory->view];
            }
            if (!strcmp(mode, "delegate"))
                [panel setDelegate: [[FilteringDelegate new] autorelease]];
        }

        BOOL builtIn = !strcmp(mode, "accessory") || !strcmp(mode, "accessory-text") || !strcmp(mode, "delegate") || !strcmp(mode, "plain");
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
        if (accessory != nil)
            printf("CONTROLS popup=%ld check=%ld popupActions=%d checkActions=%d\n",
                   (long) [accessory->popUp indexOfSelectedItem], (long) [accessory->check state],
                   accessory->popUpActions, accessory->checkActions);
        printf("DONE\n");
        CFPreferencesSetAppValue(key, NULL, domain);
        CFPreferencesSetAppValue(key, NULL, kCFPreferencesCurrentApplication);
    }
    return 0;
}
