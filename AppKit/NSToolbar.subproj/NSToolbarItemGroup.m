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
#import <Foundation/NSUUID.h>

@implementation NSToolbarItemGroup

- initWithItemIdentifier: (NSString *) identifier {
    [super initWithItemIdentifier: identifier];
    _subitems = [[NSArray alloc] init];
    return self;
}

// The documentation does not say how the subitems are identified, what happens when there are fewer labels than
// images or more, or where the target and action go.
// QUIRK: the subitems get unique identifiers of their own (UUID strings, not derived from the group's),
// a label is also the subitem's palette label, labels beyond the images are ignored and images beyond the
// labels have none, the target and action are those of the group (the subitems get none), and the group is
// always an NSToolbarItemGroup, also when the factory is sent to a subclass. Not documented. Evidence:
// black-box observation of the factory on macOS 26.7.3 (tier 2; the API is new in macOS 10.15, Mac OS X
// 10.14.4 has no factory; probe tig.m). Test: appkit-toolbaritemgroup-factory.
+ (instancetype) groupWithItemIdentifier: (NSToolbarItemIdentifier) itemIdentifier
                                  images: (NSArray<NSImage *> *) images
                           selectionMode: (NSToolbarItemGroupSelectionMode) selectionMode
                                  labels: (NSArray<NSString *> *) labels
                                  target: (id) target
                                  action: (SEL) action
{
    NSToolbarItemGroup *group = [[[NSToolbarItemGroup alloc] initWithItemIdentifier: itemIdentifier] autorelease];
    NSMutableArray *subitems = [NSMutableArray arrayWithCapacity: [images count]];
    NSUInteger index;

    for (index = 0; index < [images count]; index++) {
        NSString *identifier = [[NSUUID UUID] UUIDString];
        NSToolbarItem *subitem = [[[NSToolbarItem alloc] initWithItemIdentifier: identifier] autorelease];

        [subitem setImage: [images objectAtIndex: index]];
        if (index < [labels count]) {
            [subitem setLabel: [labels objectAtIndex: index]];
            [subitem setPaletteLabel: [labels objectAtIndex: index]];
        }
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

// The documentation gives no default; macOS 26.7.3 starts at automatic, the first case (probe tig.m). Like the mode, the value is only
// stored: the group is not yet displayed as a control, so no representation changes anything.
- (NSToolbarItemGroupControlRepresentation) controlRepresentation {
    return NS_EXTRA(NSToolbarItemGroup, self)->_controlRepresentation;
}

- (void) setControlRepresentation: (NSToolbarItemGroupControlRepresentation) representation {
    NS_EXTRA(NSToolbarItemGroup, self)->_controlRepresentation = representation;
}

// NSToolbarItem copies with NSCopyObject, which shares _subitems without retaining it and does not copy
// side storage.
// QUIRK: the copy has copies of the subitems, and neither the selection mode nor the control representation of
// the original: they have their defaults. Not documented. Evidence: black-box observation of -copy on
// macOS 26.7.3 (tier 2; probe tig.m). Test: appkit-toolbaritemgroup-factory, -control-representation.
- (id) copyWithZone: (NSZone *) zone {
    NSToolbarItemGroup *copy = [super copyWithZone: zone];

    copy->_subitems = [[NSArray alloc] initWithArray: _subitems copyItems: YES];
    NS_EXTRA_COPY(NSToolbarItemGroup, copy, self);
    NS_EXTRA(NSToolbarItemGroup, copy)->_selectionMode = NSToolbarItemGroupSelectionModeSelectOne;
    NS_EXTRA(NSToolbarItemGroup, copy)->_controlRepresentation = NSToolbarItemGroupControlRepresentationAutomatic;
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
