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
// The order in which the bindings are made must not matter. Beyond the reference, black-box observation on macOS
// 26.7.3 and 10.14.4 gave: an item keeps its content object as its representedObject; every content object gets
// its own item even when two descriptions are equal (test_equal_descriptions_keep_every_item); a bound selection
// survives a content change (test_bound_selection_survives_a_content_change); and the QUIRK tests
// test_quirk_unmatched_selection_gets_an_item, test_quirk_first_bound_selection_wins_on_content_change,
// test_quirk_content_values_need_the_content_key_path_as_prefix, test_quirk_bound_items_are_tagged_by_index and
// test_quirk_index_bindings_make_items_stand_for_indexes.
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
- (NSString *) label {
    return [@"Label " stringByAppendingString: _name];
}
@end

@interface Model : NSObject {
    NSArray *_things;
    NSArray *_titles;
    NSArray *_stand;
    id _selected;
    id _value;
    id _index;
    id _tag;
}
@property(retain) id value;
@property(retain) id index;
@property(retain) id tag;
@property(retain) NSArray *things;
@property(retain) NSArray *titles;
@property(retain) NSArray *stand;
@property(retain) id selected;
@end
@implementation Model
@synthesize things = _things, titles = _titles, stand = _stand, selected = _selected;
@synthesize value = _value, index = _index, tag = _tag;
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

// contentValues are the titles. On macOS they count next to content only when their key path starts with the
// content key path, as when both come from an array controller (see
// test_quirk_content_values_need_the_content_key_path_as_prefix); the order of the bindings does not matter.
static void test_content_values_give_the_titles(void) {
    Thing *a = [[[Thing alloc] initWithName: @"Alpha"] autorelease];
    Thing *b = [[[Thing alloc] initWithName: @"Beta"] autorelease];
    int order;

    for (order = 0; order < 2; order++) {
        Model *model = [[Model new] autorelease];
        NSPopUpButton *button = makeButton();

        model.things = [NSArray arrayWithObjects: a, b, nil];
        if (order == 0) {
            [button bind: NSContentBinding toObject: model withKeyPath: @"things" options: nil];
            [button bind: NSContentValuesBinding toObject: model withKeyPath: @"things.label" options: nil];
        } else {
            [button bind: NSContentValuesBinding toObject: model withKeyPath: @"things.label" options: nil];
            [button bind: NSContentBinding toObject: model withKeyPath: @"things" options: nil];
        }
        CHECK([button numberOfItems] == 2);
        CHECK([[button itemTitleAtIndex: 0] isEqualToString: @"Label Alpha"]);
        CHECK([[button itemTitleAtIndex: 1] isEqualToString: @"Label Beta"]);
        CHECK([[button itemAtIndex: 1] representedObject] == b);
    }
}

// Observed on macOS 26.7.3: content "things" with contentValues "titles" (a key path that does not start with
// "things.") leaves the titles as the descriptions of the content objects; contentValues without content gives
// the titles (and each title is the item's representedObject).
static void test_quirk_content_values_need_the_content_key_path_as_prefix(void) {
    Thing *a = [[[Thing alloc] initWithName: @"Alpha"] autorelease];
    Thing *b = [[[Thing alloc] initWithName: @"Beta"] autorelease];
    Model *model = [[Model new] autorelease];
    NSPopUpButton *button = makeButton();

    model.things = [NSArray arrayWithObjects: a, b, nil];
    model.titles = [NSArray arrayWithObjects: @"First", @"Second", nil];
    [button bind: NSContentBinding toObject: model withKeyPath: @"things" options: nil];
    [button bind: NSContentValuesBinding toObject: model withKeyPath: @"titles" options: nil];
    CHECK([[button itemTitleAtIndex: 0] isEqualToString: @"Alpha"]);
    CHECK([[button itemTitleAtIndex: 1] isEqualToString: @"Beta"]);

    model = [[Model new] autorelease];
    button = makeButton();
    model.titles = [NSArray arrayWithObjects: @"First", @"Second", nil];
    [button bind: NSContentValuesBinding toObject: model withKeyPath: @"titles" options: nil];
    CHECK([button numberOfItems] == 2);
    CHECK([[button itemTitleAtIndex: 1] isEqualToString: @"Second"]);
    CHECK([[[button itemAtIndex: 1] representedObject] isEqual: @"Second"]);
}

