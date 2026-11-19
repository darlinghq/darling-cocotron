/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/

#import "WaylandAppMenu.h"
#import "../private-include/AppKit/NSDBusMenu.h"
#import <AppKit/NSMenu.h>

@implementation WaylandAppMenu

static NSString *applicationName(void) {
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *name = [bundle objectForInfoDictionaryKey: @"CFBundleDisplayName"];

    if ([name length] == 0)
        name = [bundle objectForInfoDictionaryKey: @"CFBundleName"];
    if ([name length] == 0)
        name = [[NSProcessInfo processInfo] processName];
    return name;
}

- (instancetype) init {
    if ((self = [super init]) == nil)
        return nil;

    _exporter = [[NSDBusMenu alloc] initWithSessionBus];
    [_exporter setApplicationName: applicationName()];

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    NSString *names[] = {NSMenuDidAddItemNotification, NSMenuDidRemoveItemNotification,
                         NSMenuDidChangeItemNotification};

    for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); i++)
        [center addObserver: self
                   selector: @selector(menuStructureChanged:)
                       name: names[i]
                     object: nil];
    return self;
}

- (void) dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    [_exporter invalidate];
    [_exporter release];
    [_menu release];
    [super dealloc];
}

- (BOOL) globalMenuPresent {
    return _exporter != nil && [_exporter registrarPresent];
}

- (void) setMainMenu: (NSMenu *) menu {
    if (menu == _menu)
        return;
    [_menu release];
    _menu = [menu retain];
    [_exporter setMenu: _menu];
}

- (NSString *) serviceName {
    return _menu != nil ? [_exporter busName] : nil;
}

- (NSString *) objectPath {
    return _menu != nil ? [_exporter objectPath] : nil;
}

// Whether a menu was changed that belongs to the main menu.
- (void) menuStructureChanged: (NSNotification *) notification {
    if (_menu == nil)
        return;

    NSMenu *menu = [notification object];

    while ([menu supermenu] != nil && menu != _menu)
        menu = [menu supermenu];
    if (menu == _menu)
        [_exporter menuChanged];
}

@end
