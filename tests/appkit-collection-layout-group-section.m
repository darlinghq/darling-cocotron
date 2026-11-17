#import "appkit-collection-layout.h"

// NSCollectionLayoutGroup and NSCollectionLayoutSection (NSCollectionViewCompositionalLayout.h, macOS 10.15): the
// composite objects Notes, Podcasts and Activity Monitor build their layouts from.

static int gHandlerSaw;

// Installs a block that captures a local, so the literal is a stack block that dies when this function returns.
// The section has to copy it to the heap: a retain would keep a pointer to a dead frame. Reports where the stack block was.
__attribute__((noinline)) static void installStackHandler(NSCollectionLayoutSection *section, int token, void **stackAddress) {
    NSCollectionLayoutSectionVisibleItemsInvalidationHandler stackHandler =
            ^(NSArray<id<NSCollectionLayoutVisibleItem>> *items, NSPoint offset, id<NSCollectionLayoutEnvironment> environment) {
                gHandlerSaw = token;
            };
    *stackAddress = (void *) stackHandler;
    [section setVisibleItemsInvalidationHandler: stackHandler];
}

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
        NSCollectionLayoutSize *otherSize = [sizeClass sizeWithWidthDimension: [dimensionClass absoluteDimension: 7]
                                                              heightDimension: [dimensionClass absoluteDimension: 9]];
        NSCollectionLayoutItem *other = [itemClass itemWithLayoutSize: otherSize];

        NSCollectionLayoutGroup *horizontal = [groupClass horizontalGroupWithLayoutSize: fill subitems: @[item, other]];
        expect(sameSize([horizontal layoutSize], fill), @"the group keeps its layout size");
        expect(sameItemSizes([horizontal subitems], @[item, other]), @"the group keeps its subitems in order");
        expect([[horizontal interItemSpacing] isFixedSpacing] && [[horizontal interItemSpacing] spacing] == 0,
               @"quirk: inter item spacing starts as fixed zero spacing (macOS 26.7.3)");

        // quirk: a repeating group holds one copy of the subitem, resized along the group's direction to 1 / count; a count
        // below 1 raises (macOS 26.7.3).
        NSCollectionLayoutSize *absoluteSize = [sizeClass sizeWithWidthDimension: [dimensionClass absoluteDimension: 10]
                                                                 heightDimension: [dimensionClass estimatedDimension: 20]];
        NSCollectionLayoutItem *absoluteItem = [itemClass itemWithLayoutSize: absoluteSize];
        NSCollectionLayoutGroup *counted = [groupClass verticalGroupWithLayoutSize: fill subitem: absoluteItem count: 3];
        expect([[counted subitems] count] == 1, @"quirk: a repeating group has one subitem (macOS 26.7.3)");
        NSCollectionLayoutSize *countedSize = [[[counted subitems] objectAtIndex: 0] layoutSize];
        expect([[countedSize widthDimension] isAbsolute] && [[countedSize widthDimension] dimension] == 10 &&
                       [[countedSize heightDimension] isFractionalHeight] && fabs([[countedSize heightDimension] dimension] - 1.0 / 3) < 1e-6,
               @"quirk: a vertical repeating group's subitem is 1 / count of its height (macOS 26.7.3)");
        NSCollectionLayoutGroup *countedHorizontal = [groupClass horizontalGroupWithLayoutSize: fill subitem: absoluteItem count: 4];
        countedSize = [[[countedHorizontal subitems] objectAtIndex: 0] layoutSize];
        expect([[countedSize widthDimension] isFractionalWidth] && [[countedSize widthDimension] dimension] == 0.25 &&
                       [[countedSize heightDimension] isEstimated] && [[countedSize heightDimension] dimension] == 20,
               @"quirk: a horizontal repeating group's subitem is 1 / count of its width (macOS 26.7.3)");
        expect([[absoluteItem layoutSize] widthDimension].isAbsolute, @"the given subitem is not changed");
        expect([[[counted copy] autorelease] subitems].count == 1, @"a repeating group's copy keeps it");
        NSString *zeroName = nil, *negativeName = nil;
        @try { [groupClass horizontalGroupWithLayoutSize: fill subitem: item count: 0]; } @catch (NSException *e) { zeroName = [e name]; }
        @try { [groupClass verticalGroupWithLayoutSize: fill subitem: item count: -1]; } @catch (NSException *e) { negativeName = [e name]; }
        expect([zeroName isEqualToString: NSInternalInconsistencyException] && [negativeName isEqualToString: NSInternalInconsistencyException],
               @"a repeating group with a count below 1 raises NSInternalInconsistencyException (macOS 26.7.3)");

        NSCollectionLayoutSpacing *gap = [spacingClass fixedSpacing: 6];
        [horizontal setInterItemSpacing: gap];
        expect([[horizontal interItemSpacing] spacing] == 6 && [[horizontal interItemSpacing] isFixedSpacing],
               @"inter item spacing round-trips");
        [horizontal setContentInsets: NSDirectionalEdgeInsetsMake(1, 2, 3, 4)];
        NSCollectionLayoutGroup *copy = [[horizontal copy] autorelease];
        expect([copy isMemberOfClass: groupClass] && copy != horizontal, @"a group copies to a new group");
        expect(sameItemSizes([copy subitems], @[item, other]) && [[copy interItemSpacing] spacing] == 6 &&
                       sameSize([copy layoutSize], fill) && [copy contentInsets].trailing == 4,
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
        expect([horizontal supplementaryItems] == nil, @"quirk: nil supplementary items on a group are stored as nil, no exception (macOS 26.7.3)");
        [horizontal setSupplementaryItems: @[]];

        // A group needs a subitem: none, nil and a nil repeated subitem raise.
        NSString *emptyName = nil, *nilName = nil, *nilRepeatName = nil, *nilGroupName = nil;
        @try { [groupClass horizontalGroupWithLayoutSize: fill subitems: @[]]; } @catch (NSException *e) { emptyName = [e name]; }
        @try { [groupClass verticalGroupWithLayoutSize: fill subitems: nil]; } @catch (NSException *e) { nilName = [e name]; }
        @try { [groupClass horizontalGroupWithLayoutSize: fill subitem: nil count: 2]; } @catch (NSException *e) { nilRepeatName = [e name]; }
        @try { [sectionClass sectionWithGroup: nil]; } @catch (NSException *e) { nilGroupName = [e name]; }
        expect([emptyName isEqualToString: NSInternalInconsistencyException] && [nilName isEqualToString: NSInternalInconsistencyException],
               @"a group without subitems raises NSInternalInconsistencyException (macOS 26.7.3)");
        expect([nilRepeatName isEqualToString: NSInvalidArgumentException], @"a nil repeated subitem raises NSInvalidArgumentException (macOS 26.7.3)");
        expect([nilGroupName isEqualToString: NSInternalInconsistencyException], @"a section without a group raises NSInternalInconsistencyException (macOS 26.7.3)");
        // The description is a debugging aid whose format is not specified, so only what must hold of any format is
        // checked: a group and its copy are described alike, and the direction shows in the description.
        NSCollectionLayoutSize *box = [sizeClass sizeWithWidthDimension: [dimensionClass absoluteDimension: 40]
                                                        heightDimension: [dimensionClass absoluteDimension: 40]];
        NSCollectionLayoutGroup *boxVertical = [groupClass verticalGroupWithLayoutSize: box subitems: @[other, other]];
        NSCollectionLayoutGroup *boxHorizontal = [groupClass horizontalGroupWithLayoutSize: box subitems: @[other, other]];
        expect([[boxVertical visualDescription] length] > 0 &&
                       [[[[boxVertical copy] autorelease] visualDescription] isEqualToString: [boxVertical visualDescription]] &&
                       ![[boxVertical visualDescription] isEqualToString: [boxHorizontal visualDescription]],
               @"a group's copy keeps its direction, and the description tells the directions apart");

        // quirk: a custom group has no subitems, keeps the provider without calling it at creation, and a nil layout size
        // or provider raises NSInternalInconsistencyException (macOS 26.7.3 and 27.0.1).
        Class customItemClass = NSClassFromString(@"NSCollectionLayoutGroupCustomItem");
        expect(customItemClass != Nil, @"the custom item class exists");
        expectFromCollectionViewCore(customItemClass);
        __block int providerCalls = 0;
        NSCollectionLayoutGroup *custom = [groupClass customGroupWithLayoutSize: fill
                                                                   itemProvider: ^NSArray *(id<NSCollectionLayoutEnvironment> environment) {
                                                                       providerCalls++;
                                                                       return @[];
                                                                   }];
        expect([custom isKindOfClass: groupClass] && sameSize([custom layoutSize], fill), @"quirk: a custom group is a group with the layout size (macOS 26.7.3)");
        expect(providerCalls == 0, @"quirk: the provider is not called when a custom group is made (macOS 26.7.3)");
        expect([custom subitems] != nil && [[custom subitems] count] == 0, @"quirk: a custom group has an empty subitems array (macOS 26.7.3)");
        expect([[custom supplementaryItems] isEqual: @[]], @"a custom group has no supplementary items");
        expect([[custom interItemSpacing] isFixedSpacing] && [[custom interItemSpacing] spacing] == 0, @"quirk: a custom group's inter item spacing is fixed zero (macOS 26.7.3)");
        expect([custom edgeSpacing] != nil, @"a custom group has an edge spacing");
        NSDirectionalEdgeInsets customInsets = [custom contentInsets];
        expect(customInsets.top == 0 && customInsets.leading == 0 && customInsets.bottom == 0 && customInsets.trailing == 0, @"a custom group's insets are zero");
        expect(providerCalls == 0, @"the provider is not called by reading a custom group's properties (macOS 26.7.3)");
        // macOS calls the provider from -visualDescription, which is a debugging aid; whether the provider is called there is not pinned.
        expect([[custom visualDescription] length] > 0, @"a custom group has a description");
        NSCollectionLayoutGroup *customCopy = [[custom copy] autorelease];
        expect(customCopy != custom && [customCopy isKindOfClass: groupClass] && [[customCopy subitems] count] == 0 &&
                       sameSize([customCopy layoutSize], fill),
               @"a custom group's copy is a new custom group");
        [custom setInterItemSpacing: [spacingClass fixedSpacing: 5]];
        expect([[custom interItemSpacing] spacing] == 5, @"a custom group's inter item spacing is settable");
        expect([sectionClass sectionWithGroup: custom] != nil, @"a custom group makes a section");
        NSCollectionLayoutGroupCustomItemProvider emptyProvider = ^NSArray *(id<NSCollectionLayoutEnvironment> environment) { return @[]; };
        NSString *nilSizeName = nil, *nilProviderName = nil, *nilBothName = nil;
        @try { [groupClass customGroupWithLayoutSize: nil itemProvider: emptyProvider]; } @catch (NSException *e) { nilSizeName = [e name]; }
        @try { [groupClass customGroupWithLayoutSize: fill itemProvider: nil]; } @catch (NSException *e) { nilProviderName = [e name]; }
        @try { [groupClass customGroupWithLayoutSize: nil itemProvider: nil]; } @catch (NSException *e) { nilBothName = [e name]; }
        expect([nilSizeName isEqualToString: NSInternalInconsistencyException], @"quirk: a custom group without a layout size raises NSInternalInconsistencyException (macOS 26.7.3)");
        expect([nilProviderName isEqualToString: NSInternalInconsistencyException], @"quirk: a custom group without a provider raises NSInternalInconsistencyException (macOS 26.7.3)");
        expect([nilBothName isEqualToString: NSInternalInconsistencyException], @"a custom group without either raises NSInternalInconsistencyException");

        // The custom item: an immutable frame and zIndex (default 0). quirk: equality is identity, and a copy is a new,
        // unequal object (macOS 26.7.3 and 27.0.1).
        NSCollectionLayoutGroupCustomItem *plain = [customItemClass customItemWithFrame: NSMakeRect(1, 2, 3, 4)];
        NSCollectionLayoutGroupCustomItem *layered = [customItemClass customItemWithFrame: NSMakeRect(1, 2, 3, 4) zIndex: 5];
        expect(NSEqualRects([plain frame], NSMakeRect(1, 2, 3, 4)) && [plain zIndex] == 0, @"a custom item keeps its frame and has zIndex 0 by default");
        expect(NSEqualRects([layered frame], NSMakeRect(1, 2, 3, 4)) && [layered zIndex] == 5, @"a custom item keeps its zIndex");
        expect([[customItemClass customItemWithFrame: NSMakeRect(0, 0, 1, 1) zIndex: -3] zIndex] == -3, @"a custom item's zIndex may be negative");
        expect([plain conformsToProtocol: @protocol(NSCopying)] && ![plain respondsToSelector: @selector(setFrame:)] &&
                       ![plain respondsToSelector: @selector(setZIndex:)],
               @"a custom item is copyable and immutable");
        NSCollectionLayoutGroupCustomItem *layeredCopy = [[layered copy] autorelease];
        expect(layeredCopy != layered && NSEqualRects([layeredCopy frame], [layered frame]) && [layeredCopy zIndex] == 5,
               @"a custom item's copy is a new item with the same frame and zIndex");
        expect(![layeredCopy isEqual: layered] && ![plain isEqual: [customItemClass customItemWithFrame: NSMakeRect(1, 2, 3, 4)]] &&
                       [plain isEqual: plain],
               @"quirk: custom items are equal only to themselves (macOS 26.7.3)");

        NSCollectionLayoutSection *section = [sectionClass sectionWithGroup: horizontal];
        NSDirectionalEdgeInsets zero = [section contentInsets];
        expect(zero.top == 0 && zero.leading == 0 && zero.bottom == 0 && zero.trailing == 0, @"section insets start at zero");
        expect([section interGroupSpacing] == 0, @"inter group spacing starts at zero");
        expect([[section boundarySupplementaryItems] isEqual: @[]] && [[section decorationItems] isEqual: @[]],
               @"a section starts with empty boundary and decoration item arrays, not nil");
        expect([section supplementariesFollowContentInsets], @"supplementaries follow content insets by default (macOS 26.7.3)");

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

        // A handler copied to the heap outlives the stack block it was made from; one that is only retained does not.
        void *stackAddress = NULL;
        installStackHandler(section, 41, &stackAddress);
        expect(stackAddress != NULL && (void *) [section visibleItemsInvalidationHandler] != stackAddress,
               @"the section holds a heap copy of the handler, not the caller's stack block");
        gHandlerSaw = 0;
        [section visibleItemsInvalidationHandler](@[], NSZeroPoint, nil);
        expect(gHandlerSaw == 41, @"the copied handler still has the value it captured after the installing function returned");

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
        expect([section boundarySupplementaryItems] == nil && [[section decorationItems] isEqual: @[]],
               @"quirk: nil on a section gives nil boundary items and an empty array of decoration items (macOS 26.7.3)");
        NSMutableArray *mutableItems = [NSMutableArray arrayWithObject: header];
        [section setBoundarySupplementaryItems: mutableItems];
        [mutableItems removeAllObjects];
        expect([[section boundarySupplementaryItems] count] == 1, @"the section copies the array it is given");
    }
    printf("PASS: collection layout group and section\n");
    return 0;
}
