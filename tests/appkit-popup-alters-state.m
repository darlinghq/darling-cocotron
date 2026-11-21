// Copyright (C) 2026 Lubos Dolezel
//
// -[NSPopUpButtonCell altersStateOfSelectedItem], as observed on macOS 26.7.3 (black-box): it is on
// for new cells; a pop-up menu then turns on the item it selects (the first one added, too) and
// turns off the one it selected before; turning it off clears every item's state and selecting
// leaves the states alone; turning it on again turns on the selected item only. A pull-down menu's
// items keep their states. In a keyed archive the setting is NSAltersState, written only when it
// is on; decoding leaves the archived item states as they are.
//
// Build: clang -framework AppKit appkit-popup-alters-state.m
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static NSString *states(NSPopUpButtonCell *cell) {
    NSMutableString *s = [NSMutableString string];
    for (NSMenuItem *item in [cell itemArray])
        [s appendFormat: @"%ld", (long) [item state]];
    return s;
}

// Archives with only the keys that matter here, standing in for ones macOS wrote.
@interface ItemArchive : NSObject <NSCoding> {
@public
    NSString *title;
    NSInteger state;
}
@end
@implementation ItemArchive
- (void) encodeWithCoder: (NSCoder *) coder {
    [coder encodeObject: title forKey: @"NSTitle"];
    [coder encodeObject: @"" forKey: @"NSKeyEquiv"];
    if (state != 0)
        [coder encodeInt: (int) state forKey: @"NSState"];
}
- (instancetype) initWithCoder: (NSCoder *) coder { return [super init]; }
@end

@interface MenuArchive : NSObject <NSCoding> {
@public
    NSArray *items;
}
@end
@implementation MenuArchive
- (void) encodeWithCoder: (NSCoder *) coder {
    [coder encodeObject: @"" forKey: @"NSTitle"];
    [coder encodeObject: items forKey: @"NSMenuItems"];
}
- (instancetype) initWithCoder: (NSCoder *) coder { return [super init]; }
@end

@interface PopUpArchive : NSObject <NSCoding> {
@public
    BOOL alters;
    MenuArchive *menu;
}
@end
@implementation PopUpArchive
- (void) encodeWithCoder: (NSCoder *) coder {
    [coder encodeObject: menu forKey: @"NSMenu"];
    [coder encodeInt: 1 forKey: @"NSSelectedIndex"];
    if (alters)
        [coder encodeBool: YES forKey: @"NSAltersState"];
}
- (instancetype) initWithCoder: (NSCoder *) coder { return [super init]; }
@end

// A pop-up cell with items a, b and c, item b selected and item c on.
static NSPopUpButtonCell *decoded(BOOL alters) {
    NSMutableArray *items = [NSMutableArray array];
    for (NSString *title in [NSArray arrayWithObjects: @"a", @"b", @"c", nil]) {
        ItemArchive *item = [ItemArchive new];
        item->title = title;
        item->state = [title isEqualToString: @"c"] ? NSControlStateValueOn : NSControlStateValueOff;
        [items addObject: item];
    }
    PopUpArchive *source = [PopUpArchive new];
    source->alters = alters;
    source->menu = [MenuArchive new];
    source->menu->items = items;
    NSMutableData *data = [NSMutableData data];
    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData: data];
    [archiver setClassName: @"NSPopUpButtonCell" forClass: [PopUpArchive class]];
    [archiver setClassName: @"NSMenu" forClass: [MenuArchive class]];
    [archiver setClassName: @"NSMenuItem" forClass: [ItemArchive class]];
    [archiver encodeObject: source forKey: @"root"];
    [archiver finishEncoding];
    return [[[NSKeyedUnarchiver alloc] initForReadingWithData: data] decodeObjectForKey: @"root"];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];

        NSPopUpButtonCell *cell = [[NSPopUpButtonCell alloc] initTextCell: @"" pullsDown: NO];
        CHECK([cell altersStateOfSelectedItem]);
        CHECK([[NSPopUpButtonCell new] altersStateOfSelectedItem]);
        CHECK([[[NSPopUpButtonCell alloc] initTextCell: @"" pullsDown: YES] altersStateOfSelectedItem]);

        [cell removeAllItems];
        [cell addItemsWithTitles: [NSArray arrayWithObjects: @"a", @"b", @"c", nil]];
        CHECK([cell indexOfSelectedItem] == 0 && [states(cell) isEqualToString: @"100"]);
        [cell selectItemAtIndex: 2];
        CHECK([states(cell) isEqualToString: @"001"]);

        [cell setAltersStateOfSelectedItem: NO];
        CHECK(![cell altersStateOfSelectedItem] && [states(cell) isEqualToString: @"000"]);
        [cell selectItemAtIndex: 1];
        CHECK([states(cell) isEqualToString: @"000"]);
        [[cell itemAtIndex: 2] setState: NSControlStateValueOn];
        [cell selectItemAtIndex: 0];
        CHECK([states(cell) isEqualToString: @"001"]);

        [cell setAltersStateOfSelectedItem: YES];
        CHECK([states(cell) isEqualToString: @"101"]);
        [cell selectItemAtIndex: 1];
        CHECK([states(cell) isEqualToString: @"011"]);

        NSPopUpButtonCell *pullDown = [[NSPopUpButtonCell alloc] initTextCell: @"" pullsDown: YES];
        [pullDown removeAllItems];
        [pullDown addItemsWithTitles: [NSArray arrayWithObjects: @"a", @"b", @"c", nil]];
        [pullDown selectItemAtIndex: 2];
        CHECK([states(pullDown) isEqualToString: @"000"]);

        // Archives: the key is written only when the setting is on, and missing means off.
        NSPopUpButtonCell *altering = decoded(YES);
        CHECK([altering altersStateOfSelectedItem] && [states(altering) isEqualToString: @"001"]);
        NSPopUpButtonCell *keeping = decoded(NO);
        CHECK(![keeping altersStateOfSelectedItem] && [states(keeping) isEqualToString: @"001"]);

    }
    if (failures)
        return 1;
    printf("PASS\n");
    return 0;
}
