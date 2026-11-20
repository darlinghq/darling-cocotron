/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// The Open Recent menu lists the recent documents of earlier runs once the
// application has finished launching, also when the shared document
// controller was made before the main menu was set (as a main nib may do).
// The Open Recent submenu is the one a nib names _NSRecentDocumentsMenu;
// this test names it that way itself, so it runs on Darling only.
// No display needed. No ARC.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

static int failures;

static void expect(BOOL ok, const char *label) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", label);
    failures += !ok;
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        char temp[] = "/tmp/darling-recent-menu-XXXXXX";
        if (!mkdtemp(temp))
            return 2;
        NSString *directory = [NSString stringWithUTF8String: temp];
        NSString *path = [directory stringByAppendingPathComponent: @"earlier.txt"];
        [@"text" writeToFile: path atomically: YES encoding: NSUTF8StringEncoding error: NULL];

        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        id saved = [[defaults objectForKey: @"NSRecentDocumentPaths"] retain];
        [defaults setObject: @[path] forKey: @"NSRecentDocumentPaths"];

        [NSApplication sharedApplication];
        // The controller exists before there is a main menu.
        [NSDocumentController sharedDocumentController];

        NSMenu *mainMenu = [[[NSMenu alloc] initWithTitle: @"Main"] autorelease];
        NSMenuItem *fileItem = [mainMenu addItemWithTitle: @"File" action: NULL keyEquivalent: @""];
        NSMenu *fileMenu = [[[NSMenu alloc] initWithTitle: @"File"] autorelease];
        [mainMenu setSubmenu: fileMenu forItem: fileItem];
        NSMenuItem *recentItem = [fileMenu addItemWithTitle: @"Open Recent" action: NULL keyEquivalent: @""];
        NSMenu *recentMenu = [[[NSMenu alloc] initWithTitle: @"Open Recent"] autorelease];
        [recentMenu addItemWithTitle: @"Clear Menu" action: @selector(clearRecentDocuments:) keyEquivalent: @""];
        [recentMenu performSelector: @selector(_setMenuName:) withObject: @"_NSRecentDocumentsMenu"];
        [fileMenu setSubmenu: recentMenu forItem: recentItem];
        [NSApp setMainMenu: mainMenu];

        expect([[recentMenu itemArray] count] == 1, "before launching, the menu has only its own items");
        [NSApp finishLaunching];
        NSArray *items = [recentMenu itemArray];
        expect([items count] == 3 && [[items[0] title] isEqualToString: @"earlier.txt"] && [items[1] isSeparatorItem] &&
                       [[items[2] title] isEqualToString: @"Clear Menu"],
               "after launching, the menu lists the earlier document above a separator and its own items");
        for (NSMenuItem *item in items)
            printf("  item: %s\n", [item isSeparatorItem] ? "(separator)" : [[item title] UTF8String]);

        if (saved)
            [defaults setObject: saved forKey: @"NSRecentDocumentPaths"];
        else
            [defaults removeObjectForKey: @"NSRecentDocumentPaths"];
        [saved release];
        [[NSFileManager defaultManager] removeItemAtPath: directory error: NULL];
    }
    printf("failures=%d\n", failures);
    return failures ? 1 : 0;
}
