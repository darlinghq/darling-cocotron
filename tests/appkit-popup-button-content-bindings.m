// Copyright (C) 2026 Lubos Dolezel
//
// NSPopUpButton content, contentObjects, contentValues and selectedObject bindings. The contract
// is the NSPopUpButton section of the Cocoa Bindings Reference
// (https://developer.apple.com/library/archive/documentation/Cocoa/Reference/CocoaBindingsRef/BindingsText/NSPopUpButton.html):
//  - content: the objects of the pop-up button's items; unless contentValues is bound, the item
//    titles are the descriptions of the content objects;
//  - contentValues: the strings shown as the items;
//  - contentObjects: objects returned by selectedObject in place of the matching content objects
//    (available only when content is bound);
//  - selectedObject: the object in the content that matches the selected item.
// The order in which the bindings are made must not matter. Beyond the reference are the
// assumptions marked GUESS in the implementation: that an item keeps its object as its
// -representedObject, that every content object gets its own item even when two descriptions are
// equal (test_equal_descriptions_keep_every_item), and that a bound selection survives a content
// change (test_bound_selection_survives_a_content_change). Written from the documentation; not yet run in a guest.
// Build: clang -framework AppKit appkit-popup-button-content-bindings.m (no ARC)
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

@interface Thing : NSObject {
    NSString *_name;
}
- (instancetype) initWithName: (NSString *) name;
@end
@implementation Thing
- (instancetype) initWithName: (NSString *) name {
    if ((self = [super init]))
        _name = [name copy];
    return self;
}
- (void) dealloc {
    [_name release];
    [super dealloc];
}
- (NSString *) description {
    return _name;
}
@end

@interface Model : NSObject {
    NSArray *_things;
    NSArray *_titles;
    NSArray *_stand;
    id _selected;
}
@property(retain) NSArray *things;
@property(retain) NSArray *titles;
@property(retain) NSArray *stand;
@property(retain) id selected;
@end
@implementation Model
@synthesize things = _things, titles = _titles, stand = _stand, selected = _selected;
@end

static NSPopUpButton *makeButton(void) {
    return [[[NSPopUpButton alloc] initWithFrame: NSMakeRect(0, 0, 100, 22) pullsDown: NO] autorelease];
}

static void test_content_titles_and_objects(void) {
    Thing *a = [[[Thing alloc] initWithName: @"Alpha"] autorelease];
    Thing *b = [[[Thing alloc] initWithName: @"Beta"] autorelease];
    Model *model = [[Model new] autorelease];
    NSPopUpButton *button = makeButton();

    model.things = [NSArray arrayWithObjects: a, b, nil];
    [button bind: NSContentBinding toObject: model withKeyPath: @"things" options: nil];
    CHECK([button numberOfItems] == 2);
    CHECK([[button itemTitleAtIndex: 0] isEqualToString: @"Alpha"]);
    CHECK([[button itemTitleAtIndex: 1] isEqualToString: @"Beta"]);
    CHECK([[button itemAtIndex: 0] representedObject] == a);
    CHECK([[button itemAtIndex: 1] representedObject] == b);

    [button bind: NSSelectedObjectBinding toObject: model withKeyPath: @"selected" options: nil];
    [button selectItemAtIndex: 1];
    CHECK(model.selected == b);
}

static void test_equal_descriptions_keep_every_item(void) {
    Thing *a = [[[Thing alloc] initWithName: @"Same"] autorelease];
    Thing *b = [[[Thing alloc] initWithName: @"Same"] autorelease];
    Model *model = [[Model new] autorelease];
    NSPopUpButton *button = makeButton();

    model.things = [NSArray arrayWithObjects: a, b, nil];
    [button bind: NSContentBinding toObject: model withKeyPath: @"things" options: nil];
    CHECK([button numberOfItems] == 2);
    CHECK([[button itemAtIndex: 0] representedObject] == a);
    CHECK([[button itemAtIndex: 1] representedObject] == b);
}

static void test_content_values_give_the_titles(void) {
    Thing *a = [[[Thing alloc] initWithName: @"Alpha"] autorelease];
    Thing *b = [[[Thing alloc] initWithName: @"Beta"] autorelease];
    int order;

    for (order = 0; order < 2; order++) {
        Model *model = [[Model new] autorelease];
        NSPopUpButton *button = makeButton();

        model.things = [NSArray arrayWithObjects: a, b, nil];
        model.titles = [NSArray arrayWithObjects: @"First", @"Second", nil];
        if (order == 0) {
            [button bind: NSContentBinding toObject: model withKeyPath: @"things" options: nil];
            [button bind: NSContentValuesBinding toObject: model withKeyPath: @"titles" options: nil];
        } else {
            [button bind: NSContentValuesBinding toObject: model withKeyPath: @"titles" options: nil];
            [button bind: NSContentBinding toObject: model withKeyPath: @"things" options: nil];
        }
        CHECK([button numberOfItems] == 2);
        CHECK([[button itemTitleAtIndex: 0] isEqualToString: @"First"]);
        CHECK([[button itemTitleAtIndex: 1] isEqualToString: @"Second"]);
        CHECK([[button itemAtIndex: 1] representedObject] == b);
    }
}