// The reference makes contentObjects available only with content bound (macOS raises when it is bound alone, so
// only that order is tested), and makes selectedObject answer the contentObjects entry of the chosen item. The
// answer is a GUESS: macOS was observed to keep the content objects as the items' representedObjects and to match
// a model value only against them, but what it writes to the model for a user's choice was not observed.
static void test_content_objects_replace_the_selected_object(void) {
    Thing *a = [[[Thing alloc] initWithName: @"Alpha"] autorelease];
    Thing *b = [[[Thing alloc] initWithName: @"Beta"] autorelease];
    NSString *x = @"x-object", *y = @"y-object";
    Model *model = [[Model new] autorelease];
    NSPopUpButton *button = makeButton();

    model.things = [NSArray arrayWithObjects: a, b, nil];
    model.stand = [NSArray arrayWithObjects: x, y, nil];
    model.selected = a;
    [button bind: NSContentBinding toObject: model withKeyPath: @"things" options: nil];
    [button bind: NSContentObjectsBinding toObject: model withKeyPath: @"stand" options: nil];
    [button bind: NSSelectedObjectBinding toObject: model withKeyPath: @"selected" options: nil];

    CHECK([button numberOfItems] == 2);
    CHECK([[button itemTitleAtIndex: 0] isEqualToString: @"Alpha"]);
    CHECK([[button itemAtIndex: 0] representedObject] == a);
    [button selectItemAtIndex: 1];
    CHECK(model.selected == y);
    [button selectItemAtIndex: 0];
    CHECK(model.selected == x);
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

    // An object that is no longer among the items is shown by an item of its own (see
    // test_quirk_unmatched_selection_gets_an_item), and the model keeps it.
    model.things = [NSArray arrayWithObject: a];
    CHECK(model.selected == b);
    CHECK([button numberOfItems] == 2);
    CHECK([button indexOfSelectedItem] == 1);
    CHECK([[button titleOfSelectedItem] isEqualToString: @"Beta"]);
}

// Observed on macOS 26.7.3 and 10.14.4 (case numbers of the probe in parentheses): content [x,y,z] and a bound
// selectedObject that matches no item adds an item titled with the value and selects it (641.13, 641.14), nil gives
// "No Value" (641.15), and the item goes when the value matches an item again (641.16). Content replaced so that
// the selected object is not among the new items adds the item too (641.13). The model is not written by this.
static void test_quirk_unmatched_selection_gets_an_item(void) {
    NSString *x = @"x", *y = @"y", *z = @"z";
    Model *model = [[Model new] autorelease];
    NSPopUpButton *button = makeButton();

    model.things = [NSArray arrayWithObjects: x, y, z, nil];
    [button bind: NSContentBinding toObject: model withKeyPath: @"things" options: nil];
    [button bind: NSSelectedObjectBinding toObject: model withKeyPath: @"selected" options: nil];

    model.selected = @"zzz";
    CHECK([button numberOfItems] == 4);
    CHECK([[button itemTitleAtIndex: 3] isEqualToString: @"zzz"]);
    CHECK([button indexOfSelectedItem] == 3);
    CHECK([[button itemAtIndex: 3] representedObject] == nil);

    model.selected = nil;
    CHECK([button numberOfItems] == 4);
    CHECK([[button itemTitleAtIndex: 3] isEqualToString: @"No Value"]);
    CHECK([button indexOfSelectedItem] == 3);

    model.selected = y;
    CHECK([button numberOfItems] == 3);
    CHECK([button indexOfSelectedItem] == 1);
    CHECK(model.selected == y);

    // The same for selectedValue, which compares with the titles.
    Model *other = [[Model new] autorelease];
    NSPopUpButton *second = makeButton();
    other.things = [NSArray arrayWithObjects: x, y, z, nil];
    [second bind: NSContentBinding toObject: other withKeyPath: @"things" options: nil];
    [second bind: NSSelectedValueBinding toObject: other withKeyPath: @"value" options: nil];
    other.value = @"B";
    CHECK([second numberOfItems] == 4);
    CHECK([[second titleOfSelectedItem] isEqualToString: @"B"]);
    other.value = @"y";
    CHECK([second numberOfItems] == 3);
    CHECK([second indexOfSelectedItem] == 1);
}

