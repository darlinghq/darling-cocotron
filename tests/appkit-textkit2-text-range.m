/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * NSTextRange arithmetic over NSTextLocation values, the content storage's
 * document range and the layout manager's attachment to a content manager.
 * No window server needed.
 */
#import <AppKit/AppKit.h>
#include <stdio.h>

@interface TestLocation : NSObject <NSTextLocation> {
    NSInteger _value; // the legacy 32-bit runtime does not synthesize properties
}
@property NSInteger value;
+ (instancetype) at: (NSInteger) value;
@end

@implementation TestLocation
@synthesize value = _value;
+ (instancetype) at: (NSInteger) value
{
    TestLocation *location = [[TestLocation alloc] init];
    location.value = value;
    return location;
}
- (NSComparisonResult) compare: (id<NSTextLocation>) other
{
    NSInteger otherValue = ((TestLocation *) other).value;
    return _value < otherValue ? NSOrderedAscending : _value > otherValue ? NSOrderedDescending : NSOrderedSame;
}
@end

static int failures;

static void expect(BOOL ok, const char *what)
{
    if (!ok) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

static NSTextRange *range(NSInteger from, NSInteger to)
{
    return [[NSTextRange alloc] initWithLocation: [TestLocation at: from] endLocation: [TestLocation at: to]];
}

int main(void)
{
    @autoreleasepool {
        NSTextRange *a = range(2, 6);
        expect([[a location] compare: [TestLocation at: 2]] == NSOrderedSame, "location");
        expect([[a endLocation] compare: [TestLocation at: 6]] == NSOrderedSame, "end location");
        expect(![a isEmpty], "a non-empty range is not empty");
        expect([[[NSTextRange alloc] initWithLocation: [TestLocation at: 3]] isEmpty],
               "a range without an end location is empty");
        expect(range(6, 2) == nil, "an end before the start gives nil");
        expect([a containsLocation: [TestLocation at: 2]], "the start is contained");
        expect(![a containsLocation: [TestLocation at: 6]], "the end is not contained");
        expect([a containsRange: range(3, 5)], "a nested range is contained");
        expect(![a containsRange: range(3, 8)], "an overlapping range is not contained");
        expect([a intersectsWithTextRange: range(5, 9)], "overlapping ranges intersect");
        expect(![a intersectsWithTextRange: range(6, 9)], "adjacent ranges do not intersect");
        NSTextRange *both = [a textRangeByIntersectingWithTextRange: range(4, 9)];
        expect(both != nil && [both isEqualToTextRange: range(4, 6)], "intersection is 4..6");
        expect([a textRangeByIntersectingWithTextRange: range(7, 9)] == nil, "disjoint ranges have no intersection");
        expect([[a textRangeByFormingUnionWithTextRange: range(5, 9)] isEqualToTextRange: range(2, 9)],
               "union is 2..9");

        NSTextContentStorage *content = [[NSTextContentStorage alloc] init];
        [content setAttributedString: [[NSAttributedString alloc] initWithString: @"hello world"]];
        NSTextRange *document = [content documentRange];
        expect(document != nil, "the content storage has a document range");
        id<NSTextLocation> end = [content locationFromLocation: [document location] withOffset: 11];
        expect(end != nil && [end compare: [document endLocation]] == NSOrderedSame,
               "offset 11 is the end of the document");
        expect([content offsetFromLocation: [document location] toLocation: end] == 11,
               "the offset between the document ends is its length");

        NSTextLayoutManager *layout = [[NSTextLayoutManager alloc] init];
        [content addTextLayoutManager: layout];
        expect([layout textContentManager] == content, "the layout manager reports its content manager");
        expect([content primaryTextLayoutManager] == layout, "the first layout manager is primary");
        expect([[content textLayoutManagers] count] == 1, "one layout manager");
        [content removeTextLayoutManager: layout];
        expect([layout textContentManager] == nil, "removal detaches the layout manager");
    }
    if (failures)
        return 1;
    puts("textkit2 text range: PASS");
    return 0;
}
