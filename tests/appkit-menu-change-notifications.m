/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// NSMenu announces added, removed and changed items, and -performActionForItemAtIndex:
// sends the action of an enabled item without updating the menu. The behaviour of
// -performActionForItemAtIndex: was observed on macOS 26.7.3: with automatic
// enabling and a target that answers NO to validation, an item that is still
// enabled performs its action, with no menuNeedsUpdate: and with the will-send and
// did-send notifications; a disabled item does nothing at all.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(BOOL ok, NSString *what) {
    if (!ok) {
        failures++;
        printf("FAIL: %s\n", [what UTF8String]);
    }
}

@interface Probe : NSObject <NSMenuDelegate>
{
@public
    int fired, updates, willSend, didSend, added, removed, changed;
    NSInteger lastIndex;
    NSMenuItem *sentItem;
}
@end

@implementation Probe
- (void) act: (id) sender {
    fired++;
}
- (BOOL) validateMenuItem: (NSMenuItem *) item {
    return NO;
}
- (void) menuNeedsUpdate: (NSMenu *) menu {
    updates++;
}
- (void) note: (NSNotification *) n {
    NSString *name = [n name];
    NSNumber *index = [[n userInfo] objectForKey: @"NSMenuItemIndex"];

    if ([name isEqualToString: NSMenuWillSendActionNotification]) {
        willSend++;
        sentItem = [[n userInfo] objectForKey: @"MenuItem"];
    } else if ([name isEqualToString: NSMenuDidSendActionNotification])
        didSend++;
    else if ([name isEqualToString: NSMenuDidAddItemNotification]) {
        added++;
        lastIndex = [index integerValue];
    } else if ([name isEqualToString: NSMenuDidRemoveItemNotification]) {
        removed++;
        lastIndex = [index integerValue];
    } else if ([name isEqualToString: NSMenuDidChangeItemNotification]) {
        changed++;
        lastIndex = [index integerValue];
    }
}
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        Probe *probe = [Probe new];
        NSMenu *menu = [[NSMenu alloc] initWithTitle: @"M"];
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

        [menu setDelegate: probe];
        for (NSString *name in @[
                 NSMenuWillSendActionNotification, NSMenuDidSendActionNotification,
                 NSMenuDidAddItemNotification, NSMenuDidRemoveItemNotification,
                 NSMenuDidChangeItemNotification
             ])
            [center addObserver: probe selector: @selector(note:) name: name object: menu];

        NSMenuItem *a = [menu addItemWithTitle: @"A" action: @selector(act:) keyEquivalent: @""];
        [a setTarget: probe];
        expect(probe->added == 1 && probe->lastIndex == 0, @"adding an item posts DidAdd with its index");
        NSMenuItem *b = [[NSMenuItem alloc] initWithTitle: @"B" action: NULL keyEquivalent: @""];
        [menu insertItem: b atIndex: 0];
        expect(probe->added == 2 && probe->lastIndex == 0, @"inserting an item posts DidAdd with its index");

        probe->changed = 0;
        [a setTitle: @"A2"];
        expect(probe->changed == 1 && probe->lastIndex == 1, @"changing the title posts DidChange with the index");
        [a setState: NSControlStateValueOn];
        [a setHidden: YES];
        [a setEnabled: YES];
        [a setKeyEquivalent: @"x"];
        [a setSubmenu: nil];
        expect(probe->changed == 6, @"state, hidden, enabled, key equivalent and submenu changes are announced");
        [a setHidden: NO];

        [menu removeItem: b];
        expect(probe->removed == 1 && probe->lastIndex == 0, @"removing an item posts DidRemove with its index");

        // The item is enabled, though validation would say no: the action is sent
        // and the menu is not updated first.
        probe->updates = 0;
        [menu performActionForItemAtIndex: 0];
        expect(probe->fired == 1, @"performActionForItemAtIndex: sends the action of an enabled item");
        expect(probe->updates == 0, @"performActionForItemAtIndex: does not update the menu");
        expect(probe->willSend == 1 && probe->didSend == 1 && probe->sentItem == a,
               @"will-send and did-send notifications, with the item");

        [menu setAutoenablesItems: NO];
        [a setEnabled: NO];
        [menu performActionForItemAtIndex: 0];
        expect(probe->fired == 1 && probe->willSend == 1, @"a disabled item does nothing");
        [a setEnabled: YES];
        [menu performActionForItemAtIndex: 0];
        expect(probe->fired == 2, @"an enabled item without automatic enabling performs its action");

        if (failures == 0)
            printf("OK\n");
    }
    return failures ? 1 : 0;
}