// Observed on macOS 26.7.3 and 10.14.4 (641.26 to 641.29): selection bindings made with disagreeing model
// values. After a content change the one bound first is applied: selectedObject (c, index 2) when the order was
// selectedObject, selectedValue, selectedTag, selectedIndex, and selectedIndex (0) when it was the reverse.
static void test_quirk_first_bound_selection_wins_on_content_change(void) {
    NSString *a = @"a", *b = @"b", *c = @"c", *d = @"d";
    int order;

    for (order = 0; order < 2; order++) {
        Model *model = [[Model new] autorelease];
        NSPopUpButton *button = makeButton();

        model.things = [NSArray arrayWithObjects: a, b, c, nil];
        model.selected = c;
        model.value = @"B";
        model.index = [NSNumber numberWithInt: 0];
        model.tag = [NSNumber numberWithInt: 1];
        [button bind: NSContentBinding toObject: model withKeyPath: @"things" options: nil];
        if (order == 0) {
            [button bind: NSSelectedObjectBinding toObject: model withKeyPath: @"selected" options: nil];
            [button bind: NSSelectedValueBinding toObject: model withKeyPath: @"value" options: nil];
            [button bind: NSSelectedTagBinding toObject: model withKeyPath: @"tag" options: nil];
            [button bind: NSSelectedIndexBinding toObject: model withKeyPath: @"index" options: nil];
        } else {
            [button bind: NSSelectedIndexBinding toObject: model withKeyPath: @"index" options: nil];
            [button bind: NSSelectedTagBinding toObject: model withKeyPath: @"tag" options: nil];
            [button bind: NSSelectedValueBinding toObject: model withKeyPath: @"value" options: nil];
            [button bind: NSSelectedObjectBinding toObject: model withKeyPath: @"selected" options: nil];
        }
        model.things = [NSArray arrayWithObjects: a, b, c, d, nil];
        CHECK([button numberOfItems] == 4);
        CHECK([button indexOfSelectedItem] == (order == 0 ? 2 : 0));
        // Neither binding nor the content change writes what the pop-up button shows to the model (641.26 to 641.29).
        CHECK(model.selected == c && [model.value isEqual: @"B"] && [model.index intValue] == 0 &&
              [model.tag intValue] == 1);
    }
}

