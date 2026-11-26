// Copyright (C) 2026 Lubos Dolezel
//
// Setting NSMenu's itemArray
// (https://developer.apple.com/documentation/appkit/nsmenu/itemarray) replaces
// the menu's items with a copy of the array; the items left out lose their
// menu, and an item that is in another menu raises. Expected values were
// observed on macOS 26.7.3 (x86_64) with the same inputs.
#import <AppKit/AppKit.h>

static int failures;

static void report(const char *name, BOOL ok)
{
    printf("%s: %s\n", ok ? "PASS" : "FAIL", name);
    if (!ok)
        failures++;
}

int main(void)
{
    @autoreleasepool {
        NSMenu *menu = [[[NSMenu alloc] initWithTitle: @"menu"] autorelease];
        NSMenuItem *a = [menu addItemWithTitle: @"a" action: NULL keyEquivalent: @""];
        NSMenuItem *b = [[[NSMenuItem alloc] initWithTitle: @"b" action: NULL keyEquivalent: @""] autorelease];
        NSMenuItem *c = [[[NSMenuItem alloc] initWithTitle: @"c" action: NULL keyEquivalent: @""] autorelease];

        NSMutableArray *items = [NSMutableArray arrayWithObjects: b, a, nil];
        menu.itemArray = items;
        [items addObject: c];
        report("set: the items in order, copied", menu.numberOfItems == 2 && [menu itemAtIndex: 0] == b
               && [menu itemAtIndex: 1] == a && c.menu == nil);
        report("set: the items' menu", a.menu == menu && b.menu == menu);

        menu.itemArray = @[ c ];
        report("replaced: the others lose their menu", a.menu == nil && b.menu == nil && c.menu == menu
               && menu.numberOfItems == 1);

        NSMenu *other = [[[NSMenu alloc] initWithTitle: @"other"] autorelease];
        NSString *raised = nil;
        @try {
            other.itemArray = @[ c ];
        } @catch (NSException *exception) {
            raised = exception.name;
        }
        report("an item of another menu raises", [raised isEqualToString: NSInternalInconsistencyException]
               && c.menu == menu && other.numberOfItems == 0);

        menu.itemArray = @[];
        report("empty", menu.numberOfItems == 0 && c.menu == nil);
    }
    return failures != 0;
}
