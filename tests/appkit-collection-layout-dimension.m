#import "appkit-collection-layout.h"

// NSCollectionLayoutDimension and NSCollectionLayoutSize (NSCollectionViewCompositionalLayout.h, macOS 10.15): the
// dimension kinds and the size built from two of them.

int main(void) {
    @autoreleasepool {
        Class dimensionClass = NSClassFromString(@"NSCollectionLayoutDimension");
        Class sizeClass = NSClassFromString(@"NSCollectionLayoutSize");
        expect(dimensionClass != Nil, @"NSCollectionLayoutDimension exists");
        expect(sizeClass != Nil, @"NSCollectionLayoutSize exists");
        expectFromCollectionViewCore(dimensionClass);
        expectFromCollectionViewCore(sizeClass);

        NSCollectionLayoutDimension *width = [dimensionClass fractionalWidthDimension: 0.25];
        expect([width isFractionalWidth] && ![width isFractionalHeight] && ![width isAbsolute] && ![width isEstimated],
               @"a fractional width dimension is only that kind");
        expect([width dimension] == 0.25, @"the fractional width keeps its value");

        NSCollectionLayoutDimension *height = [dimensionClass fractionalHeightDimension: 1.0];
        expect([height isFractionalHeight] && ![height isFractionalWidth] && ![height isAbsolute] && ![height isEstimated],
               @"a fractional height dimension is only that kind");
        expect([height dimension] == 1.0, @"the fractional height keeps its value");

        NSCollectionLayoutDimension *absolute = [dimensionClass absoluteDimension: 44.5];
        expect([absolute isAbsolute] && ![absolute isEstimated] && ![absolute isFractionalWidth] && ![absolute isFractionalHeight],
               @"an absolute dimension is only that kind");
        expect([absolute dimension] == 44.5, @"the absolute dimension keeps its value");

        NSCollectionLayoutDimension *estimated = [dimensionClass estimatedDimension: 120];
        expect([estimated isEstimated] && ![estimated isAbsolute] && ![estimated isFractionalWidth] && ![estimated isFractionalHeight],
               @"an estimated dimension is only that kind");
        expect([estimated dimension] == 120, @"the estimated dimension keeps its value");

        NSCollectionLayoutDimension *copied = [[absolute copy] autorelease];
        expect([copied isAbsolute] && [copied dimension] == 44.5, @"a copy answers like the original");

        NSCollectionLayoutSize *size = [sizeClass sizeWithWidthDimension: width heightDimension: estimated];
        expect([size widthDimension] == width, @"the size keeps its width dimension");
        expect([size heightDimension] == estimated, @"the size keeps its height dimension");
        NSCollectionLayoutSize *copiedSize = [[size copy] autorelease];
        expect([[copiedSize widthDimension] dimension] == 0.25 && [[copiedSize heightDimension] isEstimated],
               @"a copied size answers like the original");
    }
    printf("PASS: collection layout dimension and size\n");
    return 0;
}
