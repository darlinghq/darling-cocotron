// Copyright (C) 2026 Lubos Dolezel
//
// Loads storyboards compiled by ibtool (tests/fixtures/storyboards/*.storyboard
// are the inputs; every nib inside the .storyboardc bundles is NIBArchive, so
// this needs the NIBArchive reader in NSNib).
//
// Checks: the initial controller is the designated entry point; a scene that
// holds more than one top-level controller gives its own controller (the one
// its sceneController outlet reaches), not the first window controller; an
// unknown identifier raises NSInvalidArgumentException.
//
// Usage: storyboard-ibtool-fixtures <directory holding Single.storyboardc and Multi.storyboardc>
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 2) { fprintf(stderr, "usage: %s DIR\n", argv[0]); return 2; }
        [NSApplication sharedApplication];
        NSBundle *bundle = [NSBundle bundleWithPath:[NSString stringWithUTF8String:argv[1]]];

        NSStoryboard *single = [NSStoryboard storyboardWithName:@"Single" bundle:bundle];
        CHECK(single != nil);
        id initial = [single instantiateInitialController];
        CHECK([initial isKindOfClass:[NSWindowController class]]);
        CHECK([initial storyboard] == single);
        id content = [single instantiateControllerWithIdentifier:@"Content"];
        CHECK([content isKindOfClass:[NSViewController class]]);
        CHECK([content storyboard] == single);

        NSStoryboard *multi = [NSStoryboard storyboardWithName:@"Multi" bundle:bundle];
        CHECK(multi != nil);
        // MainWindow: scene member is a window controller; an extra view controller is in the nib.
        id mainWindow = [multi instantiateControllerWithIdentifier:@"MainWindow"];
        CHECK([mainWindow isKindOfClass:[NSWindowController class]]);
        // Panel: scene member is a view controller; an extra window controller is in the nib.
        id panel = [multi instantiateControllerWithIdentifier:@"Panel"];
        CHECK([panel isKindOfClass:[NSViewController class]]);
        CHECK([[panel title] isEqualToString:@"Panel"]);

        BOOL raised = NO;
        @try { [multi instantiateControllerWithIdentifier:@"NoSuchScene"]; }
        @catch (NSException *e) { raised = [[e name] isEqualToString:NSInvalidArgumentException]; }
        CHECK(raised);

        if (!failures) puts("PASS");
    }
    return failures ? 1 : 0;
}