// QUIRK (macOS 26.7.3, 10.14.4 and 26.1, probe 641.1, 641.3, 641.25, 641.35): the items the content bindings build are tagged with their
// index, so a bound selectedTag selects the item with that index; a pull-down's items are tagged the same way.
static void test_quirk_bound_items_are_tagged_by_index(void) {
    NSString *a = @"a", *b = @"b", *c = @"c";
    Model *model = [[Model new] autorelease];
    NSPopUpButton *button = makeButton();

    model.things = [NSArray arrayWithObjects: a, b, c, nil];
    model.tag = [NSNumber numberWithInt: 1];
    [button bind: NSContentBinding toObject: model withKeyPath: @"things" options: nil];
    CHECK([[button itemAtIndex: 0] tag] == 0 && [[button itemAtIndex: 1] tag] == 1 && [[button itemAtIndex: 2] tag] == 2);
    [button bind: NSSelectedTagBinding toObject: model withKeyPath: @"tag" options: nil];
    CHECK([button indexOfSelectedItem] == 1);
    CHECK([[button titleOfSelectedItem] isEqual: @"b"]);

    // Rebuilt items are tagged afresh.
    model.things = [NSArray arrayWithObjects: c, b, a, @"d", nil];
    CHECK([[button itemAtIndex: 3] tag] == 3);
    CHECK([button indexOfSelectedItem] == 1);

    // contentValues alone (no content) tags them too
    Model *valuesModel = [[Model new] autorelease];
    NSPopUpButton *valuesButton = makeButton();

    valuesModel.titles = [NSArray arrayWithObjects: @"A", @"B", nil];
    [valuesButton bind: NSContentValuesBinding toObject: valuesModel withKeyPath: @"titles" options: nil];
    CHECK([[valuesButton itemAtIndex: 1] tag] == 1);

    NSPopUpButton *pullDown = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect(0, 0, 100, 22) pullsDown: YES] autorelease];
    Model *pullModel = [[Model new] autorelease];

    pullModel.things = [NSArray arrayWithObjects: @"t", @"a", @"b", nil];
    [pullDown bind: NSContentBinding toObject: pullModel withKeyPath: @"things" options: nil];
    CHECK([pullDown numberOfItems] == 3 && [[pullDown itemAtIndex: 2] tag] == 2);
}

