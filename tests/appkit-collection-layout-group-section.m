#import "appkit-collection-layout.h"

// NSCollectionLayoutGroup and NSCollectionLayoutSection (NSCollectionViewCompositionalLayout.h, macOS 10.15): the
// composite objects Notes, Podcasts and Activity Monitor build their layouts from.

int main(void) {
    @autoreleasepool {
        Class itemClass = NSClassFromString(@"NSCollectionLayoutItem");
        Class groupClass = NSClassFromString(@"NSCollectionLayoutGroup");
        Class sectionClass = NSClassFromString(@"NSCollectionLayoutSection");
        Class sizeClass = NSClassFromString(@"NSCollectionLayoutSize");
        Class dimensionClass = NSClassFromString(@"NSCollectionLayoutDimension");
        Class spacingClass = NSClassFromString(@"NSCollectionLayoutSpacing");
        Class boundaryClass = NSClassFromString(@"NSCollectionLayoutBoundarySupplementaryItem");
        Class decorationClass = NSClassFromString(@"NSCollectionLayoutDecorationItem");
        expect(groupClass != Nil && sectionClass != Nil, @"the group and section classes exist");
        expectFromCollectionViewCore(groupClass);
        expectFromCollectionViewCore(sectionClass);
        expect([groupClass isSubclassOfClass: itemClass], @"a group is an item");

        NSCollectionLayoutSize *fill = [sizeClass sizeWithWidthDimension: [dimensionClass fractionalWidthDimension: 1.0]
                                                         heightDimension: [dimensionClass fractionalHeightDimension: 1.0]];
        NSCollectionLayoutItem *item = [itemClass itemWithLayoutSize: fill];
        NSCollectionLayoutItem *other = [itemClass itemWithLayoutSize: fill];

        NSCollectionLayoutGroup *horizontal = [groupClass horizontalGroupWithLayoutSize: fill subitems: @[item, other]];
        expect([horizontal layoutSize] == fill, @"the group keeps its layout size");
        expect([[horizontal subitems] isEqual: @[item, other]], @"the group keeps its subitems in order");
        expect([horizontal interItemSpacing] == nil, @"inter item spacing starts nil");

        NSCollectionLayoutGroup *counted = [groupClass verticalGroupWithLayoutSize: fill subitem: item count: 3];
        expect([[counted subitems] count] == 3, @"a counted group repeats its subitem count times");
        for (NSCollectionLayoutItem *subitem in [counted subitems])
            expect(subitem == item, @"every repeated subitem is the given one");
        expect([[groupClass horizontalGroupWithLayoutSize: fill subitem: item count: 0] subitems].count == 0,
               @"a count of zero gives no subitems");

        NSCollectionLayoutSpacing *gap = [spacingClass fixedSpacing: 6];
        [horizontal setInterItemSpacing: gap];
        expect([[horizontal interItemSpacing] spacing] == 6 && [[horizontal interItemSpacing] isFixedSpacing],
               @"inter item spacing round-trips");
        [horizontal setContentInsets: NSDirectionalEdgeInsetsMake(1, 2, 3, 4)];
        NSCollectionLayoutGroup *copy = [[horizontal copy] autorelease];
        expect([copy isMemberOfClass: groupClass] && copy != horizontal, @"a group copies to a new group");
        expect([[copy subitems] isEqual: @[item, other]] && [[copy interItemSpacing] spacing] == 6 &&
                       [copy layoutSize] == fill && [copy contentInsets].trailing == 4,
               @"the copy keeps the subitems, spacing, size and insets");
        [copy setInterItemSpacing: [spacingClass fixedSpacing: 9]];
        expect([[horizontal interItemSpacing] spacing] == 6, @"changing the copy leaves the original alone");

        // Unlike an item's, a group's supplementary items can be set; the group keeps a copy of the array.
        NSCollectionLayoutBoundarySupplementaryItem *tag = [boundaryClass boundarySupplementaryItemWithLayoutSize: fill
                                                                                                      elementKind: @"tag"
                                                                                                        alignment: NSRectAlignmentTop];
        expect([[horizontal supplementaryItems] isEqual: @[]], @"a group has an empty supplementary items array to start with, not nil");
        NSMutableArray *tags = [NSMutableArray arrayWithObject: tag];
        [horizontal setSupplementaryItems: tags];
        [tags removeAllObjects];
        expect([[horizontal supplementaryItems] isEqual: @[tag]], @"a group's supplementary items round-trip as a copy");
        expect([[[[horizontal copy] autorelease] supplementaryItems] isEqual: @[tag]], @"a group's copy keeps them");
        [horizontal setSupplementaryItems: nil];
        expect([[horizontal supplementaryItems] isEqual: @[]], @"setting nil gives the empty array, not nil");
        // A copy is built by the item's copy and then filled in, so the direction has to be copied explicitly; the
        // vertical group is the one that shows it, because a lost direction reads as horizontal.
        NSCollectionLayoutGroup *verticalGroup = [groupClass verticalGroupWithLayoutSize: fill subitems: @[item, other]];
        NSCollectionLayoutGroup *verticalCopy = [[verticalGroup copy] autorelease];
        expect([[verticalCopy visualDescription] containsString: @"vertical"] && [[copy visualDescription] containsString: @"horizontal"],
               @"a group's copy keeps its direction");
        expect([[[groupClass horizontalGroupWithLayoutSize: fill subitems: @[item]] visualDescription] containsString: @"horizontal"] &&
                       [[[groupClass verticalGroupWithLayoutSize: fill subitems: @[item, other]] visualDescription] containsString: @"vertical"] &&
                       [[[groupClass verticalGroupWithLayoutSize: fill subitems: @[item, other]] visualDescription] containsString: @"2 subitems"],
               @"the visual description names the direction and the subitem count");

        BOOL raised = NO;
        @try {
            [groupClass customGroupWithLayoutSize: fill itemProvider: ^NSArray *(id<NSCollectionLayoutEnvironment> environment) { return @[]; }];
        } @catch (NSException *exception) {
            raised = [[exception reason] containsString: @"not implemented"];
        }
        expect(raised, @"a custom group fails loud");

        NSCollectionLayoutSection *section = [sectionClass sectionWithGroup: horizontal];
        NSDirectionalEdgeInsets zero = [section contentInsets];
        expect(zero.top == 0 && zero.leading == 0 && zero.bottom == 0 && zero.trailing == 0, @"section insets start at zero");
        expect([section interGroupSpacing] == 0, @"inter group spacing starts at zero");
        expect([[section boundarySupplementaryItems] isEqual: @[]] && [[section decorationItems] isEqual: @[]],
               @"a section starts with empty boundary and decoration item arrays, not nil");
        expect([section supplementariesFollowContentInsets], @"supplementaries follow content insets by default (GUESS)");

        NSCollectionLayoutBoundarySupplementaryItem *header = [boundaryClass boundarySupplementaryItemWithLayoutSize: fill
                                                                                                         elementKind: @"header"
                                                                                                           alignment: NSRectAlignmentTop];
        NSCollectionLayoutDecorationItem *background = [decorationClass backgroundDecorationItemWithElementKind: @"background"];
        [section setContentInsets: NSDirectionalEdgeInsetsMake(5, 6, 7, 8)];
        [section setInterGroupSpacing: 12];
        [section setBoundarySupplementaryItems: @[header]];
        [section setDecorationItems: @[background]];
        [section setSupplementariesFollowContentInsets: NO];
        NSDirectionalEdgeInsets insets = [section contentInsets];
        expect(insets.top == 5 && insets.leading == 6 && insets.bottom == 7 && insets.trailing == 8, @"section insets round-trip");
        expect([section interGroupSpacing] == 12, @"inter group spacing round-trips");
        expect([[section boundarySupplementaryItems] isEqual: @[header]], @"boundary items round-trip");
        expect([[section decorationItems] isEqual: @[background]], @"decoration items round-trip");
        expect(![section supplementariesFollowContentInsets], @"supplementariesFollowContentInsets round-trips");

        expect([section orthogonalScrollingBehavior] == NSCollectionLayoutSectionOrthogonalScrollingBehaviorNone &&
                       [section visibleItemsInvalidationHandler] == nil,
               @"a section does not scroll orthogonally and has no visible items handler to start with");
        __block int handlerCalls = 0;
        NSCollectionLayoutSectionVisibleItemsInvalidationHandler handler =
                ^(NSArray<id<NSCollectionLayoutVisibleItem>> *items, NSPoint offset, id<NSCollectionLayoutEnvironment> environment) {
                    handlerCalls++;
                };
        [section setOrthogonalScrollingBehavior: NSCollectionLayoutSectionOrthogonalScrollingBehaviorGroupPagingCentered];
        [section setVisibleItemsInvalidationHandler: handler];
        expect([section orthogonalScrollingBehavior] == NSCollectionLayoutSectionOrthogonalScrollingBehaviorGroupPagingCentered,
               @"the scrolling behavior round-trips");
        [section visibleItemsInvalidationHandler](@[], NSZeroPoint, nil);
        expect(handlerCalls == 1, @"the handler comes back and runs");

        NSCollectionLayoutSection *sectionCopy = [[section copy] autorelease];
        expect([sectionCopy orthogonalScrollingBehavior] == NSCollectionLayoutSectionOrthogonalScrollingBehaviorGroupPagingCentered &&
                       [sectionCopy visibleItemsInvalidationHandler] != nil,
               @"the copy keeps the scrolling behavior and the handler");
        expect([sectionCopy isMemberOfClass: sectionClass] && sectionCopy != section, @"a section copies to a new section");
        expect([sectionCopy contentInsets].leading == 6 && [sectionCopy interGroupSpacing] == 12 &&
                       [[sectionCopy boundarySupplementaryItems] isEqual: @[header]] &&
                       [[sectionCopy decorationItems] isEqual: @[background]] && ![sectionCopy supplementariesFollowContentInsets],
               @"the copy keeps every property");
        [sectionCopy setInterGroupSpacing: 1];
        expect([section interGroupSpacing] == 12, @"changing the copy leaves the original alone");

        [section setBoundarySupplementaryItems: nil];
        [section setDecorationItems: nil];
        expect([[section boundarySupplementaryItems] isEqual: @[]] && [[section decorationItems] isEqual: @[]],
               @"setting nil gives empty arrays");
        NSMutableArray *mutableItems = [NSMutableArray arrayWithObject: header];
        [section setBoundarySupplementaryItems: mutableItems];
        [mutableItems removeAllObjects];
        expect([[section boundarySupplementaryItems] count] == 1, @"the section copies the array it is given");
    }
    printf("PASS: collection layout group and section\n");
    return 0;
}
