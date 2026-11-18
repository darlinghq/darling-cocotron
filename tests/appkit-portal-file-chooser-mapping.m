// Copyright (C) 2026 Lubos Dolezel
//
// Licensed under the MIT license, the same as the rest of this project.
//
// How an NSOpenPanel or NSSavePanel is described to the desktop's file chooser portal (the options of the
// FileChooser OpenFile and SaveFile calls of the xdg-desktop-portal documentation), which panels the portal
// cannot show, and how the portal's response is read. Needs no portal and no session bus, only the window server
// the panels' nib needs. Darling only.
#import <AppKit/AppKit.h>
#include <stdio.h>

NSString *DarlingPortalUnsupportedFeature(NSSavePanel *panel);
NSDictionary *DarlingPortalRequestForPanel(NSSavePanel *panel);
NSArray *DarlingPortalPathsFromURIs(NSArray *uris);
NSInteger DarlingPortalModalResponseForCode(uint32_t code);
NSString *DarlingPortalHostPathForGuestPath(NSString *path);

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

@interface OnlyNotifications : NSObject <NSOpenSavePanelDelegate>
@end
@implementation OnlyNotifications
- (void) panel: (id) sender didChangeToDirectoryURL: (NSURL *) url {
}
@end

@interface Filtering : NSObject <NSOpenSavePanelDelegate>
@end
@implementation Filtering
- (BOOL) panel: (id) sender shouldEnableURL: (NSURL *) url {
    return YES;
}
@end

@interface Validating : NSObject <NSOpenSavePanelDelegate>
@end
@implementation Validating
- (BOOL) panel: (id) sender validateURL: (NSURL *) url error: (NSError **) error {
    return YES;
}
@end

