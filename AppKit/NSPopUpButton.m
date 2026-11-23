/* Copyright (c) 2006-2007 Christopher J. W. Lloyd <cjwl@objc.net>

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <AppKit/NSApplication.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSObject+BindingSupport.h>
#import <AppKit/NSPopUpButton.h>
#import <AppKit/NSPopUpButtonCell.h>
#import "NSKeyValueBinding/NSBinder.h"

NSString *const NSPopUpButtonWillPopUpNotification =
        @"NSPopUpButtonWillPopUpNotification";

@interface NSPopUpButtonCell (BindingItems)
- (NSMenuItem *) _appendItemWithTitle: (NSString *) title;
@end

static NSString *const NSPopUpButtonBindingObservationContext =
        @"NSPopUpButtonBindingObservationContext";

@implementation NSPopUpButton

+ (Class) cellClass {
    return [NSPopUpButtonCell class];
}

- initWithCoder: (NSCoder *) coder {
    self = [super initWithCoder: coder];

    if (![coder allowsKeyedCoding]) {
        NSInteger version = [coder versionForClassName: @"NSPopUpButton"];

        // Versions up to 24 archive a selector and an object, and 24 one byte more;
        // from 25 on nothing follows the control. Their meaning is unknown (nothing
        // observable changes with them).
        if (version <= 24) {
            SEL unknownSelector;
            [coder decodeValuesOfObjCTypes: ":", &unknownSelector];
            [coder decodeObject];
        }
        if (version == 24) {
            char unknownByte;
            [coder decodeValuesOfObjCTypes: "c", &unknownByte];
        }
    }
    return self;
}

// The designated initializer: -initWithFrame: (and so -init and a custom view
// in a nib) makes a pop-up list through it, so a subclass that sets itself up
// in its override of it is set up either way (as on macOS 10.14.4 and
// 26.7.3). Test: tests/appkit-popup-button-designated-init.m
- initWithFrame: (NSRect) frame pullsDown: (BOOL) pullsDown {
    [super initWithFrame: frame];
    [self setPullsDown: pullsDown];
    return self;
}

- initWithFrame: (NSRect) frame {
    return [self initWithFrame: frame pullsDown: NO];
}

- (void) dealloc {
    NS_DURING [self removeObserver: self forKeyPath: @"cell.selectedItem"];
    [self removeObserver: self forKeyPath: @"cell.menu.itemArray"];
    NS_HANDLER
    NS_ENDHANDLER

    if (NS_EXTRA_ALLOCATED(NSPopUpButton, self)) {
        [NS_EXTRA(NSPopUpButton, self)->_unmatchedItem release];
        [NS_EXTRA(NSPopUpButton, self)->_unmatchedObject release];
        [NS_EXTRA(NSPopUpButton, self)->_selectionBindings release];
    }
            NS_EXTRA_FREE(NSPopUpButton, self);
            [super dealloc];
}

- (BOOL) pullsDown {
    return [_cell pullsDown];
}

- (NSMenu *) menu {
    return [_cell menu];
}

- (BOOL) autoenablesItems {
    return [_cell autoenablesItems];
}

- (NSRectEdge) preferredEdge {
    return [_cell preferredEdge];
}

- (NSArray *) itemArray {
    return [_cell itemArray];
}

- (NSInteger) numberOfItems {
    return [_cell numberOfItems];
}

- (NSMenuItem *) itemAtIndex: (NSInteger) index {
    return [_cell itemAtIndex: index];
}

- (NSMenuItem *) itemWithTitle: (NSString *) title {
    return [_cell itemWithTitle: title];
}

- (NSMenuItem *) lastItem {
    return [_cell lastItem];
}

- (NSInteger) indexOfItem: (NSMenuItem *) item {
    return [_cell indexOfItem: item];
}

- (NSInteger) indexOfItemWithTitle: (NSString *) title {
    return [_cell indexOfItemWithTitle: title];
}

- (NSInteger) indexOfItemWithTag: (NSInteger) tag {
    return [_cell indexOfItemWithTag: tag];
}

- (NSInteger) indexOfItemWithRepresentedObject: object {
    return [_cell indexOfItemWithRepresentedObject: object];
}

- (NSInteger) indexOfItemWithTarget: target andAction: (SEL) action {
    return [_cell indexOfItemWithTarget: target andAction: action];
}

- (NSMenuItem *) selectedItem {
    return [_cell selectedItem];
}

- (NSString *) titleOfSelectedItem {
    return [_cell titleOfSelectedItem];
}

- (NSInteger) selectedTag {
    return [_cell tag];
}

- (NSInteger) indexOfSelectedItem {
    return [_cell indexOfSelectedItem];
}

- (void) setPullsDown: (BOOL) flag {
    [_cell setPullsDown: flag];
    [self setNeedsDisplay: YES];
}

- (void) setMenu: (NSMenu *) menu {
    [_cell setMenu: menu];
    [self setNeedsDisplay: YES];
}

- (void) setAutoenablesItems: (BOOL) value {
    [_cell setAutoenablesItems: value];
}

- (void) setPreferredEdge: (NSRectEdge) edge {
    [_cell setPreferredEdge: edge];
}

- (void) addItemWithTitle: (NSString *) title {
    [_cell addItemWithTitle: title];
    [self invalidateIntrinsicContentSize];
    [self setNeedsDisplay: YES];
}

- (void) addItemsWithTitles: (NSArray *) titles {
    [_cell addItemsWithTitles: titles];
    [self setNeedsDisplay: YES];
}

- (void) removeAllItems {
    [_cell removeAllItems];
    [self invalidateIntrinsicContentSize];
    [self setNeedsDisplay: YES];
}

- (void) removeItemAtIndex: (NSInteger) index {
    [_cell removeItemAtIndex: index];
    [self setNeedsDisplay: YES];
}

- (void) removeItemWithTitle: (NSString *) title {
    [_cell removeItemWithTitle: title];
    [self setNeedsDisplay: YES];
}

- (void) insertItemWithTitle: (NSString *) title atIndex: (NSInteger) index {
    [_cell insertItemWithTitle: title atIndex: index];
    [self setNeedsDisplay: YES];
}

- (void) selectItem: (NSMenuItem *) item {
    [_cell selectItem: item];
    [self setNeedsDisplay: YES];
}

- (void) selectItemAtIndex: (NSInteger) index {
    NSInteger previous = [self indexOfSelectedItem];

    [_cell selectItemAtIndex: index];
    // The title that is shown changes with the selection, and so does the intrinsic size; selecting
    // what is selected already changes nothing
    if ([self indexOfSelectedItem] != previous)
        [self invalidateIntrinsicContentSize];
    [self setNeedsDisplay: YES];
}

- (void) selectItemWithTitle: (NSString *) title {
    NSInteger previous = [self indexOfSelectedItem];

    [_cell selectItemWithTitle: title];
    if ([self indexOfSelectedItem] != previous)
        [self invalidateIntrinsicContentSize];
    [self setNeedsDisplay: YES];
}

- (BOOL) selectItemWithTag: (NSInteger) tag {
    [self setNeedsDisplay: YES];
    return [_cell selectItemWithTag: tag];
}

- (NSString *) itemTitleAtIndex: (NSInteger) index {
    return [_cell itemTitleAtIndex: index];
}

- (NSArray *) itemTitles {
    return [_cell itemTitles];
}

- (void) setTitle: (NSString *) title {
    if ([self pullsDown]) {
        // The title gets stored in the zero index item in the menu - it made
        // sense to Apple at some point...
        // QUIRK: assigning a title to a pull-down button whose menu has no
        // items neither raises nor creates the title item: the item count
        // stays 0 and the title stays empty. Not documented. Evidence:
        // black-box observation on macOS 27 (tier 2).
        // Test: tests/empty-pulldown-runtime.m
        if ([_cell numberOfItems] == 0)
            return;
        [[_cell itemAtIndex: 0] setTitle: title];
        [self synchronizeTitleAndSelectedItem];
    } else {
        [super setTitle: title];
    }
}

- (void) synchronizeTitleAndSelectedItem {
    [_cell synchronizeTitleAndSelectedItem];
    [self setNeedsDisplay: YES];
}

- (void) performClick: sender {

    if ([_cell trackMouse: [NSApp currentEvent]
                      inRect: [self bounds]
                      ofView: self
                untilMouseUp: NO]) {
        NSMenuItem *item = [self selectedItem];
        SEL action = [item action];
        id target = [item target];

        if (action != NULL) {
            // The item has an explicit action - so it's going to be the sender
            sender = item;
        }

        [_cell setState: ![_cell state]];
        [self setNeedsDisplay: YES];

        if (action == NULL) {
            action = [self action];
            target = [self target];
        } else if (target == nil) {
            target = [self target];
        }

        [NSApp sendAction: action to: target from: sender];
    }
}

- (void) mouseDown: (NSEvent *) event {
    if (![self isEnabled])
        return;

#if 1
    [self performClick: self];
#else
    if ([_cell trackMouse: event
                      inRect: [self bounds]
                      ofView: self
                untilMouseUp: NO]) {
        NSMenuItem *item = [self selectedItem];
        SEL action = [item action];
        id target = [item target];

        [_cell setState: ![_cell state]];
        [self setNeedsDisplay: YES];

        if (action == NULL) {
            action = [self action];
            target = [self target];
        } else if (target == nil) {
            target = [self target];
        }

        [self sendAction: action to: target];
    }
#endif
}

- (void) keyDown: (NSEvent *) event {
    [self interpretKeyEvents: [NSArray arrayWithObject: event]];
}

// this gets us arrow keys to select items in the menu w/o popping it up.
- (void) moveUp: (id) sender {
    [_cell moveUp: sender];
    [self setNeedsDisplay: YES];
}

- (void) moveDown: (id) sender {
    [_cell moveDown: sender];
    [self setNeedsDisplay: YES];
}

- (void) insertNewline: (id) sender {
    // Return opens the menu, the same as clicking the button.
    if ([self isEnabled])
        [self performClick: self];
}

@end

@implementation NSPopUpButton (BindingSupport)

// A bound value that is not an array (a single string, or the placeholder the
// binder substitutes for "no selection") must not be handed on as a
// collection: it counts as a one-item list. nil is no items.
static NSArray *popUpBindingArray(id value) {
    if (value == nil)
        return [NSArray array];
    if ([value isKindOfClass: [NSArray class]])
        return value;
    if ([value isKindOfClass: [NSSet class]])
        return [value allObjects];
    return [NSArray arrayWithObject: value];
}

// Item titles are strings. A member that is not one is shown by its
// description (the content binding reference gives that for content objects).
static NSString *popUpItemTitle(id value) {
    if ([value isKindOfClass: [NSString class]])
        return value;
    return [value respondsToSelector: @selector(description)] ? [value description] : @"";
}

// The array another content binding currently supplies, or nil when that
// binding is not made.
- (NSArray *) _popUpArrayOfBinding: (NSString *) name {
    id binder = [self _binderForBinding: name];

    if (binder == nil)
        return nil;
    return popUpBindingArray([[binder destination] valueForKeyPath: [binder keyPath]]);
}

// After the items are rebuilt the cell selects the first one without telling observers. The selection the
// model holds is put back through the selection binding that was made first; the binder's own write to its
// source does not write the value back to the model.
// QUIRK: when several selection bindings (selectedObject, selectedValue, selectedTag, selectedIndex) are
// bound, a change of the content applies the one bound first, while binding the next one applies its own value
// at once (so the one bound last wins until then). Not documented. Evidence: black-box observation on macOS
// 26.7.3 and 10.14.4 (tier 2), four disagreeing bindings made in two opposite orders and then a content change.
// Test: appkit-popup-button-content-bindings (test_quirk_first_bound_selection_wins_on_content_change)
- (void) _reapplyBoundSelection {
    for (NSString *name in NS_EXTRA(NSPopUpButton, self)->_selectionBindings) {
        id binder = [self _binderForBinding: name];

        if ([binder respondsToSelector: @selector(syncUp)]) {
            [binder performSelector: @selector(syncUp)];
            return;
        }
    }
}

// The three content bindings describe one list of items, so each of them
// rebuilds it from its own new value and what the other two supply. content is
// the list of objects, one item each; contentValues are the titles (else the
// descriptions of the content objects); contentObjects are the objects that
// selectedObject answers in place of the content objects (see -_selectedObject).
// https://developer.apple.com/library/archive/documentation/Cocoa/Reference/CocoaBindingsRef/BindingsText/NSPopUpButton.html
// Observed on macOS 26.7.3 and 10.14.4: an item stands for its content object as its representedObject, and each
// content object gets an item of its own even when two descriptions are equal. contentObjects is documented as
// available only with content bound (macOS raises when it is bound alone, which is not reproduced); with neither
// content nor contentValues there is nothing to build items from, so nothing changes.
// QUIRK: contentValues is honoured next to content only when its key path starts with the content key path
// (content arrangedObjects, contentValues arrangedObjects.name); any other contentValues is ignored and the
// titles are the descriptions of the content objects (macOS logs "Binding contentValues ... ignored: Key path
// ... needs to have the content key path ... as prefix"). Not documented. Evidence: black-box observation on
// macOS 26.7.3 (tier 2): content "items" with contentValues "values" gave the descriptions, an array controller's
// arrangedObjects with arrangedObjects.name gave the names. Test: appkit-popup-button-content-bindings
// (test_quirk_content_values_need_the_content_key_path_as_prefix).
// Limitation: the other two bindings are read from their destination, so a
// value transformer or null placeholder on them is not applied.
// Whether the contentValues binding, if there is one, may name the titles of the items of the content binding.
- (BOOL) _contentValuesFitContent {
    id valuesBinder = [self _binderForBinding: @"contentValues"];
    id contentBinder = [self _binderForBinding: @"content"];

    if (valuesBinder == nil || contentBinder == nil)
        return YES;
    return [[valuesBinder keyPath] hasPrefix: [[contentBinder keyPath] stringByAppendingString: @"."]];
}

- (void) _applyItemsFromContent: (NSArray *) content
                       values: (NSArray *) values
                      objects: (NSArray *) objects
{
    NSUInteger i;

    if (content != nil && ![self _contentValuesFitContent])
        values = nil;
    NSUInteger count = content != nil ? [content count] : [values count];

    if (content == nil && values == nil)
        return;

    [self _removeUnmatchedItem];
    [_cell removeAllItems];
    for (i = 0; i < count; i++) {
        NSString *title = @"";
        id represented = nil;

        if (values != nil && i < [values count])
            title = popUpItemTitle([values objectAtIndex: i]);
        else if (content != nil && i < [content count])
            title = popUpItemTitle([content objectAtIndex: i]);

        // Observed on macOS 26.7.3 and 10.14.4: contentObjects does not change what an item stands for; with
        // no content bound the title is the object.
        if (content != nil && i < [content count])
            represented = [content objectAtIndex: i];
        else
            represented = title;

        [[_cell _appendItemWithTitle: title] setRepresentedObject: represented];
    }
    [self synchronizeTitleAndSelectedItem];
    [self _reapplyBoundSelection];
}

- (id) _contentValues {
    return [self valueForKeyPath: @"itemArray.title"];
}

- (void) _setContentValues: (id) values {
    [self _applyItemsFromContent: [self _popUpArrayOfBinding: @"content"]
                        values: popUpBindingArray(values)
                       objects: [self _popUpArrayOfBinding: @"contentObjects"]];
}

- (id) _contentObjects {
    return [self valueForKeyPath: @"itemArray.representedObject"];
}

- (void) _setContentObjects: (id) objects {
    [self _applyItemsFromContent: [self _popUpArrayOfBinding: @"content"]
                        values: [self _popUpArrayOfBinding: @"contentValues"]
                       objects: popUpBindingArray(objects)];
}

- (id) _content {
    return [self valueForKeyPath: @"itemArray.representedObject"];
}

- (void) _setContent: (id) content {
    [self _applyItemsFromContent: popUpBindingArray(content)
                        values: [self _popUpArrayOfBinding: @"contentValues"]
                       objects: [self _popUpArrayOfBinding: @"contentObjects"]];
}

// QUIRK: a bound selectedObject or selectedValue that matches none of the items makes the pop-up button append
// one more item for it, titled with the value ("No Value" for nil), and select that. The item is not part of the
// content: it goes when the value matches an item again, when another item is chosen or when the content is
// rebuilt. Not documented. Evidence: black-box observation on macOS 26.7.3 and 10.14.4 (tier 2): content
// [x,y,z] with a selection of "c" gave the items x y z c with c selected, nil gave "No Value", and the item went
// when the selection came back to "y".
// Test: appkit-popup-button-content-bindings (test_quirk_unmatched_selection_gets_an_item)
- (void) _removeUnmatchedItem {
    NSMenuItem *item = NS_EXTRA(NSPopUpButton, self)->_unmatchedItem;

    if (item == nil)
        return;
    NS_EXTRA(NSPopUpButton, self)->_unmatchedItem = nil;
    [NS_EXTRA(NSPopUpButton, self)->_unmatchedObject release];
    NS_EXTRA(NSPopUpButton, self)->_unmatchedObject = nil;
    if ([self indexOfItem: item] >= 0)
        [self removeItemAtIndex: [self indexOfItem: item]];
    [item release];
}

- (void) _selectUnmatchedItemTitled: (NSString *) title forObject: (id) object {
    NSMenuItem *item = [_cell _appendItemWithTitle: title];

    NS_EXTRA(NSPopUpButton, self)->_unmatchedItem = [item retain];
    NS_EXTRA(NSPopUpButton, self)->_unmatchedObject = [object retain];
    [self selectItem: item];
}

// The object the selected item stands for: its content object, or the matching contentObjects entry when that is
// bound; for the item of an unmatched selection, the object it was made for. A model value is matched against
// the content objects only (observed on macOS 26.7.3 and 10.14.4).
- (id) _selectedObject {
    NSMenuItem *item = [_cell selectedItem];

    if (item != nil && item == NS_EXTRA(NSPopUpButton, self)->_unmatchedItem)
        return NS_EXTRA(NSPopUpButton, self)->_unmatchedObject;

    // GUESS: the reference says selectedObject answers the contentObjects entry for the chosen item when that
    // binding is made; what macOS answers was not observed (selecting a model value that is a contentObjects
    // entry did not select the item there, see -_setSelectedObject:).
    NSArray *objects = [self _popUpArrayOfBinding: @"contentObjects"];
    NSInteger index = [_cell indexOfSelectedItem];

    if (objects != nil && index >= 0 && (NSUInteger) index < [objects count])
        return [objects objectAtIndex: index];
    return [item representedObject];
}

- (void) _applySelectedObject: (id) object {
    [self _removeUnmatchedItem];
    NSInteger index = object != nil ? [_cell indexOfItemWithRepresentedObject: object] : -1;

    if (index >= 0)
        [_cell selectItemAtIndex: index];
    else
        [self _selectUnmatchedItemTitled: object != nil ? popUpItemTitle(object) : @"No Value" forObject: object];
}

- (NSInteger) _selectedTag {
    return [[_cell selectedItem] tag];
}

- (void) _applySelectedTag: (NSInteger) tag {
    int index = [_cell indexOfItemWithTag: tag];

    if (index >= 0)
        [_cell selectItemAtIndex: index];
}

- (NSUInteger) _selectedIndex {
    return [self indexOfSelectedItem];
}

- (void) _applySelectedIndex: (NSUInteger) idx {
    [self selectItemAtIndex: idx];
}

- (id) _selectedValue {
    return [self titleOfSelectedItem];
}

- (void) _applySelectedValue: (id) value {
    if (value && ![value isKindOfClass: [NSString class]]) {
        // Cocoa actually accepts non string values
        value = [NSString stringWithFormat: @"%@", value];
    }
    [self _removeUnmatchedItem];
    if (value != nil && [self indexOfItemWithTitle: value] >= 0)
        [self selectItemWithTitle: value];
    else
        [self _selectUnmatchedItemTitled: value != nil ? value : @"No Value" forObject: nil];
}

// What a binding does to the items or the selection is not a choice made in the pop-up button: the other
// selection bindings are not told of it, so they do not write their own view of the selection to the model.
// QUIRK: with several selection bindings, applying one model value changes the selection without writing to the
// model through the others. Not documented. Evidence: black-box observation on macOS 26.7.3 and 10.14.4 (tier 2):
// four selection bindings with disagreeing model values wrote nothing to the model while they were bound and when
// the content changed.
// Test: appkit-popup-button-content-bindings (test_quirk_first_bound_selection_wins_on_content_change)
- (void) _setItemsFromContent: (NSArray *) content
                       values: (NSArray *) values
                      objects: (NSArray *) objects
{
    NS_EXTRA(NSPopUpButton, self)->_boundChangeDepth++;
    [self _applyItemsFromContent: content values: values objects: objects];
    NS_EXTRA(NSPopUpButton, self)->_boundChangeDepth--;
}

- (void) _setSelectedObject: (id) object {
    NS_EXTRA(NSPopUpButton, self)->_boundChangeDepth++;
    [self _applySelectedObject: object];
    NS_EXTRA(NSPopUpButton, self)->_boundChangeDepth--;
}

- (void) _setSelectedTag: (NSInteger) tag {
    NS_EXTRA(NSPopUpButton, self)->_boundChangeDepth++;
    [self _applySelectedTag: tag];
    NS_EXTRA(NSPopUpButton, self)->_boundChangeDepth--;
}

- (void) _setSelectedIndex: (NSUInteger) idx {
    NS_EXTRA(NSPopUpButton, self)->_boundChangeDepth++;
    [self _applySelectedIndex: idx];
    NS_EXTRA(NSPopUpButton, self)->_boundChangeDepth--;
}

- (void) _setSelectedValue: (id) value {
    NS_EXTRA(NSPopUpButton, self)->_boundChangeDepth++;
    [self _applySelectedValue: value];
    NS_EXTRA(NSPopUpButton, self)->_boundChangeDepth--;
}

- (void) bind: (NSString *) binding
           toObject: (id) observable
        withKeyPath: (NSString *) keyPath
            options: (NSDictionary *) options
{
    // No need to observe the same thing many times when we have several
    // bindings
    if (!NS_EXTRA(NSPopUpButton, self)->_observerAdded) {
        NS_EXTRA(NSPopUpButton, self)->_observerAdded = YES;
        [self addObserver: self
                forKeyPath: @"cell.menu.itemArray"
                   options: NSKeyValueObservingOptionPrior
                   context: NSPopUpButtonBindingObservationContext];

        [self addObserver: self
                forKeyPath: @"cell.selectedItem"
                   options: NSKeyValueObservingOptionPrior
                   context: NSPopUpButtonBindingObservationContext];
    }
    [super bind: binding
               toObject: observable
            withKeyPath: keyPath
                options: options];

    if ([binding isEqualToString: NSSelectedObjectBinding] || [binding isEqualToString: NSSelectedValueBinding] ||
        [binding isEqualToString: NSSelectedTagBinding] || [binding isEqualToString: NSSelectedIndexBinding]) {
        NSMutableArray *order = NS_EXTRA(NSPopUpButton, self)->_selectionBindings;

        if (order == nil)
            order = NS_EXTRA(NSPopUpButton, self)->_selectionBindings = [[NSMutableArray alloc] init];
        [order removeObject: binding];
        [order addObject: binding];
    }
}

- (void) unbind: (NSString *) binding {
    [super unbind: binding];
    [NS_EXTRA(NSPopUpButton, self)->_selectionBindings removeObject: binding];
}

- (void) observeValueForKeyPath: (NSString *) keyPath
                       ofObject: (id) object
                         change: (NSDictionary *) change
                        context: (void *) context
{
    if (context == NSPopUpButtonBindingObservationContext) {
        if ([keyPath isEqualToString: @"cell.selectedItem"] && NS_EXTRA(NSPopUpButton, self)->_boundChangeDepth > 0) {
            // A binding is applying the selection: the other bindings are not told (see
            // -_setItemsFromContent:values:objects:).
        } else if ([keyPath isEqualToString: @"cell.selectedItem"]) {
            if ([[change objectForKey: NSKeyValueChangeNotificationIsPriorKey]
                        boolValue]) {
                [self willChangeValueForKey: @"selectedIndex"];
                [self willChangeValueForKey: @"selectedValue"];
                [self willChangeValueForKey: @"selectedObject"];
                [self willChangeValueForKey: @"selectedTag"];

            } else {
                [self didChangeValueForKey: @"selectedObject"];
                [self didChangeValueForKey: @"selectedValue"];
                [self didChangeValueForKey: @"selectedIndex"];
                [self didChangeValueForKey: @"selectedTag"];
                // The item made for an unmatched selection goes when another item is chosen.
                if (NS_EXTRA(NSPopUpButton, self)->_unmatchedItem != nil &&
                    [_cell selectedItem] != NS_EXTRA(NSPopUpButton, self)->_unmatchedItem)
                    [self _removeUnmatchedItem];
            }
        } else {
            if ([[change objectForKey: NSKeyValueChangeNotificationIsPriorKey]
                        boolValue]) {
                [self willChangeValueForKey: @"contentValues"];
            } else {
                [self didChangeValueForKey: @"contentValues"];
            }
        }
    } else {
        [super observeValueForKeyPath: keyPath
                             ofObject: object
                               change: change
                              context: context];
    }
}
@end
