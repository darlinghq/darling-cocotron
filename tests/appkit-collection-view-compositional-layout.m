#import "appkit-collection-layout.h"

// NSCollectionViewCompositionalLayout, its configuration and NSCollectionViewFlowLayoutInvalidationContext
// (macOS 10.15): the layout objects Notes, Podcasts and Activity Monitor create. Unlike the NSCollectionLayout*
// data classes the layout and its configuration are AppKit's own, so they must not come from CollectionViewCore.
// The invalidation context is declared by AppKit but implemented with the other collection view layout classes in
// UIFoundation.

static void expectFromAppKit(Class cls) {
    const char *image = cls != Nil ? class_getImageName(cls) : NULL;
    expect(image != NULL && strstr(image, "/AppKit.framework/") != NULL,
           [NSString stringWithFormat: @"%s is defined by AppKit (image: %s)",
                                       cls != Nil ? class_getName(cls) : "(missing class)", image ? image : "none"]);
}

int main(void) {
    @autoreleasepool {
        Class layoutClass = NSClassFromString(@"NSCollectionViewCompositionalLayout");
        Class configurationClass = NSClassFromString(@"NSCollectionViewCompositionalLayoutConfiguration");
        Class contextClass = NSClassFromString(@"NSCollectionViewFlowLayoutInvalidationContext");
        Class sectionClass = NSClassFromString(@"NSCollectionLayoutSection");
        Class groupClass = NSClassFromString(@"NSCollectionLayoutGroup");
        Class itemClass = NSClassFromString(@"NSCollectionLayoutItem");
        Class sizeClass = NSClassFromString(@"NSCollectionLayoutSize");
        Class dimensionClass = NSClassFromString(@"NSCollectionLayoutDimension");
        Class boundaryClass = NSClassFromString(@"NSCollectionLayoutBoundarySupplementaryItem");
        expect(layoutClass != Nil && configurationClass != Nil && contextClass != Nil, @"the layout classes exist");
        expectFromAppKit(layoutClass);
        expectFromAppKit(configurationClass);
        expect([layoutClass isSubclassOfClass: [NSCollectionViewLayout class]], @"a compositional layout is a collection view layout");
        expect([contextClass isSubclassOfClass: [NSCollectionViewLayoutInvalidationContext class]],
               @"the flow layout invalidation context is an invalidation context");

        NSCollectionViewFlowLayoutInvalidationContext *context = [[[contextClass alloc] init] autorelease];
        expect([context invalidateFlowLayoutDelegateMetrics] && [context invalidateFlowLayoutAttributes],
               @"quirk: a new flow layout invalidation context invalidates the delegate metrics and the attributes (macOS 26.7.3)");
        [context setInvalidateFlowLayoutDelegateMetrics: NO];
        expect(![context invalidateFlowLayoutDelegateMetrics] && [context invalidateFlowLayoutAttributes], @"the two flags are independent");
        [context setInvalidateFlowLayoutDelegateMetrics: YES];
        [context setInvalidateFlowLayoutAttributes: YES];
        expect([context invalidateFlowLayoutDelegateMetrics] && [context invalidateFlowLayoutAttributes],
               @"the invalidation flags round-trip");

        NSCollectionLayoutSize *fill = [sizeClass sizeWithWidthDimension: [dimensionClass fractionalWidthDimension: 1.0]
                                                         heightDimension: [dimensionClass absoluteDimension: 44]];
        NSCollectionLayoutItem *item = [itemClass itemWithLayoutSize: fill];
        NSCollectionLayoutGroup *group = [groupClass verticalGroupWithLayoutSize: fill subitems: @[item]];
        NSCollectionLayoutSection *section = [sectionClass sectionWithGroup: group];
        NSCollectionLayoutBoundarySupplementaryItem *header = [boundaryClass boundarySupplementaryItemWithLayoutSize: fill
                                                                                                         elementKind: @"header"
                                                                                                           alignment: NSRectAlignmentTop];

        NSCollectionViewCompositionalLayoutConfiguration *configuration = [[[configurationClass alloc] init] autorelease];
        expect([configuration scrollDirection] == NSCollectionViewScrollDirectionVertical && [configuration interSectionSpacing] == 0 &&
                       [configuration boundarySupplementaryItems] == nil,
               @"quirk: a configuration starts vertical, without spacing and with nil boundary items (macOS 26.7.3)");
        [configuration setBoundarySupplementaryItems: @[header]];
        [configuration setBoundarySupplementaryItems: nil];
        expect([configuration boundarySupplementaryItems] == nil, @"quirk: nil boundary items are stored as nil, no exception (macOS 26.7.3)");
        [configuration setScrollDirection: NSCollectionViewScrollDirectionHorizontal];
        [configuration setInterSectionSpacing: 14];
        [configuration setBoundarySupplementaryItems: @[header]];
        NSCollectionViewCompositionalLayoutConfiguration *configurationCopy = [[configuration copy] autorelease];
        expect(configurationCopy != configuration && [configurationCopy scrollDirection] == NSCollectionViewScrollDirectionHorizontal &&
                       [configurationCopy interSectionSpacing] == 14 && [[configurationCopy boundarySupplementaryItems] isEqual: @[header]],
               @"a configuration copies with every property");
        [configurationCopy setInterSectionSpacing: 1];
        expect([configuration interSectionSpacing] == 14, @"changing the copy leaves the original alone");

        NSCollectionViewCompositionalLayout *single = [[[layoutClass alloc] initWithSection: section] autorelease];
        expect(single != nil && [single configuration] != nil && [[single configuration] scrollDirection] == NSCollectionViewScrollDirectionVertical,
               @"a layout made from a section has a default configuration");
        NSCollectionViewCompositionalLayout *configured = [[[layoutClass alloc] initWithSection: section configuration: configuration] autorelease];
        expect([[configured configuration] interSectionSpacing] == 14 && [configured configuration] != configuration,
               @"a layout keeps a copy of the configuration it is given");
        [configured setConfiguration: configurationCopy];
        expect([[configured configuration] interSectionSpacing] == 1, @"the configuration can be replaced");

        NSCollectionViewCompositionalLayout *provided = [[[layoutClass alloc]
                initWithSectionProvider: ^NSCollectionLayoutSection *(NSInteger index, id<NSCollectionLayoutEnvironment> environment) {
                    return section;
                }] autorelease];
        expect(provided != nil && [provided configuration] != nil, @"a layout made from a section provider has a default configuration");
        NSCollectionViewCompositionalLayout *providedConfigured = [[[layoutClass alloc]
                initWithSectionProvider: ^NSCollectionLayoutSection *(NSInteger index, id<NSCollectionLayoutEnvironment> environment) {
                    return section;
                }
                          configuration: configuration] autorelease];
        expect([[providedConfigured configuration] scrollDirection] == NSCollectionViewScrollDirectionHorizontal,
               @"a provider layout keeps the configuration it is given");
    }
    printf("PASS: collection view compositional layout\n");
    return 0;
}
