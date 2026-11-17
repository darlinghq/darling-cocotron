#import "appkit-collection-layout.h"

// NSCollectionLayoutSpacing, NSCollectionLayoutEdgeSpacing and NSCollectionLayoutAnchor
// (NSCollectionViewCompositionalLayout.h, macOS 10.15).

int main(void) {
    @autoreleasepool {
        Class spacingClass = NSClassFromString(@"NSCollectionLayoutSpacing");
        Class edgeClass = NSClassFromString(@"NSCollectionLayoutEdgeSpacing");
        Class anchorClass = NSClassFromString(@"NSCollectionLayoutAnchor");
        expect(spacingClass != Nil && edgeClass != Nil && anchorClass != Nil, @"the three classes exist");
        expectFromCollectionViewCore(spacingClass);
        expectFromCollectionViewCore(edgeClass);
        expectFromCollectionViewCore(anchorClass);

        NSCollectionLayoutSpacing *flexible = [spacingClass flexibleSpacing: 8];
        expect([flexible isFlexibleSpacing] && ![flexible isFixedSpacing] && [flexible spacing] == 8,
               @"a flexible spacing is flexible and keeps its value");
        NSCollectionLayoutSpacing *fixed = [spacingClass fixedSpacing: 3];
        expect([fixed isFixedSpacing] && ![fixed isFlexibleSpacing] && [fixed spacing] == 3,
               @"a fixed spacing is fixed and keeps its value");
        NSCollectionLayoutSpacing *fixedCopy = [[fixed copy] autorelease];
        expect(fixedCopy != nil && [fixedCopy spacing] == 3 && [fixedCopy isFixedSpacing], @"a spacing copies");

        NSCollectionLayoutEdgeSpacing *edges = [edgeClass spacingForLeading: flexible top: nil trailing: fixed bottom: nil];
        expect([edges leading] == flexible, @"the leading spacing is kept (not swapped with trailing)");
        expect([edges trailing] == fixed, @"the trailing spacing is kept");
        expect([edges top] == nil && [edges bottom] == nil, @"omitted edges stay nil");
        NSCollectionLayoutEdgeSpacing *edgesBottom = [edgeClass spacingForLeading: nil top: fixed trailing: nil bottom: flexible];
        expect([edgesBottom top] == fixed && [edgesBottom bottom] == flexible, @"top and bottom are kept in their own slots");
        NSCollectionLayoutEdgeSpacing *edgesCopy = [[edges copy] autorelease];
        expect([edgesCopy leading] == flexible && [edgesCopy trailing] == fixed, @"edge spacing copies");

        NSDirectionalRectEdge both = NSDirectionalRectEdgeTop | NSDirectionalRectEdgeTrailing;
        NSCollectionLayoutAnchor *plain = [anchorClass layoutAnchorWithEdges: both];
        expect([plain edges] == both && [plain offset].x == 0 && [plain offset].y == 0, @"an anchor keeps its edges and has no offset");
        expect([plain isAbsoluteOffset] && ![plain isFractionalOffset],
               @"quirk: an anchor without an offset reports an absolute offset (macOS 26.7.3)");
        NSCollectionLayoutAnchor *plainNone = [anchorClass layoutAnchorWithEdges: NSDirectionalRectEdgeNone];
        expect([plainNone edges] == NSDirectionalRectEdgeNone && [plainNone isAbsoluteOffset] && ![plainNone isFractionalOffset],
               @"quirk: an anchor without edges or offset reports an absolute offset (macOS 26.7.3)");

        NSCollectionLayoutAnchor *absolute = [anchorClass layoutAnchorWithEdges: NSDirectionalRectEdgeBottom absoluteOffset: NSMakePoint(4, -6)];
        expect([absolute isAbsoluteOffset] && ![absolute isFractionalOffset], @"an absolute offset is absolute");
        expect([absolute offset].x == 4 && [absolute offset].y == -6 && [absolute edges] == NSDirectionalRectEdgeBottom,
               @"the absolute offset and edges are kept");

        NSCollectionLayoutAnchor *fractional = [anchorClass layoutAnchorWithEdges: NSDirectionalRectEdgeLeading fractionalOffset: NSMakePoint(0.5, -0.5)];
        expect([fractional isFractionalOffset] && ![fractional isAbsoluteOffset], @"a fractional offset is fractional");
        expect([fractional offset].x == 0.5 && [fractional offset].y == -0.5, @"the fractional offset is kept");
        NSCollectionLayoutAnchor *fractionalCopy = [[fractional copy] autorelease];
        expect(fractionalCopy != nil && [fractionalCopy isFractionalOffset] && [fractionalCopy offset].x == 0.5, @"an anchor copies");

        expect(NSDirectionalRectEdgeAll == (NSDirectionalRectEdgeTop | NSDirectionalRectEdgeLeading | NSDirectionalRectEdgeBottom | NSDirectionalRectEdgeTrailing),
               @"the all-edges mask is the four edges");
    }
    printf("PASS: collection layout spacing and anchor\n");
    return 0;
}
