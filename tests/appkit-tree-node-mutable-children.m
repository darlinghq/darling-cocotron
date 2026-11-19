// Copyright (C) 2026 Lubos Dolezel
//
// -[NSTreeNode mutableChildNodes], as observed on macOS 26.7.3 (black-box): a node added through
// it gets the receiver as its parent, a node moved to another parent leaves the old one, a removed
// or replaced node has no parent, childNodes is the live list, and observers of childNodes are
// told about each insertion and removal with its kind and indexes. -sortWithSortDescriptors:recursively:
// compares the represented objects and sets the children as a whole.
//
// Build: clang -framework AppKit appkit-tree-node-mutable-children.m
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

@interface ChangeLog : NSObject {
@public
    NSMutableArray *changes;
}
@end
@implementation ChangeLog
- (instancetype) init {
    if ((self = [super init]))
        changes = [NSMutableArray new];
    return self;
}
- (void) observeValueForKeyPath: (NSString *) keyPath ofObject: (id) object change: (NSDictionary *) change
                        context: (void *) context {
    NSIndexSet *indexes = [change objectForKey: NSKeyValueChangeIndexesKey];
    [changes addObject: [NSString stringWithFormat: @"%@:%lu@%lu", [object representedObject],
                         (unsigned long) [[change objectForKey: NSKeyValueChangeKindKey] unsignedIntegerValue],
                         (unsigned long) [indexes firstIndex]]];
}
@end

static NSString *names(NSTreeNode *node) {
    return [[[node childNodes] valueForKey: @"representedObject"] componentsJoinedByString: @","];
}

int main(void) {
    @autoreleasepool {
        NSTreeNode *a = [NSTreeNode treeNodeWithRepresentedObject: @"a"];
        NSTreeNode *b = [NSTreeNode treeNodeWithRepresentedObject: @"b"];
        NSTreeNode *c = [NSTreeNode treeNodeWithRepresentedObject: @"c"];
        NSTreeNode *d = [NSTreeNode treeNodeWithRepresentedObject: @"d"];
        ChangeLog *log = [ChangeLog new];
        [a addObserver: log forKeyPath: @"childNodes" options: 0 context: NULL];
        [b addObserver: log forKeyPath: @"childNodes" options: 0 context: NULL];

        CHECK([a isLeaf] && [[a childNodes] count] == 0);
        NSMutableArray *children = [a mutableChildNodes];
        [children addObject: b];
        [children addObject: c];
        CHECK([names(a) isEqualToString: @"b,c"]);
        CHECK([b parentNode] == a && [c parentNode] == a && ![a isLeaf]);
        CHECK([[c indexPath] isEqual: [NSIndexPath indexPathWithIndex: 1]]);
        CHECK([a childNodes] == [a childNodes]);

        // moving c under b takes it away from a
        [[b mutableChildNodes] addObject: c];
        CHECK([names(a) isEqualToString: @"b"] && [names(b) isEqualToString: @"c"]);
        CHECK([c parentNode] == b);
        NSUInteger path[] = { 0, 0 };
        CHECK([[c indexPath] isEqual: [NSIndexPath indexPathWithIndexes: path length: 2]]);
        CHECK([a descendantNodeAtIndexPath: [NSIndexPath indexPathWithIndexes: path length: 2]] == c);

        [children insertObject: d atIndex: 0];
        CHECK([names(a) isEqualToString: @"d,b"] && [d parentNode] == a);
        [children removeObjectAtIndex: 0];
        CHECK([names(a) isEqualToString: @"b"] && [d parentNode] == nil);
        NSArray *expected = [NSArray arrayWithObjects: @"a:2@0", @"a:2@1", @"a:3@1", @"b:2@0", @"a:2@0", @"a:3@0", nil];
        CHECK([log->changes isEqualToArray: expected]);
        if (![log->changes isEqualToArray: expected])
            fprintf(stderr, "changes: %s\n", [[log->changes componentsJoinedByString: @" "] UTF8String]);

        [children replaceObjectAtIndex: 0 withObject: d];
        CHECK([names(a) isEqualToString: @"d"] && [b parentNode] == nil && [d parentNode] == a);

        // Sorting compares the represented objects; observers see the list set as a whole.
        NSTreeNode *root = [NSTreeNode treeNodeWithRepresentedObject: @"root"];
        for (NSString *name in [NSArray arrayWithObjects: @"bb", @"a", @"ccc", nil]) {
            NSTreeNode *node = [NSTreeNode treeNodeWithRepresentedObject: name];
            [[root mutableChildNodes] addObject: node];
            [[node mutableChildNodes] addObject: [NSTreeNode treeNodeWithRepresentedObject: [name stringByAppendingString: @"y"]]];
            [[node mutableChildNodes] addObject: [NSTreeNode treeNodeWithRepresentedObject: [name stringByAppendingString: @"z"]]];
        }
        [root addObserver: log forKeyPath: @"childNodes" options: 0 context: NULL];
        [log->changes removeAllObjects];
        NSArray *byLength = [NSArray arrayWithObject: [NSSortDescriptor sortDescriptorWithKey: @"length" ascending: YES]];
        [root sortWithSortDescriptors: byLength recursively: NO];
        CHECK([names(root) isEqualToString: @"a,bb,ccc"]);
        CHECK([log->changes count] == 1 && [[log->changes objectAtIndex: 0] hasPrefix: @"root:1@"]);
        NSArray *descending = [NSArray arrayWithObject: [NSSortDescriptor sortDescriptorWithKey: @"self" ascending: NO]];
        [root sortWithSortDescriptors: descending recursively: YES];
        CHECK([names(root) isEqualToString: @"ccc,bb,a"]);
        CHECK([names([[root childNodes] objectAtIndex: 0]) isEqualToString: @"cccz,cccy"]);
        [root sortWithSortDescriptors: [NSArray array] recursively: YES];
        CHECK([names(root) isEqualToString: @"ccc,bb,a"]);
        [root removeObserver: log forKeyPath: @"childNodes"];

        [a removeObserver: log forKeyPath: @"childNodes"];
        [b removeObserver: log forKeyPath: @"childNodes"];
    }
    if (failures)
        return 1;
    printf("PASS\n");
    return 0;
}
