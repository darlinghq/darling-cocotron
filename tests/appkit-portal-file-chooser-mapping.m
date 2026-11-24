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
NSArray *DarlingPortalChoicesForAccessoryView(NSView *view);

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

        // An accessory view of pop-up buttons and check boxes goes to the portal as choices.
        {
            NSView *view = [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 320, 100)] autorelease];
            NSTextField *label = [[[NSTextField alloc] initWithFrame: NSMakeRect(5, 68, 100, 20)] autorelease];
            [label setStringValue: @"Encoding:"];
            [label setEditable: NO];
            [view addSubview: label];
            NSPopUpButton *popUp = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect(110, 66, 200, 24) pullsDown: NO] autorelease];
            [popUp addItemsWithTitles: @[ @"Automatic", @"UTF-8", @"Latin 1" ]];
            [[popUp menu] insertItem: [NSMenuItem separatorItem] atIndex: 1];
            [popUp selectItemAtIndex: 3];
            [view addSubview: popUp];
            NSButton *check = [[[NSButton alloc] initWithFrame: NSMakeRect(110, 30, 200, 20)] autorelease];
            [check setButtonType: NSSwitchButton];
            [check setTitle: @"Ignore rich text commands"];
            [check setState: NSOnState];
            [view addSubview: check];

            NSArray *choices = DarlingPortalChoicesForAccessoryView(view);
            CHECK([choices count] == 2);
            // top to bottom: the pop-up (its label is the static text on its left, without the colon), then the box
            CHECK([choices[0][@"label"] isEqual: @"Encoding"]);
            CHECK([choices[0][@"id"] isEqual: @"c0"] && [choices[0][@"control"] == popUp ? @YES : @NO isEqual: @YES]);
            // the separator is not an option; an option's id is the item's index
            CHECK([choices[0][@"options"] isEqual: (@[ @[ @"0", @"Automatic" ], @[ @"2", @"UTF-8" ], @[ @"3", @"Latin 1" ] ])]);
            CHECK([choices[0][@"initial"] isEqual: @"3"]);
            CHECK([choices[1][@"label"] isEqual: @"Ignore rich text commands"]);
            CHECK([choices[1][@"options"] isEqual: @[]] && [choices[1][@"initial"] isEqual: @"true"]);
            CHECK(choices[1][@"control"] == check);
            [check setState: NSOffState];
            CHECK([DarlingPortalChoicesForAccessoryView(view)[1][@"initial"] isEqual: @"false"]);

            NSSavePanel *save = [NSSavePanel savePanel];
            [save setAccessoryView: view];
            CHECK(DarlingPortalUnsupportedFeature(save) == nil);
            NSArray *wire = DarlingPortalRequestForPanel(save)[@"options"][@"choices"];
            CHECK([wire count] == 2 && [wire[0][0] isEqual: @"c0"] && [wire[0][1] isEqual: @"Encoding"] &&
                  [wire[0][3] isEqual: @"3"] && [wire[1][2] isEqual: @[]] && [wire[1][3] isEqual: @"false"]);

            // a label above the pop-up, in a box inside a plain view, and hidden unsupported views
            NSView *outer = [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 200, 100)] autorelease];
            NSBox *box = [[[NSBox alloc] initWithFrame: NSMakeRect(0, 0, 200, 100)] autorelease];
            [outer addSubview: box];
            NSTextField *above = [[[NSTextField alloc] initWithFrame: NSMakeRect(10, 60, 100, 20)] autorelease];
            [above setStringValue: @"Format"];
            [above setEditable: NO];
            [[box contentView] addSubview: above];
            NSPopUpButton *below = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect(10, 30, 150, 24) pullsDown: NO] autorelease];
            [below addItemsWithTitles: @[ @"One", @"Two" ]];
            [[box contentView] addSubview: below];
            NSSlider *hidden = [[[NSSlider alloc] initWithFrame: NSMakeRect(10, 0, 100, 20)] autorelease];
            [hidden setHidden: YES];
            [outer addSubview: hidden];
            choices = DarlingPortalChoicesForAccessoryView(outer);
            CHECK([choices count] == 1 && [choices[0][@"label"] isEqual: @"Format"]);

            // a pop-up without a label is named by its selected item
            NSView *bare = [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 200, 40)] autorelease];
            NSPopUpButton *plain = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect(10, 10, 150, 24) pullsDown: NO] autorelease];
            [plain addItemsWithTitles: @[ @"One", @"Two" ]];
            [bare addSubview: plain];
            CHECK([DarlingPortalChoicesForAccessoryView(bare)[0][@"label"] isEqual: @"One"]);

            // what the portal cannot show: a view with no control, a text field, a pull-down, a radio button, a push
            // button, an image view, a disabled control, a check box in the mixed state, a nil view
            CHECK(DarlingPortalChoicesForAccessoryView(nil) == nil);
            CHECK(DarlingPortalChoicesForAccessoryView([[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)] autorelease]) == nil);
            Class unsupported[] = { [NSTextField class], [NSImageView class], [NSSlider class] };
            for (size_t i = 0; i < sizeof unsupported / sizeof *unsupported; i++) {
                NSView *copy = [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 320, 100)] autorelease];
                [copy addSubview: [[[NSPopUpButton alloc] initWithFrame: NSMakeRect(10, 60, 100, 24) pullsDown: NO] autorelease]];
                [(NSPopUpButton *) [[copy subviews] firstObject] addItemWithTitle: @"x"];
                [copy addSubview: [[[unsupported[i] alloc] initWithFrame: NSMakeRect(10, 10, 100, 20)] autorelease]];
                CHECK(DarlingPortalChoicesForAccessoryView(copy) == nil);
            }
            NSView *other = [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 320, 100)] autorelease];
            NSPopUpButton *pull = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect(10, 60, 100, 24) pullsDown: YES] autorelease];
            [pull addItemsWithTitles: @[ @"Menu", @"One" ]];
            [other addSubview: pull];
            CHECK(DarlingPortalChoicesForAccessoryView(other) == nil);
            [pull removeFromSuperview];
            NSButton *radio = [[[NSButton alloc] initWithFrame: NSMakeRect(10, 10, 100, 20)] autorelease];
            [radio setButtonType: NSRadioButton];
            [radio setTitle: @"Radio"];
            [other addSubview: radio];
            CHECK(DarlingPortalChoicesForAccessoryView(other) == nil);
            [radio removeFromSuperview];
            NSButton *push = [[[NSButton alloc] initWithFrame: NSMakeRect(10, 10, 100, 20)] autorelease];
            [push setTitle: @"Push"];
            [other addSubview: push];
            CHECK(DarlingPortalChoicesForAccessoryView(other) == nil);
            [push removeFromSuperview];
            NSButton *mixed = [[[NSButton alloc] initWithFrame: NSMakeRect(10, 10, 100, 20)] autorelease];
            [mixed setButtonType: NSSwitchButton];
            [mixed setTitle: @"Mixed"];
            [mixed setAllowsMixedState: YES];
            [mixed setState: NSMixedState];
            [other addSubview: mixed];
            CHECK(DarlingPortalChoicesForAccessoryView(other) == nil);
            [mixed setState: NSOffState];
            CHECK([DarlingPortalChoicesForAccessoryView(other) count] == 1);
            [mixed setEnabled: NO];
            CHECK(DarlingPortalChoicesForAccessoryView(other) == nil);
        }

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
