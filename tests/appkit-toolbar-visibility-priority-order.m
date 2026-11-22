// https://developer.apple.com/documentation/appkit/nstoolbaritem/visibilitypriority-swift.property
// https://developer.apple.com/documentation/appkit/nstoolbaritem/visibilitypriority-swift.struct
// When a toolbar lacks the room for all its items, it keeps the items of the higher visibilityPriority
// and pushes the lower ones to the overflow menu first; of items with the same priority it pushes the
// one nearest the trailing edge first. The type is extensible, so values between the named constants
// are priorities too.
//
// Each item's view is 100 points wide and the window 300 points wide, so two items fit and two do not
// whatever the overflow button's width is (10 points of margins; the button is narrower than 80).
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

// The ivar and @synthesize are explicit: the i386 slice uses the legacy runtime, which does not synthesize properties.
@interface PriorityDelegate : NSObject <NSToolbarDelegate> {
    NSDictionary *_priorities;
}
@property(copy) NSDictionary *priorities;
@end
@implementation PriorityDelegate
@synthesize priorities = _priorities;
- (NSArray *) toolbarDefaultItemIdentifiers: (NSToolbar *) toolbar {
    return @[ @"A", @"B", @"C", @"D" ];
}
- (NSArray *) toolbarAllowedItemIdentifiers: (NSToolbar *) toolbar {
    return [self toolbarDefaultItemIdentifiers: toolbar];
}
- (NSToolbarItem *) toolbar: (NSToolbar *) toolbar itemForItemIdentifier: (NSString *) identifier willBeInsertedIntoToolbar: (BOOL) flag {
    NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier: identifier] autorelease];
    [item setLabel: identifier];
    [item setView: [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 100, 24)] autorelease]];
    NSNumber *priority = self.priorities[identifier];
    if (priority != nil)
        [item setVisibilityPriority: [priority integerValue]];
    return item;
}
@end

static NSArray *visibleIdentifiers(NSDictionary *priorities) {
    PriorityDelegate *delegate = [[PriorityDelegate alloc] init];
    delegate.priorities = priorities;
    NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier: [NSString stringWithFormat: @"priority-%p", delegate]];
    [toolbar setDisplayMode: NSToolbarDisplayModeIconOnly];
    [toolbar setDelegate: delegate];
    NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 300, 200)
                                                   styleMask: NSWindowStyleMaskTitled
                                                     backing: NSBackingStoreBuffered
                                                       defer: NO];
    [window setToolbar: toolbar];
    [window display];
    NSMutableArray *result = [NSMutableArray array];
    for (NSToolbarItem *item in [toolbar visibleItems])
        [result addObject: [item itemIdentifier]];
    return result;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];

        // All standard: the leftmost items stay, the ones at the trailing edge overflow.
        NSArray *equal = visibleIdentifiers(@{});
        CHECK([equal count] == 2);
        CHECK([equal containsObject: @"A"] && [equal containsObject: @"B"]);

        // Named priorities: high and standard stay, low overflows, whatever the position.
        NSArray *named = visibleIdentifiers(@{ @"A": @(NSToolbarItemVisibilityPriorityLow),
                                               @"D": @(NSToolbarItemVisibilityPriorityHigh) });
        CHECK([named count] == 2);
        CHECK([named containsObject: @"D"] && ![named containsObject: @"A"]);

        // A value between the named constants is a priority of its own: 500 outranks standard (0) and is
        // outranked by high (1000), so B and C stay although A is the first standard item.
        NSArray *between = visibleIdentifiers(@{ @"B": @500,
                                                 @"C": @(NSToolbarItemVisibilityPriorityHigh),
                                                 @"D": @(NSToolbarItemVisibilityPriorityLow) });
        CHECK([between count] == 2);
        CHECK([between containsObject: @"B"] && [between containsObject: @"C"]);
        CHECK(![between containsObject: @"A"] && ![between containsObject: @"D"]);

        // Values above the user priority outrank it, values below low are outranked by it.
        NSArray *beyond = visibleIdentifiers(@{ @"A": @(NSToolbarItemVisibilityPriorityLow - 500),
                                                @"B": @(NSToolbarItemVisibilityPriorityUser + 500),
                                                @"C": @(NSToolbarItemVisibilityPriorityUser),
                                                @"D": @(NSToolbarItemVisibilityPriorityLow) });
        CHECK([beyond count] == 2);
        CHECK([beyond containsObject: @"B"] && [beyond containsObject: @"C"]);
    }
    printf("%s\n", failures ? "FAIL" : "PASS");
    return failures ? 1 : 0;
}