static void test_content_objects_replace_the_selected_object(void) {
    Thing *a = [[[Thing alloc] initWithName: @"Alpha"] autorelease];
    Thing *b = [[[Thing alloc] initWithName: @"Beta"] autorelease];
    NSString *x = @"x-object", *y = @"y-object";
    int order;

    for (order = 0; order < 2; order++) {
        Model *model = [[Model new] autorelease];
        NSPopUpButton *button = makeButton();

        model.things = [NSArray arrayWithObjects: a, b, nil];
        model.stand = [NSArray arrayWithObjects: x, y, nil];
        if (order == 0) {
            [button bind: NSContentBinding toObject: model withKeyPath: @"things" options: nil];
            [button bind: NSContentObjectsBinding toObject: model withKeyPath: @"stand" options: nil];
        } else {
            [button bind: NSContentObjectsBinding toObject: model withKeyPath: @"stand" options: nil];
            [button bind: NSContentBinding toObject: model withKeyPath: @"things" options: nil];
        }
        [button bind: NSSelectedObjectBinding toObject: model withKeyPath: @"selected" options: nil];

        CHECK([button numberOfItems] == 2);
        CHECK([[button itemTitleAtIndex: 0] isEqualToString: @"Alpha"]);
        [button selectItemAtIndex: 1];
        CHECK(model.selected == y);
        [button selectItemAtIndex: 0];
        CHECK(model.selected == x);
    }
}

static void test_changing_the_content_rebuilds_the_items(void) {
    Thing *a = [[[Thing alloc] initWithName: @"Alpha"] autorelease];
    Thing *b = [[[Thing alloc] initWithName: @"Beta"] autorelease];
    Model *model = [[Model new] autorelease];
    NSPopUpButton *button = makeButton();

    model.things = [NSArray arrayWithObjects: a, b, nil];
    [button bind: NSContentBinding toObject: model withKeyPath: @"things" options: nil];
    model.things = [NSArray arrayWithObject: b];
    CHECK([button numberOfItems] == 1);
    CHECK([[button itemAtIndex: 0] representedObject] == b);
    model.things = nil;
    CHECK([button numberOfItems] == 0);
}

static void test_bound_selection_survives_a_content_change(void) {
    Thing *a = [[[Thing alloc] initWithName: @"Alpha"] autorelease];
    Thing *b = [[[Thing alloc] initWithName: @"Beta"] autorelease];
    Thing *c = [[[Thing alloc] initWithName: @"Gamma"] autorelease];
    Model *model = [[Model new] autorelease];
    NSPopUpButton *button = makeButton();

    model.things = [NSArray arrayWithObjects: a, b, nil];
    [button bind: NSContentBinding toObject: model withKeyPath: @"things" options: nil];
    [button bind: NSSelectedObjectBinding toObject: model withKeyPath: @"selected" options: nil];
    model.selected = b;
    CHECK([button indexOfSelectedItem] == 1);

    // The rebuilt items must not push the first item's object back into the model.
    model.things = [NSArray arrayWithObjects: a, b, c, nil];
    CHECK(model.selected == b);
    CHECK([button indexOfSelectedItem] == 1);

    model.things = [NSArray arrayWithObjects: c, b, nil];
    CHECK(model.selected == b);
    CHECK([button indexOfSelectedItem] == 1);

    // GUESS: an object that is no longer among the items selects none, and the model keeps it.
    model.things = [NSArray arrayWithObject: a];
    CHECK(model.selected == b);
    CHECK([button indexOfSelectedItem] == -1);
}

#define RUN(t) do { @try { t; } @catch (id e) { fprintf(stderr, "FAIL: %s raised %s\n", #t, [[e description] UTF8String]); failures++; } } while (0)

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [NSApplication sharedApplication];
    RUN(test_content_titles_and_objects());
    RUN(test_equal_descriptions_keep_every_item());
    RUN(test_content_values_give_the_titles());
    RUN(test_content_objects_replace_the_selected_object());
    RUN(test_changing_the_content_rebuilds_the_items());
    RUN(test_bound_selection_survives_a_content_change());
    if (failures == 0)
        printf("PASS appkit-popup-button-content-bindings\n");
    [pool release];
    return failures != 0;
}
