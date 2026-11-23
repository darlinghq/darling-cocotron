// Copyright (C) 2026 Lubos Dolezel
//
// NSSplitViewItem +inspectorWithViewController:, minimumThickness, maximumThickness,
// collapseBehavior, springLoaded and allowsFullHeightLayout. The documentation says:
// minimumThickness and maximumThickness (read-write, macOS 10.11) default to
// unspecifiedDimension, which means the item enforces no limit; collapseBehavior defaults to
// "default" and has the cases default, preferResizingSplitViewWithFixedSiblings,
// preferResizingSiblingsWithFixedSplitView and useConstraints; isSpringLoaded defaults
// to false; allowsFullHeightLayout (macOS 11.0) defaults to true; Behavior has an
// inspector case, the behavior of items made with init(inspectorWithViewController:), and
// from macOS 14 an inspector can collapse and has a minimum and maximum thickness of 270.
// The rest is black-box behaviour of macOS 26.7.3 (the inspector API is new in 11; the sidebar
// and content list values are the same on Mac OS X 10.14.4), marked QUIRK where it is not
// documented: NSSplitViewItemUnspecifiedDimension is -1, NSSplitViewItemBehaviorInspector is 3,
// an inspector's holding priority is 261, a sidebar is spring loaded and has a minimum
// thickness of 140, a content list has a minimum of 200 and a holding priority of 255, and
// assigning the unspecified constant to a limit stores it.
// Build: clang -fobjc-arc -framework AppKit appkit-splitviewitem-inspector-thickness.m
// Not covered: the "Stub called" log line of the catch-all (NSLog cannot be captured
// here), and any effect on layout (the values are stored only). On master the factory
// raises an unrecognized selector, the accessors fall into the catch-all (stores nothing,
// returns an unspecified value) so only some checks fail, and with ARC the test does
// not compile against master's header.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

// An application subclass that wraps the setters the way an override does: it reads the
// value back first.
@interface ThicknessItem : NSSplitViewItem
- (void)setMinimumThickness:(CGFloat)thickness;
- (void)setCollapseBehavior:(NSSplitViewItemCollapseBehavior)behavior;
@end
@implementation ThicknessItem
- (void)setMinimumThickness:(CGFloat)thickness {
    (void)[self minimumThickness];
    [super setMinimumThickness:thickness];
}
- (void)setCollapseBehavior:(NSSplitViewItemCollapseBehavior)behavior {
    (void)[self collapseBehavior];
    [super setCollapseBehavior:behavior];
}
@end

// Stands in for NSSplitViewItem in an archive. Only the keys the existing decoding reads
// are written.
static NSInteger archivedBehavior;
@interface SplitViewItemStandIn : NSObject <NSCoding>
@end
@implementation SplitViewItemStandIn
- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeInteger:archivedBehavior forKey:@"NSBehavior"];
}
- (id)initWithCoder:(NSCoder *)coder { return [super init]; }
@end

