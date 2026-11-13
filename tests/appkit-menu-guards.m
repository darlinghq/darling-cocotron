/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Noting a recent document works while the application has no main menu, or a
// main menu without a recent-documents submenu (the documents are recorded,
// nothing is touched in the menu); and a main menu item whose submenu has an
// empty title is shown under the item's own title. The second part uses a
// private Cocotron method and is skipped where it does not exist.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(cond, what) do { if (!(cond)) { printf("FAIL: %s\n", what); failures++; } } while (0)

@interface NSMenuItem (Private)
- (NSString *) _mainMenuTitle;
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSDocumentController *controller = [NSDocumentController sharedDocumentController];
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                [NSString stringWithFormat: @"menu-guards-%d.txt", getpid()]];
        [@"x" writeToFile: path atomically: NO encoding: NSUTF8StringEncoding error: NULL];
        NSURL *url = [NSURL fileURLWithPath: path];

        [NSApp setMainMenu: nil];
        CHECK([NSApp mainMenu] == nil, "no main menu");
        [controller clearRecentDocuments: nil];
        [controller noteNewRecentDocumentURL: url];
        CHECK([[controller recentDocumentURLs] count] == 1, "recent document recorded without a main menu");

        NSMenu *menu = [[NSMenu alloc] initWithTitle: @"Main"];
        NSMenuItem *file = [menu addItemWithTitle: @"File" action: NULL keyEquivalent: @""];
        [file setSubmenu: [[NSMenu alloc] initWithTitle: @"File"]];
        [NSApp setMainMenu: menu];
        [controller noteNewRecentDocumentURL: url];
        CHECK([[controller recentDocumentURLs] count] == 1, "same document is not recorded twice");
        [controller clearRecentDocuments: nil];
        CHECK([[controller recentDocumentURLs] count] == 0, "recent documents cleared with no recent submenu");

        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle: @"Edit" action: NULL keyEquivalent: @""];
        [menu addItem: item];
        [item setSubmenu: [[NSMenu alloc] initWithTitle: @""]];
        if ([item respondsToSelector: @selector(_mainMenuTitle)]) {
            CHECK([[item _mainMenuTitle] isEqual: @"Edit"], "empty submenu title: the item title is used");
            [[item submenu] setTitle: @"Changed"];
            CHECK([[item _mainMenuTitle] isEqual: @"Changed"], "non-empty submenu title is used");
        }
        [[NSFileManager defaultManager] removeItemAtPath: path error: NULL];
    }
    printf(failures ? "FAIL\n" : "PASS\n");
    return failures != 0;
}
