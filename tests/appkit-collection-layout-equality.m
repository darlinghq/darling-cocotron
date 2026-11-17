#import "appkit-collection-layout.h"

// Equality of the NSCollectionLayout* classes. The documentation is silent; the behavior is the quirk observed on macOS
// 26.7.3 (x86_64) and 27.0.1 (arm64): the value classes compare by their properties, the hash is not overridden, and a
// custom group item and the compositional layout configuration compare by identity.
typedef NSCollectionLayoutDimension Dim;
typedef NSCollectionLayoutSize LSize;
typedef NSCollectionLayoutSpacing Spacing;
typedef NSCollectionLayoutAnchor Anchor;
typedef NSCollectionLayoutItem Item;
typedef NSCollectionLayoutGroup Group;
typedef NSCollectionLayoutSupplementaryItem Supp;
typedef NSCollectionLayoutBoundarySupplementaryItem Boundary;
typedef NSCollectionLayoutDecorationItem Decoration;
typedef NSCollectionLayoutSection Section;

static LSize *size(CGFloat w, CGFloat h) {
    return [LSize sizeWithWidthDimension: [Dim absoluteDimension: w] heightDimension: [Dim absoluteDimension: h]];
}
static Anchor *anchor(NSDirectionalRectEdge edges) { return [Anchor layoutAnchorWithEdges: edges]; }
static Supp *supp(NSString *kind, NSInteger z) {
    Supp *s = [Supp supplementaryItemWithLayoutSize: size(1, 1) elementKind: kind containerAnchor: anchor(NSDirectionalRectEdgeTop)];
    [s setZIndex: z];
    return s;
}
static Boundary *boundary(NSString *kind, NSRectAlignment alignment) {
    return [Boundary boundarySupplementaryItemWithLayoutSize: size(1, 1) elementKind: kind alignment: alignment];
}
static Group *group(NSArray *subitems) { return [Group horizontalGroupWithLayoutSize: size(100, 50) subitems: subitems]; }
static Item *item(CGFloat w) { return [Item itemWithLayoutSize: size(w, 20)]; }

#define SAME(a, b, what) expect([(a) isEqual: (b)] && [(b) isEqual: (a)], @"equal: " what)
#define DIFF(a, b, what) expect(![(a) isEqual: (b)] && ![(b) isEqual: (a)], @"different: " what)