static NSSplitViewItem *decoded(NSInteger behavior) {
    archivedBehavior = behavior;
    NSMutableData *data = [NSMutableData data];
    NSKeyedArchiver *archiver =
        [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];
    [archiver setClassName:@"NSSplitViewItem" forClass:[SplitViewItemStandIn class]];
    [archiver encodeObject:[SplitViewItemStandIn new] forKey:@"root"];
    [archiver finishEncoding];
    NSKeyedUnarchiver *unarchiver =
        [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
    return [unarchiver decodeObjectForKey:@"root"];
}

static NSViewController *controller(void) {
    return [[NSViewController alloc] initWithNibName:nil bundle:nil];
}

static void checkAccessors(NSSplitViewItem *item) {
    CHECK([item respondsToSelector:@selector(minimumThickness)]);
    CHECK([item respondsToSelector:@selector(setMinimumThickness:)]);
    CHECK([item respondsToSelector:@selector(maximumThickness)]);
    CHECK([item respondsToSelector:@selector(setMaximumThickness:)]);
    CHECK([item respondsToSelector:@selector(collapseBehavior)]);
    CHECK([item respondsToSelector:@selector(setCollapseBehavior:)]);
    CHECK([item respondsToSelector:@selector(isSpringLoaded)]);
    CHECK([item respondsToSelector:@selector(setSpringLoaded:)]);
    CHECK([item respondsToSelector:@selector(allowsFullHeightLayout)]);
    CHECK([item respondsToSelector:@selector(setAllowsFullHeightLayout:)]);
}

// The documented defaults of an item that is neither an inspector, a sidebar nor a content list.
static void checkDefaults(NSSplitViewItem *item) {
    CHECK([item minimumThickness] == NSSplitViewItemUnspecifiedDimension);
    CHECK([item maximumThickness] == NSSplitViewItemUnspecifiedDimension);
    CHECK([item collapseBehavior] == NSSplitViewItemCollapseBehaviorDefault);
    CHECK(![item isSpringLoaded]);
    CHECK([item allowsFullHeightLayout]);
}

static void checkRoundTrip(NSSplitViewItem *item) {
    checkAccessors(item);

    const NSSplitViewItemCollapseBehavior behaviors[] = {
        NSSplitViewItemCollapseBehaviorDefault,
        NSSplitViewItemCollapseBehaviorPreferResizingSplitViewWithFixedSiblings,
        NSSplitViewItemCollapseBehaviorPreferResizingSiblingsWithFixedSplitView,
        NSSplitViewItemCollapseBehaviorUseConstraints,
    };
    for (size_t i = 0; i < sizeof behaviors / sizeof behaviors[0]; i++) {
        [item setCollapseBehavior:behaviors[i]];
        CHECK([item collapseBehavior] == behaviors[i]);
    }

    const CGFloat thicknesses[] = {0, 1, 150.5, 270, 10000};
    for (size_t i = 0; i < sizeof thicknesses / sizeof thicknesses[0]; i++) {
        [item setMinimumThickness:thicknesses[i]];
        CHECK([item minimumThickness] == thicknesses[i]);
        [item setMaximumThickness:thicknesses[i] + 1];
        CHECK([item maximumThickness] == thicknesses[i] + 1);
        // the two limits do not overwrite one another
        CHECK([item minimumThickness] == thicknesses[i]);
    }

    [item setSpringLoaded:YES];
    CHECK([item isSpringLoaded]);
    [item setSpringLoaded:NO];
    CHECK(![item isSpringLoaded]);
    [item setAllowsFullHeightLayout:NO];
    CHECK(![item allowsFullHeightLayout]);
    [item setAllowsFullHeightLayout:YES];
    CHECK([item allowsFullHeightLayout]);

    // none of the six values disturbs the properties the class already had
    [item setCollapseBehavior:NSSplitViewItemCollapseBehaviorUseConstraints];
    [item setSpringLoaded:YES];
    [item setAllowsFullHeightLayout:NO];
    [item setMinimumThickness:111];
    [item setMaximumThickness:222];
    CHECK([item collapseBehavior] == NSSplitViewItemCollapseBehaviorUseConstraints);
    CHECK([item isSpringLoaded] && ![item allowsFullHeightLayout]);
    CHECK([item minimumThickness] == 111 && [item maximumThickness] == 222);
    [item setCanCollapse:YES];
    [item setCollapsed:YES];
    [item setHoldingPriority:123];
    CHECK([item canCollapse] && [item isCollapsed] && [item holdingPriority] == 123);
    CHECK([item minimumThickness] == 111 && [item maximumThickness] == 222);
    CHECK([item collapseBehavior] == NSSplitViewItemCollapseBehaviorUseConstraints);
}

int main(void) {
    @autoreleasepool {
        // the numbers of the constant and of the new enum case (macOS 26.7.3)
        CHECK(NSSplitViewItemUnspecifiedDimension == -1);
        CHECK(NSSplitViewItemBehaviorInspector == 3);
        CHECK(NSSplitViewItemBehaviorDefault == 0);
        CHECK(NSSplitViewItemBehaviorSidebar == 1);
        CHECK(NSSplitViewItemBehaviorContentList == 2);

        CHECK([NSSplitViewItem
            respondsToSelector:@selector(inspectorWithViewController:)]);

        // The inspector factory.
        NSViewController *inspectorController = controller();
        NSSplitViewItem *inspector =
            [NSSplitViewItem inspectorWithViewController:inspectorController];
        CHECK(inspector != nil && [inspector isKindOfClass:[NSSplitViewItem class]]);
        CHECK([inspector behavior] == NSSplitViewItemBehaviorInspector);
        CHECK([inspector viewController] == inspectorController);
        // documented for macOS 14 and later: an inspector can collapse, with a fixed
        // thickness of 270
        // (applied on every version)
        CHECK([inspector canCollapse]);
        CHECK([inspector minimumThickness] == 270);
        CHECK([inspector maximumThickness] == 270);
        CHECK([inspector collapseBehavior] == NSSplitViewItemCollapseBehaviorDefault);
        CHECK(![inspector isSpringLoaded]);
        CHECK([inspector allowsFullHeightLayout]);
        CHECK(![inspector isCollapsed]);
        // QUIRK (macOS 26.7.3, probe splititem.m): an inspector's holding priority is 261
        CHECK([inspector holdingPriority] == NSLayoutPriorityDefaultLow + 11);
        // the other factories are not changed by the new one
        NSSplitViewItem *plain =
            [NSSplitViewItem splitViewItemWithViewController:controller()];
        CHECK([plain behavior] == NSSplitViewItemBehaviorDefault && ![plain canCollapse]);
        NSSplitViewItem *sidebar =
            [NSSplitViewItem sidebarWithViewController:controller()];
        CHECK([sidebar behavior] == NSSplitViewItemBehaviorSidebar);
        CHECK([sidebar canCollapse]);
        NSSplitViewItem *list =
            [NSSplitViewItem contentListWithViewController:controller()];
        CHECK([list behavior] == NSSplitViewItemBehaviorContentList);

        // Documented defaults of a plain item, and of a bare -init.
        checkDefaults(plain);
        checkDefaults([[NSSplitViewItem alloc] init]);
        // QUIRK (macOS 26.7.3 and 10.14.4, probe splititem.m): the system standards of a sidebar and of a
        // content list
        CHECK([sidebar minimumThickness] == 140 && [sidebar maximumThickness] == NSSplitViewItemUnspecifiedDimension);
        CHECK([sidebar isSpringLoaded] && [sidebar holdingPriority] == NSLayoutPriorityDefaultLow + 10);
        CHECK([list minimumThickness] == 200 && [list maximumThickness] == NSSplitViewItemUnspecifiedDimension);
        CHECK(![list isSpringLoaded] && [list holdingPriority] == NSLayoutPriorityDefaultLow + 5);
        CHECK([sidebar collapseBehavior] == NSSplitViewItemCollapseBehaviorDefault && [sidebar allowsFullHeightLayout]);

        // Round trips on every kind of item.
        checkRoundTrip(plain);
        checkRoundTrip(inspector);
        checkRoundTrip([NSSplitViewItem sidebarWithViewController:controller()]);

        // A subclass instance (the receiver in a real application was a subclass), created
        // through the inherited factories and through -init; its overrides wrap the
        // superclass setters.
        NSSplitViewItem *sub = [ThicknessItem inspectorWithViewController:controller()];
        CHECK([sub isKindOfClass:[ThicknessItem class]]);
        CHECK([sub behavior] == NSSplitViewItemBehaviorInspector);
        CHECK([sub minimumThickness] == 270);
        checkRoundTrip(sub);
        ThicknessItem *plainSub = [[ThicknessItem alloc] init];
        checkDefaults(plainSub);
        checkRoundTrip(plainSub);

        // QUIRK (macOS 26.7.3, probe splititem.m): assigning the unspecified constant stores it, also for
        // an inspector, whose 270 is only the starting value
        NSSplitViewItem *reset =
            [NSSplitViewItem splitViewItemWithViewController:controller()];
        [reset setMinimumThickness:100];
        [reset setMaximumThickness:300];
        [reset setMinimumThickness:NSSplitViewItemUnspecifiedDimension];
        [reset setMaximumThickness:NSSplitViewItemUnspecifiedDimension];
        CHECK([reset minimumThickness] == NSSplitViewItemUnspecifiedDimension);
        CHECK([reset maximumThickness] == NSSplitViewItemUnspecifiedDimension);
        [inspector setMinimumThickness:100];
        [inspector setMaximumThickness:300];
        CHECK([inspector minimumThickness] == 100 && [inspector maximumThickness] == 300);
        [inspector setMinimumThickness:NSSplitViewItemUnspecifiedDimension];
        [inspector setMaximumThickness:NSSplitViewItemUnspecifiedDimension];
        CHECK([inspector minimumThickness] == NSSplitViewItemUnspecifiedDimension);
        CHECK([inspector maximumThickness] == NSSplitViewItemUnspecifiedDimension);

        // Items decoded from a keyed archive start from the same defaults.
        NSSplitViewItem *fromArchive = decoded(NSSplitViewItemBehaviorDefault);
        CHECK(fromArchive != nil);
        checkDefaults(fromArchive);
        checkRoundTrip(fromArchive);
        NSSplitViewItem *inspectorFromArchive = decoded(NSSplitViewItemBehaviorInspector);
        CHECK([inspectorFromArchive behavior] == NSSplitViewItemBehaviorInspector);
        CHECK([inspectorFromArchive allowsFullHeightLayout]);
        CHECK(![inspectorFromArchive isSpringLoaded]);
        // the documented inspector thickness applies to a decoded inspector too
        CHECK([inspectorFromArchive minimumThickness] == 270);
        CHECK([inspectorFromArchive maximumThickness] == 270);
        [inspectorFromArchive setMinimumThickness:100];
        CHECK([inspectorFromArchive minimumThickness] == 100);
        checkRoundTrip(inspectorFromArchive);
    }
    if (failures) return 1;
    printf("PASS\n");
    return 0;
}
