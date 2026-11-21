/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Contract: the identifier of an NSMenu is archived under the key
// NSMenuIdentifier, comes back from an unarchive, and is kept by a copy; a menu
// without an identifier archives no such key. (Black box on macOS 10.14.4 and
// 26.7.3.) Applications that fill a menu from its identifier in
// -menuNeedsUpdate: depend on it surviving a nib load.
// Prints PASS or FAIL.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c, ...) do { if (!(c)) { failures++; printf("FAIL line %d: %s\n", __LINE__, [[NSString stringWithFormat: __VA_ARGS__] UTF8String]); } } while (0)

static BOOL archiveHasMenuIdentifierKey(NSData *data) {
    CFPropertyListRef plist = CFPropertyListCreateWithData(NULL, (CFDataRef) data, kCFPropertyListImmutable, NULL, NULL);
    BOOL found = NO;
    for (id object in [(NSDictionary *) plist objectForKey: @"$objects"])
        if ([object isKindOfClass: [NSDictionary class]] && [object objectForKey: @"NSTitle"] != nil &&
            [object objectForKey: @"NSMenuItems"] != nil && [object objectForKey: @"NSMenuIdentifier"] != nil)
            found = YES;
    CFRelease(plist);
    return found;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];

        NSMenu *menu = [[NSMenu alloc] initWithTitle: @"File"];
        [menu addItemWithTitle: @"One" action: NULL keyEquivalent: @""];
        CHECK([menu identifier] == nil, @"default identifier is %@", [menu identifier]);

        NSData *plain = [NSKeyedArchiver archivedDataWithRootObject: menu];
        CHECK(!archiveHasMenuIdentifierKey(plain), @"a menu without an identifier archived NSMenuIdentifier");
        NSMenu *plainBack = [NSKeyedUnarchiver unarchiveObjectWithData: plain];
        CHECK([plainBack identifier] == nil, @"identifier after unarchiving a menu without one: %@", [plainBack identifier]);

        [menu setIdentifier: @"{8F487F1F-419F-47A8-8ECF-EC44AF4449A3}"];
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject: menu];
        CHECK(archiveHasMenuIdentifierKey(data), @"the archive has no NSMenuIdentifier");
        NSMenu *back = [NSKeyedUnarchiver unarchiveObjectWithData: data];
        CHECK([[back identifier] isEqual: @"{8F487F1F-419F-47A8-8ECF-EC44AF4449A3}"], @"identifier after the round trip: %@", [back identifier]);
        CHECK([back numberOfItems] == 1 && [[back title] isEqual: @"File"], @"the rest of the menu changed");

        NSMenu *copy = [menu copy];
        CHECK([[copy identifier] isEqual: [menu identifier]], @"identifier of the copy: %@", [copy identifier]);

        // A submenu keeps its own identifier inside a menu archive.
        NSMenu *main = [[NSMenu alloc] initWithTitle: @"Main"];
        NSMenuItem *item = [main addItemWithTitle: @"File" action: NULL keyEquivalent: @""];
        [item setSubmenu: menu];
        NSMenu *mainBack = [NSKeyedUnarchiver unarchiveObjectWithData: [NSKeyedArchiver archivedDataWithRootObject: main]];
        CHECK([[[[mainBack itemAtIndex: 0] submenu] identifier] isEqual: @"{8F487F1F-419F-47A8-8ECF-EC44AF4449A3}"],
              @"submenu identifier after the round trip: %@", [[[mainBack itemAtIndex: 0] submenu] identifier]);
    }
    printf(failures ? "FAIL (%d)\n" : "PASS\n", failures);
    return failures != 0;
}