int main(void) {
    @autoreleasepool {
        Class itemClass = NSClassFromString(@"NSCollectionLayoutItem");
        expect(itemClass != Nil && NSClassFromString(@"NSCollectionLayoutSection") != Nil, @"the layout classes exist");
        expectFromCollectionViewCore(itemClass);

        // Dimension, size, spacing, edge spacing, anchor.
        SAME([Dim absoluteDimension: 10], [Dim absoluteDimension: 10], @"dimensions built alike");
        DIFF([Dim absoluteDimension: 10], [Dim absoluteDimension: 11], @"dimension value");
        DIFF([Dim absoluteDimension: 10], [Dim estimatedDimension: 10], @"dimension kind");
        DIFF([Dim fractionalWidthDimension: 0.5], [Dim fractionalHeightDimension: 0.5], @"fractional width and height");
        DIFF([Dim absoluteDimension: 1], @1, @"a dimension and a number");
        expect(![[Dim absoluteDimension: 1] isEqual: nil], @"a dimension is not equal to nil");
        SAME(size(10, 20), size(10, 20), @"sizes built alike");
        DIFF(size(10, 20), size(11, 20), @"size width");
        DIFF(size(10, 20), size(10, 21), @"size height");
        DIFF(size(10, 20), [LSize sizeWithWidthDimension: [Dim estimatedDimension: 10] heightDimension: [Dim absoluteDimension: 20]], @"size width kind");
        SAME([Spacing fixedSpacing: 5], [Spacing fixedSpacing: 5], @"spacings built alike");
        DIFF([Spacing fixedSpacing: 5], [Spacing fixedSpacing: 6], @"spacing value");
        DIFF([Spacing fixedSpacing: 5], [Spacing flexibleSpacing: 5], @"fixed and flexible spacing");
        Spacing *zero = [Spacing fixedSpacing: 0], *one = [Spacing fixedSpacing: 1];
        NSCollectionLayoutEdgeSpacing *edges = [NSCollectionLayoutEdgeSpacing spacingForLeading: zero top: zero trailing: zero bottom: zero];
        SAME(edges, [NSCollectionLayoutEdgeSpacing spacingForLeading: zero top: zero trailing: zero bottom: zero], @"edge spacings built alike");
        DIFF(edges, [NSCollectionLayoutEdgeSpacing spacingForLeading: one top: zero trailing: zero bottom: zero], @"edge spacing leading");
        DIFF(edges, [NSCollectionLayoutEdgeSpacing spacingForLeading: zero top: one trailing: zero bottom: zero], @"edge spacing top");
        DIFF(edges, [NSCollectionLayoutEdgeSpacing spacingForLeading: zero top: zero trailing: one bottom: zero], @"edge spacing trailing");
        DIFF(edges, [NSCollectionLayoutEdgeSpacing spacingForLeading: zero top: zero trailing: zero bottom: one], @"edge spacing bottom");
        DIFF(edges, [NSCollectionLayoutEdgeSpacing spacingForLeading: zero top: nil trailing: zero bottom: zero], @"a nil and a zero edge spacing");
        SAME([NSCollectionLayoutEdgeSpacing spacingForLeading: zero top: nil trailing: nil bottom: nil],
             [NSCollectionLayoutEdgeSpacing spacingForLeading: zero top: nil trailing: nil bottom: nil], @"edge spacings with nil sides");
        SAME(anchor(NSDirectionalRectEdgeTop), anchor(NSDirectionalRectEdgeTop), @"anchors built alike");
        DIFF(anchor(NSDirectionalRectEdgeTop), anchor(NSDirectionalRectEdgeBottom), @"anchor edges");
        Anchor *absolute = [Anchor layoutAnchorWithEdges: NSDirectionalRectEdgeTop absoluteOffset: NSMakePoint(1, 2)];
        DIFF(absolute, [Anchor layoutAnchorWithEdges: NSDirectionalRectEdgeTop absoluteOffset: NSMakePoint(1, 3)], @"anchor offset");
        DIFF(absolute, [Anchor layoutAnchorWithEdges: NSDirectionalRectEdgeTop fractionalOffset: NSMakePoint(1, 2)], @"absolute and fractional offset");
        SAME(absolute, [Anchor layoutAnchorWithEdges: NSDirectionalRectEdgeTop absoluteOffset: NSMakePoint(1, 2)], @"anchors with an offset");

        // Items.
        SAME(item(10), item(10), @"items built alike");
        SAME(item(10), [[item(10) copy] autorelease], @"an item and its copy");
        DIFF(item(10), item(11), @"item size");
        Item *insets = item(10);
        [insets setContentInsets: NSDirectionalEdgeInsetsMake(1, 0, 0, 0)];
        DIFF(item(10), insets, @"item content insets");
        Item *spaced = item(10);
        [spaced setEdgeSpacing: [NSCollectionLayoutEdgeSpacing spacingForLeading: one top: zero trailing: zero bottom: zero]];
        DIFF(item(10), spaced, @"item edge spacing");
        Item *noSpacing = item(10);
        [noSpacing setEdgeSpacing: nil];
        DIFF(item(10), noSpacing, @"an item without edge spacing");
        DIFF(item(10), [Item itemWithLayoutSize: size(10, 20) supplementaryItems: @[supp(@"k", 0)]], @"item supplementary items");
        expect(![item(10) isEqual: nil] && ![item(10) isEqual: [NSNull null]] && ![item(10) isEqual: @"x"], @"an item is not equal to nil or other classes");

        // quirk: an item takes a group or a supplementary item with the same item properties as equal, not the other way round.
        Group *oneGroup = [Group horizontalGroupWithLayoutSize: size(10, 20) subitems: @[item(1)]];
        expect([item(10) isEqual: oneGroup] && ![oneGroup isEqual: item(10)], @"quirk: an item is equal to a group with its properties, not vice versa (macOS 26.7.3)");
        Supp *sameSizeSupp = [Supp supplementaryItemWithLayoutSize: size(10, 20) elementKind: @"k" containerAnchor: anchor(NSDirectionalRectEdgeTop)];
        expect([item(10) isEqual: sameSizeSupp] && ![sameSizeSupp isEqual: item(10)],
               @"quirk: an item is equal to a supplementary item with its properties, not vice versa (macOS 26.7.3)");
        DIFF(item(10), [Decoration backgroundDecorationItemWithElementKind: @"k"], @"an item and a decoration item");

        // quirk: the hash is not overridden; equal items have different hashes.
        Item *a = item(10), *b = item(10);
        expect([a isEqual: b] && [a hash] != [b hash], @"quirk: equal items do not have equal hashes (macOS 26.7.3)");
        expect([a hash] == [a hash], @"an item's hash is stable");

        // Supplementary items.
        SAME(supp(@"k", 1), supp(@"k", 1), @"supplementary items built alike");
        DIFF(supp(@"k", 1), supp(@"k", 2), @"supplementary z index");
        DIFF(supp(@"k", 1), supp(@"j", 1), @"supplementary element kind");
        Supp *other = [Supp supplementaryItemWithLayoutSize: size(1, 1) elementKind: @"k" containerAnchor: anchor(NSDirectionalRectEdgeBottom)];
        [other setZIndex: 1];
        DIFF(supp(@"k", 1), other, @"supplementary container anchor");
        Supp *withItemAnchor = [Supp supplementaryItemWithLayoutSize: size(1, 1) elementKind: @"k" containerAnchor: anchor(NSDirectionalRectEdgeTop) itemAnchor: anchor(NSDirectionalRectEdgeLeading)];
        [withItemAnchor setZIndex: 1];
        DIFF(supp(@"k", 1), withItemAnchor, @"supplementary item anchor");
        SAME(supp(@"k", 1), [[supp(@"k", 1) copy] autorelease], @"a supplementary item and its copy");
        Supp *inset = supp(@"k", 1);
        [inset setContentInsets: NSDirectionalEdgeInsetsMake(1, 0, 0, 0)];
        DIFF(supp(@"k", 1), inset, @"supplementary content insets");

        // Boundary supplementary items.
        SAME(boundary(@"k", NSRectAlignmentTop), boundary(@"k", NSRectAlignmentTop), @"boundary items built alike");
        DIFF(boundary(@"k", NSRectAlignmentTop), boundary(@"k", NSRectAlignmentBottom), @"boundary alignment");
        DIFF(boundary(@"k", NSRectAlignmentTop), boundary(@"j", NSRectAlignmentTop), @"boundary element kind");
        Boundary *extends = boundary(@"k", NSRectAlignmentTop), *pinned = boundary(@"k", NSRectAlignmentTop), *z = boundary(@"k", NSRectAlignmentTop);
        [extends setExtendsBoundary: ![extends extendsBoundary]];
        [pinned setPinToVisibleBounds: YES];
        [z setZIndex: 3];
        DIFF(boundary(@"k", NSRectAlignmentTop), extends, @"boundary extends boundary");
        DIFF(boundary(@"k", NSRectAlignmentTop), pinned, @"boundary pin to visible bounds");
        DIFF(boundary(@"k", NSRectAlignmentTop), z, @"boundary z index");
        DIFF(boundary(@"k", NSRectAlignmentTop),
             [Boundary boundarySupplementaryItemWithLayoutSize: size(1, 1) elementKind: @"k" alignment: NSRectAlignmentTop absoluteOffset: NSMakePoint(1, 0)], @"boundary offset");
        SAME(boundary(@"k", NSRectAlignmentTop), [[boundary(@"k", NSRectAlignmentTop) copy] autorelease], @"a boundary item and its copy");
        DIFF(boundary(@"k", NSRectAlignmentTop), supp(@"k", 0), @"a boundary item and a plain supplementary item");

        // Decoration items.
        SAME([Decoration backgroundDecorationItemWithElementKind: @"k"], [Decoration backgroundDecorationItemWithElementKind: @"k"], @"decoration items built alike");
        DIFF([Decoration backgroundDecorationItemWithElementKind: @"k"], [Decoration backgroundDecorationItemWithElementKind: @"j"], @"decoration element kind");
        Decoration *layered = [Decoration backgroundDecorationItemWithElementKind: @"k"];
        [layered setZIndex: 2];
        DIFF([Decoration backgroundDecorationItemWithElementKind: @"k"], layered, @"decoration z index");

        // Groups.
        SAME(group(@[item(10)]), group(@[item(10)]), @"groups built alike");
        SAME(group(@[item(10)]), [[group(@[item(10)]) copy] autorelease], @"a group and its copy");
        DIFF(group(@[item(10)]), group(@[item(11)]), @"group subitem size");
        DIFF(group(@[item(10)]), group(@[item(10), item(10)]), @"group subitem count");
        DIFF(group(@[item(1), item(2)]), group(@[item(2), item(1)]), @"group subitem order");
        DIFF(group(@[item(10)]), [Group verticalGroupWithLayoutSize: size(100, 50) subitems: @[item(10)]], @"group direction");
        DIFF(group(@[item(10)]), [Group horizontalGroupWithLayoutSize: size(101, 50) subitems: @[item(10)]], @"group size");
        Group *spacingGroup = group(@[item(10)]), *insetGroup = group(@[item(10)]), *noEdge = group(@[item(10)]), *supplemented = group(@[item(10)]);
        [spacingGroup setInterItemSpacing: [Spacing flexibleSpacing: 2]];
        [insetGroup setContentInsets: NSDirectionalEdgeInsetsMake(1, 0, 0, 0)];
        [noEdge setEdgeSpacing: nil];
        [supplemented setSupplementaryItems: @[supp(@"k", 0)]];
        DIFF(group(@[item(10)]), spacingGroup, @"group inter item spacing");
        DIFF(group(@[item(10)]), insetGroup, @"group content insets");
        DIFF(group(@[item(10)]), noEdge, @"group edge spacing");
        DIFF(group(@[item(10)]), supplemented, @"group supplementary items");
        Group *supplementedOrder = group(@[item(1)]), *supplementedReversed = group(@[item(1)]);
        [supplementedOrder setSupplementaryItems: @[supp(@"a", 0), supp(@"b", 0)]];
        [supplementedReversed setSupplementaryItems: @[supp(@"b", 0), supp(@"a", 0)]];
        DIFF(supplementedOrder, supplementedReversed, @"group supplementary item order");
        DIFF([Group horizontalGroupWithLayoutSize: size(100, 50) subitem: item(10) count: 2],
             [Group horizontalGroupWithLayoutSize: size(100, 50) subitem: item(10) count: 3], @"repeating group count");
        SAME([Group horizontalGroupWithLayoutSize: size(100, 50) subitem: item(10) count: 2],
             [Group horizontalGroupWithLayoutSize: size(100, 50) subitem: item(10) count: 2], @"repeating groups built alike");

        // quirk: subitems are compared by the receiver's isEqual:, so a group holding an item is equal to a group holding
        // a group with the same item properties, not the other way round.
        Group *innerGroup = [Group horizontalGroupWithLayoutSize: size(1, 20) subitems: @[item(3)]];
        Group *holdsItem = group(@[item(1)]), *holdsGroup = group(@[innerGroup]);
        expect([holdsItem isEqual: holdsGroup] && ![holdsGroup isEqual: holdsItem],
               @"quirk: group subitems are compared with the receiver's isEqual: (macOS 26.7.3)");

        // quirk: the item provider block of a custom group is not compared; the size is.
        NSArray *(^provider1)(id<NSCollectionLayoutEnvironment>) = ^NSArray *(id<NSCollectionLayoutEnvironment> e) { return @[]; };
        int captured = 7;
        NSArray *(^provider2)(id<NSCollectionLayoutEnvironment>) = [[^NSArray *(id<NSCollectionLayoutEnvironment> e) { return @[@(captured)]; } copy] autorelease];
        Group *custom1 = [Group customGroupWithLayoutSize: size(10, 20) itemProvider: provider1];
        Group *custom2 = [Group customGroupWithLayoutSize: size(10, 20) itemProvider: provider2];
        expect([custom1 isEqual: custom2] && [custom2 isEqual: custom1] && [custom1 isEqual: [[custom1 copy] autorelease]],
               @"quirk: custom groups with different item providers are equal (macOS 26.7.3)");
        DIFF(custom1, [Group customGroupWithLayoutSize: size(11, 20) itemProvider: provider1], @"custom group size");

        // quirk: a custom group item compares by identity.
        NSCollectionLayoutGroupCustomItem *customItem = [NSCollectionLayoutGroupCustomItem customItemWithFrame: NSMakeRect(1, 2, 3, 4) zIndex: 5];
        NSCollectionLayoutGroupCustomItem *customItem2 = [NSCollectionLayoutGroupCustomItem customItemWithFrame: NSMakeRect(1, 2, 3, 4) zIndex: 5];
        expect([customItem isEqual: customItem] && ![customItem isEqual: customItem2] && ![customItem isEqual: [[customItem copy] autorelease]],
               @"quirk: custom group items compare by identity (macOS 26.7.3)");

        // Sections.
        Section *base = [Section sectionWithGroup: group(@[item(10)])];
        SAME(base, [Section sectionWithGroup: group(@[item(10)])], @"sections built alike");
        SAME(base, [[base copy] autorelease], @"a section and its copy");
        DIFF(base, [Section sectionWithGroup: group(@[item(11)])], @"section group");
        Section *s1 = [Section sectionWithGroup: group(@[item(10)])], *s2 = [Section sectionWithGroup: group(@[item(10)])];
        Section *s3 = [Section sectionWithGroup: group(@[item(10)])], *s4 = [Section sectionWithGroup: group(@[item(10)])];
        Section *s5 = [Section sectionWithGroup: group(@[item(10)])], *s6 = [Section sectionWithGroup: group(@[item(10)])];
        [s1 setContentInsets: NSDirectionalEdgeInsetsMake(1, 0, 0, 0)];
        [s2 setInterGroupSpacing: 4];
        [s3 setBoundarySupplementaryItems: @[boundary(@"k", NSRectAlignmentTop)]];
        [s4 setSupplementariesFollowContentInsets: ![s4 supplementariesFollowContentInsets]];
        [s5 setDecorationItems: @[[Decoration backgroundDecorationItemWithElementKind: @"k"]]];
        [s6 setOrthogonalScrollingBehavior: NSCollectionLayoutSectionOrthogonalScrollingBehaviorContinuous];
        DIFF(base, s1, @"section content insets");
        DIFF(base, s2, @"section inter group spacing");
        DIFF(base, s3, @"section boundary supplementary items");
        DIFF(base, s4, @"section supplementaries follow content insets");
        DIFF(base, s5, @"section decoration items");
        DIFF(base, s6, @"section orthogonal scrolling behavior");

        // quirk: the invalidation handler is compared only for being set: two different handlers are equal, a handler and
        // none are not.
        Section *h1 = [Section sectionWithGroup: group(@[item(10)])], *h2 = [Section sectionWithGroup: group(@[item(10)])];
        [h1 setVisibleItemsInvalidationHandler: ^(NSArray<id<NSCollectionLayoutVisibleItem>> *items, NSPoint offset, id<NSCollectionLayoutEnvironment> env) {}];
        [h2 setVisibleItemsInvalidationHandler: ^(NSArray<id<NSCollectionLayoutVisibleItem>> *items, NSPoint offset, id<NSCollectionLayoutEnvironment> env) { (void) captured; }];
        expect([h1 isEqual: h2] && [h2 isEqual: h1] && [h1 isEqual: [[h1 copy] autorelease]],
               @"quirk: sections with different invalidation handlers are equal (macOS 26.7.3)");
        DIFF(base, h1, @"a section with and without an invalidation handler");
        expect(![base isEqual: nil] && ![base isEqual: group(@[item(10)])], @"a section is not equal to nil or a group");
        expect([base hash] != [[Section sectionWithGroup: group(@[item(10)])] hash] && [base isEqual: [Section sectionWithGroup: group(@[item(10)])]],
               @"quirk: equal sections do not have equal hashes (macOS 26.7.3)");

        // quirk: the compositional layout configuration compares by identity, and is not equal to its copy.
        NSCollectionViewCompositionalLayoutConfiguration *config = [[[NSCollectionViewCompositionalLayoutConfiguration alloc] init] autorelease];
        NSCollectionViewCompositionalLayoutConfiguration *config2 = [[[NSCollectionViewCompositionalLayoutConfiguration alloc] init] autorelease];
        expect([config isEqual: config] && ![config isEqual: config2] && ![config isEqual: [[config copy] autorelease]],
               @"quirk: the layout configuration compares by identity (macOS 26.7.3)");
    }
    printf("PASS: collection layout equality\n");
    return 0;
}