static NSArray *patterns(NSArray *filter) {
    NSMutableArray *result = [NSMutableArray array];
    for (NSArray *pattern in filter[1])
        [result addObject: [NSString stringWithFormat: @"%@:%@", pattern[0], pattern[1]]];
    return result;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];

        // Open panel defaults.
        NSOpenPanel *open = [NSOpenPanel openPanel];
        CHECK(DarlingPortalUnsupportedFeature(open) == nil);
        NSDictionary *request = DarlingPortalRequestForPanel(open);
        CHECK([request[@"method"] isEqual: @"OpenFile"]);
        NSDictionary *options = request[@"options"];
        CHECK([options[@"multiple"] isEqual: @NO]);
        CHECK([options[@"directory"] isEqual: @NO]);
        CHECK([options[@"modal"] isEqual: @YES]);
        CHECK(options[@"filters"] == nil && options[@"current_filter"] == nil);
        CHECK(options[@"current_name"] == nil);
        CHECK([request[@"title"] length] > 0);

        // Options.
        open = [NSOpenPanel openPanel];
        [open setAllowsMultipleSelection: YES];
        [open setPrompt: @"Pick"];
        [open setMessage: @"Choose pictures"];
        [open setAllowedFileTypes: @[ @"png", @".Jpg" ]];
        [open setDirectoryURL: [NSURL fileURLWithPath: @"/Volumes/SystemRoot/tmp/a b"]];
        CHECK(DarlingPortalUnsupportedFeature(open) == nil);
        request = DarlingPortalRequestForPanel(open);
        options = request[@"options"];
        CHECK([options[@"multiple"] isEqual: @YES]);
        CHECK([options[@"accept_label"] isEqual: @"Pick"]);
        CHECK([request[@"title"] isEqual: @"Choose pictures"]);
        NSArray *filters = options[@"filters"];
        CHECK([filters count] == 1);
        CHECK([options[@"current_filter"] isEqual: filters[0]]);
        NSArray *p = patterns(filters[0]);
        CHECK([p isEqual: (@[ @"0:*.[pP][nN][gG]", @"0:*.[jJ][pP][gG]" ])]);
        NSData *folder = options[@"current_folder"];
        CHECK([folder isEqual: [NSData dataWithBytes: "/tmp/a b" length: 9]]);

        // A folder panel asks the portal for folders only.
        open = [NSOpenPanel openPanel];
        [open setCanChooseFiles: NO];
        [open setCanChooseDirectories: YES];
        CHECK(DarlingPortalUnsupportedFeature(open) == nil);
        CHECK([DarlingPortalRequestForPanel(open)[@"options"][@"directory"] isEqual: @YES]);

        // A guest-only folder cannot be named to the portal.
        [open setDirectoryURL: [NSURL fileURLWithPath: @"/Users/someone"]];
        CHECK(DarlingPortalRequestForPanel(open)[@"options"][@"current_folder"] == nil);
        CHECK(DarlingPortalHostPathForGuestPath(@"/Users/someone") == nil);
        CHECK([DarlingPortalHostPathForGuestPath(@"/Volumes/SystemRoot/home/x/") isEqual: @"/home/x"]);
        CHECK(DarlingPortalHostPathForGuestPath(@"/Volumes/SystemRoot/a/../b") == nil);
        CHECK(DarlingPortalHostPathForGuestPath(@"/Volumes/SystemRoot") == nil);

        // Save panel.
        NSSavePanel *save = [NSSavePanel savePanel];
        [save setNameFieldStringValue: @"Untitled.txt"];
        [save setAllowedFileTypes: @[ @"txt" ]];
        [save setAllowsOtherFileTypes: YES];
        CHECK(DarlingPortalUnsupportedFeature(save) == nil);
        request = DarlingPortalRequestForPanel(save);
        options = request[@"options"];
        CHECK([request[@"method"] isEqual: @"SaveFile"]);
        CHECK([options[@"current_name"] isEqual: @"Untitled.txt"]);
        CHECK(options[@"multiple"] == nil && options[@"directory"] == nil);
        filters = options[@"filters"];
        CHECK([filters count] == 2);
        CHECK([patterns(filters[1]) isEqual: (@[ @"0:*" ])]);
        CHECK([options[@"current_filter"] isEqual: filters[0]]);
        save = [NSSavePanel savePanel];
        CHECK(DarlingPortalRequestForPanel(save)[@"options"][@"filters"] == nil);

        // What the portal cannot show.
        open = [NSOpenPanel openPanel];
        [open setAccessoryView: [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)] autorelease]];
        CHECK([DarlingPortalUnsupportedFeature(open) length] > 0);
        open = [NSOpenPanel openPanel];
        [open setDelegate: [[OnlyNotifications new] autorelease]];
        CHECK(DarlingPortalUnsupportedFeature(open) == nil);
        [open setDelegate: [[Filtering new] autorelease]];
        CHECK([DarlingPortalUnsupportedFeature(open) length] > 0);
        [open setDelegate: [[Validating new] autorelease]];
        CHECK([DarlingPortalUnsupportedFeature(open) length] > 0);
        open = [NSOpenPanel openPanel];
        [open setCanChooseDirectories: YES];
        CHECK([DarlingPortalUnsupportedFeature(open) length] > 0);
        open = [NSOpenPanel openPanel];
        [open setCanChooseFiles: NO];
        CHECK([DarlingPortalUnsupportedFeature(open) length] > 0);
        open = [NSOpenPanel openPanel];
        [open setShowsHiddenFiles: YES];
        CHECK([DarlingPortalUnsupportedFeature(open) length] > 0);
        open = [NSOpenPanel openPanel];
        [open setTreatsFilePackagesAsDirectories: YES];
        CHECK([DarlingPortalUnsupportedFeature(open) length] > 0);
        save = [NSSavePanel savePanel];
        [save setAccessoryView: [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)] autorelease]];
        CHECK([DarlingPortalUnsupportedFeature(save) length] > 0);

        // Response URIs.
        NSArray *paths = DarlingPortalPathsFromURIs(@[ @"file:///tmp/a%20b.txt", @"file:///home/x/%E6%97%A5" ]);
        CHECK([paths isEqual: (@[ @"/Volumes/SystemRoot/tmp/a b.txt", @"/Volumes/SystemRoot/home/x/日" ])]);
        CHECK(DarlingPortalPathsFromURIs(@[]) == nil);
        CHECK(DarlingPortalPathsFromURIs(nil) == nil);
        CHECK(DarlingPortalPathsFromURIs(@[ @"http://example.com/a" ]) == nil);
        CHECK(DarlingPortalPathsFromURIs(@[ @"file:///tmp/ok", @"file:///tmp/../etc/passwd" ]) == nil);
        CHECK(DarlingPortalPathsFromURIs(@[ @"file:///tmp/a%00b" ]) == nil);
        CHECK(DarlingPortalPathsFromURIs(@[ @"file:///tmp/ok", @(1) ]) == nil);
        // Each entry is one URI: a line break or a comment marker is refused.
        CHECK(DarlingPortalPathsFromURIs(@[ @"file:///tmp/a\r\nfile:///tmp/b", @"#c" ]) == nil);
        CHECK(DarlingPortalPathsFromURIs(@[ @"file:///tmp/a\nfile:///tmp/b" ]) == nil);
        CHECK(DarlingPortalPathsFromURIs(@[ @"#file:///tmp/a" ]) == nil);
        CHECK(DarlingPortalPathsFromURIs(@[ @"file://otherhost/tmp/a" ]) == nil);
        CHECK([DarlingPortalPathsFromURIs(@[ @"file://localhost/tmp/a" ]) isEqual: @[ @"/Volumes/SystemRoot/tmp/a" ]]);
        CHECK(DarlingPortalPathsFromURIs(@[ @"file:///tmp/a%2Fb" ]) == nil);

        // Response codes: 0 success, 1 cancelled, 2 ended otherwise.
        CHECK(DarlingPortalModalResponseForCode(0) == NSModalResponseOK);
        CHECK(DarlingPortalModalResponseForCode(1) == NSModalResponseCancel);
        CHECK(DarlingPortalModalResponseForCode(2) == NSModalResponseCancel);
        CHECK(DarlingPortalModalResponseForCode(77) == NSModalResponseCancel);
    }
    printf(failures ? "FAIL\n" : "PASS\n");
    return failures ? 1 : 0;
}
