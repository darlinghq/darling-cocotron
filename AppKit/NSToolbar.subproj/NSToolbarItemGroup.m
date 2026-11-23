/* Copyright (c) 2009 Christopher J. W. Lloyd

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
#import <AppKit/NSToolbarItemGroup.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSString.h>

@implementation NSToolbarItemGroup

- initWithItemIdentifier: (NSString *) identifier {
    [super initWithItemIdentifier: identifier];
    _subitems = [[NSArray alloc] init];
    return self;
}

// The documentation does not say how the subitems are identified, what happens when there are fewer labels than
// images or more, or where the target and action go.
// GUESS: a subitem's identifier is the group's followed by a dot and the subitem's position, so each is unique
// and none is taken for the group; labels beyond the images are ignored and images beyond the labels have none;
// the target and action are those of the group, which the documentation says the system falls back to for a
// subitem without an action, and the subitems get none.
+ (instancetype) groupWithItemIdentifier: (NSToolbarItemIdentifier) itemIdentifier
                                  images: (NSArray<NSImage *> *) images
                           selectionMode: (NSToolbarItemGroupSelectionMode) selectionMode
                                  labels: (NSArray<NSString *> *) labels
                                  target: (id) target
                                  action: (SEL) action
{
    NSToolbarItemGroup *group = [[[self alloc] initWithItemIdentifier: itemIdentifier] autorelease];
    NSMutableArray *subitems = [NSMutableArray arrayWithCapacity: [images count]];
    NSUInteger index;

    for (index = 0; index < [images count]; index++) {
        NSString *identifier = [NSString stringWithFormat: @"%@.%lu", itemIdentifier, (unsigned long) index];
        NSToolbarItem *subitem = [[[NSToolbarItem alloc] initWithItemIdentifier: identifier] autorelease];

        [subitem setImage: [images objectAtIndex: index]];
        if (index < [labels count])
            [subitem setLabel: [labels objectAtIndex: index]];
        [subitems addObject: subitem];
    }
    [group setSubitems: subitems];
    [group setSelectionMode: selectionMode];
    [group setTarget: target];
    [group setAction: action];
    return group;
}

// The mode is only stored: the group is not yet drawn as a set of segments, so no selection is made.
- (NSToolbarItemGroupSelectionMode) selectionMode {
    return NS_EXTRA(NSToolbarItemGroup, self)->_selectionMode;
}

- (void) setSelectionMode: (NSToolbarItemGroupSelectionMode) mode {
    NS_EXTRA(NSToolbarItemGroup, self)->_selectionMode = mode;
}

// GUESS: the documentation gives no default; it is automatic, the first case. Like the mode, the value is only
// stored: the group is not yet displayed as a control, so no representation changes anything.
- (NSToolbarItemGroupControlRepresentation) controlRepresentation {
    return NS_EXTRA(NSToolbarItemGroup, self)->_controlRepresentation;
}

- (void) setControlRepresentation: (NSToolbarItemGroupControlRepresentation) representation {
    NS_EXTRA(NSToolbarItemGroup, self)->_controlRepresentation = representation;
}

// The documentation says this is the index of the most recently selected subitem, and that with selectAny or
// momentary it is not the selected subitem. It states no default and nothing about an index outside the subitems.
// GUESS: the default is 0 (the side storage starts zeroed); the setter stores any value, a negative one or one
// past the last subitem included, and neither the setter nor -setSubitems: checks it against the subitems.
// Nothing selects a subitem yet, so the value is only stored.
- (NSInteger) selectedIndex {
    return NS_EXTRA(NSToolbarItemGroup, self)->_selectedIndex;
}

- (void) setSelectedIndex: (NSInteger) index {
    NS_EXTRA(NSToolbarItemGroup, self)->_selectedIndex = index;
}

// NSToolbarItem copies with NSCopyObject, which shares _subitems without retaining it and does not copy
// side storage.
- (id) copyWithZone: (NSZone *) zone {
    NSToolbarItemGroup *copy = [super copyWithZone: zone];

    copy->_subitems = [_subitems copy];
    NS_EXTRA_COPY(NSToolbarItemGroup, copy, self);
    return copy;
}

- (void) dealloc {
    [_subitems release];
    [super dealloc];
}

- (NSArray *) subitems {
    return _subitems;
}

- (void) setSubitems: (NSArray *) subitems {
    subitems = [subitems retain];
    [_subitems release];
    _subitems = subitems;
}

@end