// QUIRK (macOS 26.7.3, 10.14.4 and 26.1, probe 641.20 to 641.29): with selectedIndex or selectedTag as the first selection binding the
// items' representedObjects are their indexes, so a selectedObject made later matches no item and gets one of its
// own; with selectedObject or selectedValue first they stay the content objects.
static void test_quirk_index_bindings_make_items_stand_for_indexes(void) {
    NSString *a = @"a", *b = @"b", *c = @"c", *d = @"d";
    int which;

    for (which = 0; which < 2; which++) {
        Model *model = [[Model new] autorelease];
        NSPopUpButton *button = makeButton();

        model.things = [NSArray arrayWithObjects: a, b, c, nil];
        model.index = [NSNumber numberWithInt: 2];
        model.tag = [NSNumber numberWithInt: 2];
        [button bind: NSContentBinding toObject: model withKeyPath: @"things" options: nil];
        CHECK([[button itemAtIndex: 1] representedObject] == b); // no selection binding yet: the content object
        [button bind: which == 0 ? NSSelectedIndexBinding : NSSelectedTagBinding toObject: model
         withKeyPath: which == 0 ? @"index" : @"tag" options: nil];
        // the items already there change too
        CHECK([[[button itemAtIndex: 0] representedObject] isEqual: [NSNumber numberWithInt: 0]]);
        CHECK([[[button itemAtIndex: 2] representedObject] isEqual: [NSNumber numberWithInt: 2]]);
        CHECK([button indexOfSelectedItem] == 2);

        model.things = [NSArray arrayWithObjects: a, b, c, d, nil];
        CHECK([[[button itemAtIndex: 3] representedObject] isEqual: [NSNumber numberWithInt: 3]]);

        // a selectedObject bound later finds no item for "c" and gets an extra one (641.27)
        model.selected = c;
        [button bind: NSSelectedObjectBinding toObject: model withKeyPath: @"selected" options: nil];
        CHECK([button numberOfItems] == 5 && [[button itemAtIndex: 4] representedObject] == nil);
        CHECK([[button titleOfSelectedItem] isEqual: @"c"] && [button indexOfSelectedItem] == 4);
    }

    // selectedValue first: the content objects stay
    Model *model = [[Model new] autorelease];
    NSPopUpButton *button = makeButton();

    model.things = [NSArray arrayWithObjects: a, b, c, nil];
    model.value = @"b";
    [button bind: NSContentBinding toObject: model withKeyPath: @"things" options: nil];
    [button bind: NSSelectedValueBinding toObject: model withKeyPath: @"value" options: nil];
    CHECK([[button itemAtIndex: 1] representedObject] == b);
    CHECK([[button itemAtIndex: 2] representedObject] == c);

    // Items that no content binding built keep their representedObjects (not observed on macOS; the rule is
    // limited to what the probe showed)
    NSPopUpButton *plain = makeButton();
    Model *plainModel = [[Model new] autorelease];

    [plain addItemWithTitle: @"x"];
    [[plain itemAtIndex: 0] setRepresentedObject: a];
    plainModel.index = [NSNumber numberWithInt: 0];
    [plain bind: NSSelectedIndexBinding toObject: plainModel withKeyPath: @"index" options: nil];
    CHECK([[plain itemAtIndex: 0] representedObject] == a);

    // contentValues alone: the items stand for their indexes too (macOS 26.7.3 and 10.14.4, probe popup2.m), whichever
    // of the two bindings is made first; a selectedValue binding leaves the titles as the representedObjects
    NSPopUpButton *titled = makeButton();
    Model *titledModel = [[Model new] autorelease];

    titledModel.titles = [NSArray arrayWithObjects: @"A", @"B", nil];
    titledModel.index = [NSNumber numberWithInt: 1];
    [titled bind: NSContentValuesBinding toObject: titledModel withKeyPath: @"titles" options: nil];
    [titled bind: NSSelectedIndexBinding toObject: titledModel withKeyPath: @"index" options: nil];
    CHECK([[[titled itemAtIndex: 1] representedObject] isEqual: [NSNumber numberWithInt: 1]]);
    CHECK([titled indexOfSelectedItem] == 1);

    NSPopUpButton *selectionFirst = makeButton();
    Model *selectionFirstModel = [[Model new] autorelease];

    selectionFirstModel.titles = [NSArray arrayWithObjects: @"A", @"B", nil];
    selectionFirstModel.tag = [NSNumber numberWithInt: 1];
    [selectionFirst bind: NSSelectedTagBinding toObject: selectionFirstModel withKeyPath: @"tag" options: nil];
    [selectionFirst bind: NSContentValuesBinding toObject: selectionFirstModel withKeyPath: @"titles" options: nil];
    CHECK([[[selectionFirst itemAtIndex: 0] representedObject] isEqual: [NSNumber numberWithInt: 0]]);
    CHECK([[[selectionFirst itemAtIndex: 1] representedObject] isEqual: [NSNumber numberWithInt: 1]]);
    CHECK([selectionFirst indexOfSelectedItem] == 1);

    NSPopUpButton *valueBound = makeButton();
    Model *valueModel = [[Model new] autorelease];

    valueModel.titles = [NSArray arrayWithObjects: @"A", @"B", nil];
    valueModel.value = @"B";
    [valueBound bind: NSContentValuesBinding toObject: valueModel withKeyPath: @"titles" options: nil];
    [valueBound bind: NSSelectedValueBinding toObject: valueModel withKeyPath: @"value" options: nil];
    CHECK([[[valueBound itemAtIndex: 1] representedObject] isEqual: @"B"]);
}

#define RUN(t) do { @try { t; } @catch (id e) { fprintf(stderr, "FAIL: %s raised %s\n", #t, [[e description] UTF8String]); failures++; } } while (0)

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [NSApplication sharedApplication];
    RUN(test_content_titles_and_objects());
    RUN(test_equal_descriptions_keep_every_item());
    RUN(test_content_values_give_the_titles());
    RUN(test_quirk_content_values_need_the_content_key_path_as_prefix());
    RUN(test_content_objects_replace_the_selected_object());
    RUN(test_changing_the_content_rebuilds_the_items());
    RUN(test_bound_selection_survives_a_content_change());
    RUN(test_quirk_unmatched_selection_gets_an_item());
    RUN(test_quirk_first_bound_selection_wins_on_content_change());
    RUN(test_quirk_bound_items_are_tagged_by_index());
    RUN(test_quirk_index_bindings_make_items_stand_for_indexes());
    if (failures == 0)
        printf("PASS appkit-popup-button-content-bindings\n");
    [pool release];
    return failures != 0;
}
