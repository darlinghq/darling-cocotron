/*
 This file is part of Darling.

 Copyright (C) 2019 Lubos Dolezel

 Darling is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Darling is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with Darling.  If not, see <http://www.gnu.org/licenses/>.
*/

#import <AppKit/NSStackView.h>
#import <AppKit/NSWindow.h>
#import "NSViewLayoutInternal.h"
#import <Foundation/NSArray.h>
#import <Foundation/NSException.h>
#import <Foundation/NSKeyValueObserving.h>
#import <Foundation/NSMapTable.h>
#import <objc/runtime.h>

static void *const HiddenContext = (void *) &HiddenContext;
static const CGFloat DefaultSpacing = 8;

@interface NSView (NSStackViewPrivate)
- (void) _removeViewWithoutDisplay: (NSView *) view;
@end

@interface NSStackViewEntry : NSObject {
@public
    NSView *view;
    NSStackViewGravity gravity;
    CGFloat spacingAfter;
    NSStackViewVisibilityPriority visibilityPriority;
    BOOL detached;
    // Detached because the stack view is too small for it (see -_updateDroppedViews).
    BOOL dropped;
    BOOL tamicSetByStack;
    NSSize naturalSize, assignedSize;
}
@end

@implementation NSStackViewEntry
- (void) dealloc {
    [view release];
    [super dealloc];
}
@end

// What an archive of a stack view holds for one gravity area: its views in order, the space after
// some of them and their visibility priorities. Only the archive is decoded into this; the stack
// view takes the contents over. The keys are those macOS writes for its NSStackViewContainer
// (observed in NSKeyedArchiver output and ibtool-compiled nibs of macOS 10.14.4 and 26.7.3).
@interface NSStackViewContainer : NSView {
@public
    NSArray *_views;
    NSMapTable *_customSpacings, *_visibilityPriorities;
}
@end

@implementation NSStackViewContainer

- (instancetype) initWithCoder: (NSCoder *) coder {
    if ((self = [super initWithCoder: coder]) != nil && [coder allowsKeyedCoding]) {
        id views = [coder decodeObjectForKey: @"NSStackViewContainerNonDroppedViews"];
        id spacings = [coder decodeObjectForKey: @"NSStackViewContainerViewToCustomAfterSpaceMap"];
        id priorities = [coder decodeObjectForKey: @"NSStackViewContainerVisibilityPriorities"];

        _views = [([views isKindOfClass: [NSArray class]] ? views : nil) retain];
        _customSpacings = [([spacings isKindOfClass: [NSMapTable class]] ? spacings : nil) retain];
        _visibilityPriorities = [([priorities isKindOfClass: [NSMapTable class]] ? priorities : nil) retain];
    }
    return self;
}

- (void) dealloc {
    [_views release];
    [_customSpacings release];
    [_visibilityPriorities release];
    [super dealloc];
}

@end

@implementation NSStackView

+ (instancetype) stackViewWithViews: (NSArray *) views {
    NSStackView *stackView = [[[self alloc] initWithFrame: NSZeroRect] autorelease];

    [stackView setViews: views inGravity: NSStackViewGravityLeading];
    return stackView;
}

- (void) _setUpStackView {
    _orientation = NSUserInterfaceLayoutOrientationHorizontal;
    _alignment = NSLayoutAttributeNotAnAttribute;
    _distribution = NSStackViewDistributionGravityAreas;
    _spacing = DefaultSpacing;
    // QUIRK: a new stack view keeps hidden views in its layout (detachesHiddenViews is NO). Not
    // documented. Evidence: black-box observation of NSStackView on macOS 10.14.4 (tier 2; macOS
    // 26.7.3 detaches them by default, and archives of both always record the setting). Test:
    // appkit-stack-view-gravity-areas.m (test_quirk_detaches_hidden_views_default)
    _detachesHiddenViews = NO;
    _entries = [[NSMutableArray alloc] init];
}

- (instancetype) initWithFrame: (NSRect) frame {
    if ((self = [super initWithFrame: frame]) != nil)
        [self _setUpStackView];
    return self;
}

// The stack view's settings, under the keys macOS archives them with (observed in
// NSKeyedArchiver output and compiled nibs of macOS 26.7.3 and 10.14.4). A setting that is
// not in the archive keeps its default.
- (void) _decodeSettingsWithCoder: (NSKeyedUnarchiver *) keyed {
    if ([keyed containsValueForKey: @"NSStackViewOrientation"])
        _orientation = [keyed decodeIntegerForKey: @"NSStackViewOrientation"];
    if ([keyed containsValueForKey: @"NSStackViewAlignment"])
        _alignment = [keyed decodeIntegerForKey: @"NSStackViewAlignment"];
    // Fill (0) and the other explicit distributions are archived; gravity areas is not.
    if ([keyed containsValueForKey: @"NSStackViewdistribution"])
        _distribution = [keyed decodeIntegerForKey: @"NSStackViewdistribution"];
    if ([keyed containsValueForKey: @"NSStackViewSpacing"])
        _spacing = [keyed decodeDoubleForKey: @"NSStackViewSpacing"];
    if ([keyed containsValueForKey: @"NSStackViewEdgeInsets.top"])
        _edgeInsets = NSEdgeInsetsMake([keyed decodeDoubleForKey: @"NSStackViewEdgeInsets.top"],
                                       [keyed decodeDoubleForKey: @"NSStackViewEdgeInsets.left"],
                                       [keyed decodeDoubleForKey: @"NSStackViewEdgeInsets.bottom"],
                                       [keyed decodeDoubleForKey: @"NSStackViewEdgeInsets.right"]);
    if ([keyed containsValueForKey: @"NSStackViewDetachesHiddenViews"])
        _detachesHiddenViews = [keyed decodeBoolForKey: @"NSStackViewDetachesHiddenViews"];
    if ([keyed containsValueForKey: @"NSStackViewHorizontalHugging"])
        [self setHuggingPriority: [keyed decodeFloatForKey: @"NSStackViewHorizontalHugging"]
                  forOrientation: NSLayoutConstraintOrientationHorizontal];
    if ([keyed containsValueForKey: @"NSStackViewVerticalHugging"])
        [self setHuggingPriority: [keyed decodeFloatForKey: @"NSStackViewVerticalHugging"]
                  forOrientation: NSLayoutConstraintOrientationVertical];
    if ([keyed containsValueForKey: @"NSStackViewHorizontalClippingResistance"])
        [self setClippingResistancePriority: [keyed decodeFloatForKey: @"NSStackViewHorizontalClippingResistance"]
                             forOrientation: NSLayoutConstraintOrientationHorizontal];
    if ([keyed containsValueForKey: @"NSStackViewVerticalClippingResistance"])
        [self setClippingResistancePriority: [keyed decodeFloatForKey: @"NSStackViewVerticalClippingResistance"]
                             forOrientation: NSLayoutConstraintOrientationVertical];
}

// An archive that holds the gravity areas' views gives each its gravity, space after it and visibility
// priority, and the stack view arranges them at once. Without them (an archive written by something
// else) the decoded subviews become leading arranged views and keep their archived frames until the
// stack view changes.
- (void) _decodeGravityContainers: (NSArray *) containers {
    static const NSStackViewGravity gravities[3] = {NSStackViewGravityLeading, NSStackViewGravityCenter,
                                                    NSStackViewGravityTrailing};
    NSArray *subviews = [[[self subviews] copy] autorelease];

    for (int i = 0; i < 3; i++) {
        NSStackViewContainer *container = [containers objectAtIndex: i];

        if (![container isKindOfClass: [NSStackViewContainer class]])
            continue;
        for (NSView *view in container->_views) {
            if (![view isKindOfClass: [NSView class]] || [self _entryForView: view] != nil)
                continue;

            NSStackViewEntry *entry = [self _newEntryForView: view inGravity: gravities[i]];
            id spacing = [container->_customSpacings objectForKey: view];
            id priority = [container->_visibilityPriorities objectForKey: view];

            if ([spacing respondsToSelector: @selector(doubleValue)])
                entry->spacingAfter = [spacing doubleValue];
            if ([priority respondsToSelector: @selector(floatValue)])
                entry->visibilityPriority = [priority floatValue];
            // A view the archive does not list as a subview was detached when it was archived.
            if (![subviews containsObject: view])
                entry->dropped = ![self _isDetachedByState: entry];
            entry->detached = [self _shouldDetach: entry];
            [_entries addObject: entry];
            [entry release];
            if (entry->detached && [view superview] == self)
                [view removeFromSuperview];
        }
    }
    // Subviews no area lists stay arranged, as leading views.
    for (NSView *view in subviews) {
        if ([self _entryForView: view] != nil)
            continue;

        NSStackViewEntry *entry = [self _newEntryForView: view inGravity: NSStackViewGravityLeading];

        [_entries addObject: entry];
        [entry release];
        if (entry->detached)
            [view removeFromSuperview];
    }
}

- (instancetype) initWithCoder: (NSCoder *) coder {
    if ((self = [super initWithCoder: coder]) != nil) {
        NSArray *containers = nil;

        [self _setUpStackView];
        if ([coder allowsKeyedCoding]) {
            NSKeyedUnarchiver *keyed = (NSKeyedUnarchiver *) coder;

            [self _decodeSettingsWithCoder: keyed];
            if ([keyed containsValueForKey: @"NSStackViewBeginningContainer"] ||
                [keyed containsValueForKey: @"NSStackViewMiddleContainer"] ||
                [keyed containsValueForKey: @"NSStackViewEndContainer"]) {
                id none = [NSNull null];
                id begin = [keyed decodeObjectForKey: @"NSStackViewBeginningContainer"];
                id middle = [keyed decodeObjectForKey: @"NSStackViewMiddleContainer"];
                id end = [keyed decodeObjectForKey: @"NSStackViewEndContainer"];

                containers = [NSArray arrayWithObjects: begin ? begin : none, middle ? middle : none,
                                                        end ? end : none, nil];
            }
        }
        _changingViews = YES;
        if (containers != nil) {
            [self _decodeGravityContainers: containers];
        } else {
            for (NSView *view in [[[self subviews] copy] autorelease]) {
                NSStackViewEntry *entry = [self _newEntryForView: view
                                                       inGravity: NSStackViewGravityLeading];

                [_entries addObject: entry];
                [entry release];
                if (entry->detached)
                    [view removeFromSuperview];
            }
        }
        _changingViews = NO;
        _keepsDecodedFrames = containers == nil;
        if (containers != nil)
            [self setNeedsLayout: YES];
    }
    return self;
}

- (void) dealloc {
    for (NSStackViewEntry *entry in _entries)
        [entry->view removeObserver: self forKeyPath: @"hidden" context: HiddenContext];
    [_entries release];
    [super dealloc];
}

- (NSStackViewEntry *) _entryForView: (NSView *) view {
    for (NSStackViewEntry *entry in _entries)
        if (entry->view == view)
            return entry;
    return nil;
}

- (NSStackViewEntry *) _requiredEntryForView: (NSView *) view {
    NSStackViewEntry *entry = [self _entryForView: view];

    if (entry == nil)
        [NSException raise: NSInvalidArgumentException
                    format: @"%@ is not in stack view %@", view, self];
    return entry;
}

// Alignments on the vertical axis apply to horizontal stacks and vice versa;
// Apple ignores a value for the wrong axis.
- (BOOL) _alignmentIsVertical: (NSLayoutAttribute) alignment {
    switch (alignment) {
    case NSLayoutAttributeTop:
    case NSLayoutAttributeBottom:
    case NSLayoutAttributeCenterY:
    case NSLayoutAttributeHeight:
    case NSLayoutAttributeBaseline:
    case NSLayoutAttributeFirstBaseline:
        return YES;
    default:
        return NO;
    }
}

#pragma mark - Properties

- (id<NSStackViewDelegate>) delegate {
    return _delegate;
}

- (void) setDelegate: (id<NSStackViewDelegate>) delegate {
    _delegate = delegate;
}

- (NSUserInterfaceLayoutOrientation) orientation {
    return _orientation;
}

- (void) setOrientation: (NSUserInterfaceLayoutOrientation) orientation {
    _orientation = orientation;
    [self _arrangeViews];
}

// NotAnAttribute stands for the orientation's documented default.
- (NSLayoutAttribute) alignment {
    if (_alignment == NSLayoutAttributeNotAnAttribute)
        return _orientation == NSUserInterfaceLayoutOrientationVertical ? NSLayoutAttributeCenterX
                                                                        : NSLayoutAttributeCenterY;
    return _alignment;
}

- (void) setAlignment: (NSLayoutAttribute) alignment {
    _alignment = alignment;
    [self _arrangeViews];
}

- (NSStackViewDistribution) distribution {
    return _distribution;
}

- (void) setDistribution: (NSStackViewDistribution) distribution {
    _distribution = distribution;
    [self _arrangeViews];
}

static const char huggingKey;
static const char clippingResistanceKey;

// Priorities per orientation, kept outside the instance, whose ivar layout is fixed.
static NSLayoutPriority priorityFor(id object, const char *key, NSLayoutConstraintOrientation orientation,
                                    NSLayoutPriority fallback) {
    NSArray *priorities = objc_getAssociatedObject(object, key);

    return priorities ? [[priorities objectAtIndex: orientation] floatValue] : fallback;
}

static void setPriorityFor(id object, const char *key, NSLayoutConstraintOrientation orientation,
                           NSLayoutPriority priority, NSLayoutPriority fallback) {
    NSMutableArray *priorities = [[objc_getAssociatedObject(object, key) mutableCopy] autorelease];

    if (priorities == nil)
        priorities = [NSMutableArray arrayWithObjects: [NSNumber numberWithFloat: fallback],
                                                       [NSNumber numberWithFloat: fallback], nil];
    [priorities replaceObjectAtIndex: orientation withObject: [NSNumber numberWithFloat: priority]];
    objc_setAssociatedObject(object, key, priorities, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSLayoutPriority) huggingPriorityForOrientation: (NSLayoutConstraintOrientation) orientation {
    return priorityFor(self, &huggingKey, orientation, NSLayoutPriorityDefaultLow);
}

- (void) setHuggingPriority: (NSLayoutPriority) priority
             forOrientation: (NSLayoutConstraintOrientation) orientation
{
    setPriorityFor(self, &huggingKey, orientation, priority, NSLayoutPriorityDefaultLow);
}

- (NSLayoutPriority) clippingResistancePriorityForOrientation: (NSLayoutConstraintOrientation) orientation {
    return priorityFor(self, &clippingResistanceKey, orientation, NSLayoutPriorityRequired);
}

- (void) setClippingResistancePriority: (NSLayoutPriority) priority
                        forOrientation: (NSLayoutConstraintOrientation) orientation
{
    setPriorityFor(self, &clippingResistanceKey, orientation, priority, NSLayoutPriorityRequired);
}

- (CGFloat) spacing {
    return _spacing;
}

- (void) setSpacing: (CGFloat) spacing {
    _spacing = spacing;
    [self _arrangeViews];
}

- (NSEdgeInsets) edgeInsets {
    return _edgeInsets;
}

- (void) setEdgeInsets: (NSEdgeInsets) insets {
    _edgeInsets = insets;
    [self _arrangeViews];
}

- (BOOL) detachesHiddenViews {
    return _detachesHiddenViews;
}

- (void) setDetachesHiddenViews: (BOOL) flag {
    _detachesHiddenViews = flag;
    [self _updateAttachment];
}

#pragma mark - Views and gravity areas

- (NSArray *) _viewsOfEntriesPassing: (BOOL (^)(NSStackViewEntry *)) test {
    NSMutableArray *views = [NSMutableArray array];

    for (NSStackViewEntry *entry in _entries)
        if (test(entry))
            [views addObject: entry->view];
    return views;
}

- (NSArray *) views {
    return [self _viewsOfEntriesPassing: ^BOOL(NSStackViewEntry *e) { return YES; }];
}

- (NSArray *) arrangedSubviews {
    return [self _viewsOfEntriesPassing: ^BOOL(NSStackViewEntry *e) { return !e->detached; }];
}

- (NSArray *) detachedViews {
    return [self _viewsOfEntriesPassing: ^BOOL(NSStackViewEntry *e) { return e->detached; }];
}

- (NSArray *) viewsInGravity: (NSStackViewGravity) gravity {
    return [self _viewsOfEntriesPassing: ^BOOL(NSStackViewEntry *e) {
        return e->gravity == gravity;
    }];
}

- (NSStackViewEntry *) _newEntryForView: (NSView *) view inGravity: (NSStackViewGravity) gravity {
    NSStackViewEntry *entry = [[NSStackViewEntry alloc] init];

    entry->view = [view retain];
    entry->gravity = gravity;
    entry->spacingAfter = NSStackViewSpacingUseDefault;
    entry->visibilityPriority = NSStackViewVisibilityPriorityMustHold;
    entry->detached = [self _shouldDetach: entry];
    entry->naturalSize = entry->assignedSize = [view frame].size;
    [view addObserver: self forKeyPath: @"hidden" options: 0 context: HiddenContext];
    return entry;
}

- (void) insertView: (NSView *) view
            atIndex: (NSUInteger) index
          inGravity: (NSStackViewGravity) gravity
{
    NSStackViewEntry *entry;
    NSUInteger start = 0, count = 0;

    if (view == nil)
        [NSException raise: NSInvalidArgumentException format: @"nil view for stack view %@", self];
    if (gravity < NSStackViewGravityLeading || gravity > NSStackViewGravityTrailing)
        [NSException raise: NSInvalidArgumentException
                    format: @"Invalid stack view gravity %ld", (long) gravity];
    for (NSStackViewEntry *other in _entries) {
        if (other->view == view)
            continue;
        if (other->gravity < gravity)
            start++;
        else if (other->gravity == gravity)
            count++;
    }
    if (index > count)
        [NSException raise: NSRangeException
                    format: @"Index %lu beyond the %lu views in gravity %ld",
                            (unsigned long) index, (unsigned long) count, (long) gravity];

    [[view retain] autorelease];
    [self _forgetView: view];
    entry = [self _newEntryForView: view inGravity: gravity];
    [_entries insertObject: entry atIndex: start + index];
    [entry release];
    _changingViews = YES;
    if (!entry->detached && [view superview] != self)
        [self addSubview: view];
    else if (entry->detached && [view superview] != nil)
        [view removeFromSuperview];
    _changingViews = NO;
    [self _arrangeViews];
}

- (void) addView: (NSView *) view inGravity: (NSStackViewGravity) gravity {
    NSUInteger count = 0;

    for (NSStackViewEntry *entry in _entries)
        if (entry->gravity == gravity && entry->view != view)
            count++;
    [self insertView: view atIndex: count inGravity: gravity];
}

- (void) setViews: (NSArray *) views inGravity: (NSStackViewGravity) gravity {
    for (NSView *view in [self viewsInGravity: gravity])
        [self removeView: view];
    for (NSView *view in views)
        [self addView: view inGravity: gravity];
}

// Drops the stack view's record of the view; the caller decides about superview.
- (void) _forgetView: (NSView *) view {
    NSStackViewEntry *entry = [self _entryForView: view];

    if (entry == nil)
        return;
    [view removeObserver: self forKeyPath: @"hidden" context: HiddenContext];
    [_entries removeObjectIdenticalTo: entry];
}

- (void) removeView: (NSView *) view {
    NSStackViewEntry *entry = [self _requiredEntryForView: view];

    [[view retain] autorelease];
    if (!entry->detached && [view superview] == self) {
        _changingViews = YES;
        [view removeFromSuperview];
        _changingViews = NO;
    }
    [self _forgetView: view];
    [self _arrangeViews];
}

- (void) addArrangedSubview: (NSView *) view {
    NSStackViewGravity gravity = [_entries count] != 0
            ? ((NSStackViewEntry *) [_entries lastObject])->gravity
            : NSStackViewGravityLeading;

    [self addView: view inGravity: gravity];
}

- (void) insertArrangedSubview: (NSView *) view atIndex: (NSInteger) index {
    NSArray *arranged = [self arrangedSubviews];
    NSStackViewEntry *before;
    NSUInteger gravityIndex = 0;

    if (index < 0 || (NSUInteger) index > [arranged count])
        [NSException raise: NSRangeException
                    format: @"Index %ld beyond the %lu arranged subviews",
                            (long) index, (unsigned long) [arranged count]];
    if ((NSUInteger) index == [arranged count]) {
        [self addArrangedSubview: view];
        return;
    }
    before = [self _entryForView: [arranged objectAtIndex: index]];
    for (NSStackViewEntry *entry in _entries) {
        if (entry == before)
            break;
        if (entry->gravity == before->gravity && entry->view != view)
            gravityIndex++;
    }
    [self insertView: view atIndex: gravityIndex inGravity: before->gravity];
}

// Apple keeps the view as a subview; only the stack view stops arranging it.
- (void) removeArrangedSubview: (NSView *) view {
    if ([self _entryForView: view] == nil)
        return;
    [self _forgetView: view];
    [self _arrangeViews];
}

// Cocotron's removeFromSuperview reports to the superview here, not through
// willRemoveSubview:.
- (void) _removeViewWithoutDisplay: (NSView *) view {
    BOOL managed = !_changingViews && [self _entryForView: view] != nil;

    if (managed) {
        [[view retain] autorelease];
        [self _forgetView: view];
    }
    [super _removeViewWithoutDisplay: view];
    if (managed)
        [self _arrangeViews];
}

#pragma mark - Spacing and visibility

- (void) setCustomSpacing: (CGFloat) spacing afterView: (NSView *) view {
    [self _requiredEntryForView: view]->spacingAfter = spacing;
    [self _arrangeViews];
}

- (CGFloat) customSpacingAfterView: (NSView *) view {
    return [self _requiredEntryForView: view]->spacingAfter;
}

- (void) setVisibilityPriority: (NSStackViewVisibilityPriority) priority
                       forView: (NSView *) view
{
    [self _requiredEntryForView: view]->visibilityPriority = priority;
    [self _updateAttachment];
}

- (NSStackViewVisibilityPriority) visibilityPriorityForView: (NSView *) view {
    return [self _requiredEntryForView: view]->visibilityPriority;
}

// A view that is hidden or not visible by its priority, whatever the room there is.
- (BOOL) _isDetachedByState: (NSStackViewEntry *) entry {
    return entry->visibilityPriority == NSStackViewVisibilityPriorityNotVisible ||
           (_detachesHiddenViews && [entry->view isHidden]);
}

- (BOOL) _shouldDetach: (NSStackViewEntry *) entry {
    return entry->dropped || [self _isDetachedByState: entry];
}

- (void) _updateAttachment {
    NSMutableArray *detach = [NSMutableArray array];
    NSMutableArray *reattach = [NSMutableArray array];

    for (NSStackViewEntry *entry in _entries) {
        BOOL shouldDetach = [self _shouldDetach: entry];

        if (shouldDetach && !entry->detached)
            [detach addObject: entry->view];
        else if (!shouldDetach && entry->detached)
            [reattach addObject: entry->view];
    }

    if ([detach count] != 0 &&
        [_delegate respondsToSelector: @selector(stackView:willDetachViews:)])
        [_delegate stackView: self willDetachViews: detach];

    _changingViews = YES;
    // The delegate may have removed some of these views from the stack view.
    for (NSView *view in detach) {
        NSStackViewEntry *entry = [self _entryForView: view];

        if (entry == nil)
            continue;
        entry->detached = YES;
        if ([view superview] == self)
            [view removeFromSuperview];
    }
    for (NSView *view in [[reattach copy] autorelease]) {
        NSStackViewEntry *entry = [self _entryForView: view];

        if (entry == nil) {
            [reattach removeObjectIdenticalTo: view];
            continue;
        }
        entry->detached = NO;
        [self addSubview: view];
    }
    _changingViews = NO;

    [self _arrangeViews];
    if ([reattach count] != 0 &&
        [_delegate respondsToSelector: @selector(stackView:didReattachViews:)])
        [_delegate stackView: self didReattachViews: reattach];
}

- (void) observeValueForKeyPath: (NSString *) keyPath
                       ofObject: (id) object
                         change: (NSDictionary *) change
                        context: (void *) context
{
    if (context != HiddenContext) {
        [super observeValueForKeyPath: keyPath ofObject: object change: change context: context];
        return;
    }
    [self _updateAttachment];
}

#pragma mark - Layout

typedef struct {
    CGFloat main, cross;
} StackSize;

- (BOOL) _isVertical {
    return _orientation == NSUserInterfaceLayoutOrientationVertical;
}

// Without an intrinsic size a view keeps the size it had when added, or the
// size it was last given by someone other than the stack view.
- (StackSize) _naturalSizeOfEntry: (NSStackViewEntry *) entry {
    NSSize intrinsic = [entry->view intrinsicContentSize];
    NSSize frame = [entry->view frame].size;
    CGFloat width, height;

    if (!NSEqualSizes(frame, entry->assignedSize))
        entry->naturalSize = entry->assignedSize = frame;
    width = intrinsic.width != NSViewNoIntrinsicMetric ? intrinsic.width : entry->naturalSize.width;
    height = intrinsic.height != NSViewNoIntrinsicMetric ? intrinsic.height : entry->naturalSize.height;

    return [self _isVertical] ? (StackSize) { height, width } : (StackSize) { width, height };
}

- (CGFloat) _spacingAfter: (NSStackViewEntry *) entry {
    return entry->spacingAfter == NSStackViewSpacingUseDefault ? _spacing : entry->spacingAfter;
}

- (NSArray *) _attachedEntries {
    NSMutableArray *attached = [NSMutableArray array];

    for (NSStackViewEntry *entry in _entries)
        if (!entry->detached)
            [attached addObject: entry];
    return attached;
}

// Each gravity area as the range of entries it holds: first[g]..last[g] (inclusive), with
// last[g] < first[g] when the area is empty, and the length of its views and the space between them.
typedef struct {
    NSInteger first[4], last[4];
    CGFloat length[4];
} GravityAreas;

- (GravityAreas) _gravityAreasOfEntries: (NSArray *) entries lengths: (CGFloat *) lengths spacings: (CGFloat *) spacing {
    GravityAreas areas = {{0, 0, 0, 0}, {-1, -1, -1, -1}, {0, 0, 0, 0}};
    NSUInteger i, count = [entries count];
    NSStackViewGravity g;

    for (g = NSStackViewGravityLeading; g <= NSStackViewGravityTrailing; g++)
        areas.first[g] = count;
    for (i = 0; i < count; i++) {
        g = ((NSStackViewEntry *) [entries objectAtIndex: i])->gravity;
        areas.first[g] = MIN(areas.first[g], (NSInteger) i);
        areas.last[g] = i;
    }
    for (g = NSStackViewGravityLeading; g <= NSStackViewGravityTrailing; g++)
        for (i = areas.first[g]; (NSInteger) i <= areas.last[g]; i++)
            areas.length[g] += lengths[i] + ((NSInteger) i < areas.last[g] ? spacing[i] : 0);
    return areas;
}

// The length along the stacking axis the entries need, insets included. The center gravity area is
// centered in the whole stack view, so it counts twice on the side of the longer neighbour.
- (CGFloat) _fittingMainLengthForEntries: (NSArray *) entries {
    NSUInteger i, count = [entries count];
    CGFloat insetStart = [self _isVertical] ? _edgeInsets.top : _edgeInsets.left;
    CGFloat insetEnd = [self _isVertical] ? _edgeInsets.bottom : _edgeInsets.right;
    CGFloat lengths[count + 1], spacing[count + 1], sum = 0, gaps = 0, widest = 0, step = 0;

    if (count == 0)
        return insetStart + insetEnd;
    for (i = 0; i < count; i++) {
        NSStackViewEntry *entry = [entries objectAtIndex: i];

        lengths[i] = [self _naturalSizeOfEntry: entry].main;
        spacing[i] = [self _spacingAfter: entry];
        sum += lengths[i];
        widest = MAX(widest, lengths[i]);
        if (i + 1 < count)
            gaps += spacing[i];
    }

    switch (_distribution) {
    case NSStackViewDistributionFillEqually:
        return insetStart + insetEnd + widest * count + gaps;
    case NSStackViewDistributionEqualCentering:
        // The centers of neighbouring views are as far apart as the widest pair needs.
        for (i = 0; i + 1 < count; i++)
            step = MAX(step, lengths[i] / 2 + spacing[i] + lengths[i + 1] / 2);
        return insetStart + insetEnd + (count == 1 ? lengths[0] : lengths[0] / 2 + step * (count - 1) + lengths[count - 1] / 2);
    case NSStackViewDistributionGravityAreas:
        break;
    default:
        return insetStart + insetEnd + sum + gaps;
    }

    GravityAreas areas = [self _gravityAreasOfEntries: entries lengths: lengths spacings: spacing];
    BOOL lead = areas.last[NSStackViewGravityLeading] >= 0, center = areas.last[NSStackViewGravityCenter] >= 0,
         trail = areas.last[NSStackViewGravityTrailing] >= 0;
    CGFloat leadGap = lead ? spacing[areas.last[NSStackViewGravityLeading]] : 0;
    CGFloat centerGap = center ? spacing[areas.last[NSStackViewGravityCenter]] : 0;
    CGFloat leading = areas.length[NSStackViewGravityLeading], middle = areas.length[NSStackViewGravityCenter],
            trailing = areas.length[NSStackViewGravityTrailing];
    CGFloat fit = insetStart + insetEnd + leading + middle + trailing;

    if (lead && trail)
        fit = MAX(fit, insetStart + leading + (center ? 0 : leadGap) + trailing + insetEnd);
    if (center) {
        CGFloat leftNeed = (lead ? insetStart + leading + leadGap : insetStart) + middle / 2;
        CGFloat rightNeed = middle / 2 + (trail ? centerGap + trailing + insetEnd : insetEnd);

        fit = MAX(fit, 2 * MAX(leftNeed, rightNeed));
    }
    return fit;
}

- (NSSize) intrinsicContentSize {
    // A stack view that arranges its views with constraints has no intrinsic
    // size of its own; its constraints size it.
    if ([self _constraintArrangementIsActive])
        return NSMakeSize(NSViewNoIntrinsicMetric, NSViewNoIntrinsicMetric);
    // Measuring decoded views with the undecoded default settings would be wrong.
    NSArray *attached = _keepsDecodedFrames ? [NSArray array] : [self _attachedEntries];
    NSUInteger i, count = [attached count];
    CGFloat main = [self _fittingMainLengthForEntries: attached], cross = 0;

    for (i = 0; i < count; i++)
        cross = MAX(cross, [self _naturalSizeOfEntry: [attached objectAtIndex: i]].cross);
    if ([self _isVertical])
        return NSMakeSize(cross + _edgeInsets.left + _edgeInsets.right, main);
    return NSMakeSize(main, cross + _edgeInsets.top + _edgeInsets.bottom);
}

// QUIRK: in gravity areas, a view that hugs its content below the default priority (250) is
// stretched to take the room between its area and the next one (the least hugging view of an
// area, the first of equals), as far as the space after the area's last view allows: the leading
// area up to the center area (or the trailing one), the trailing area back to the center area (or
// the leading one), and the center area, which stays centered, as far as the nearer neighbour
// allows. A view that hugs at 250 or more is not stretched. Not documented. Evidence: black-box
// observation of NSStackView on macOS 10.14.4 and 26.7.3 (tier 2), probe
// mac-probes/stackview-gravity-layout.m of the research notes.
// Test: appkit-stack-view-gravity-areas.m (test_quirk_gravity_area_stretch)
// Returns whether a view was stretched; the areas' lengths and starts are updated.
- (BOOL) _stretchGravityAreas: (GravityAreas *) areas
                        start: (CGFloat *) start
                      entries: (NSArray *) entries
                      lengths: (CGFloat *) lengths
                     spacings: (CGFloat *) spacing
                       length: (CGFloat) length
                         axis: (NSLayoutConstraintOrientation) axis
{
    NSInteger stretchy[4];
    BOOL any = NO;
    NSStackViewGravity g;

    for (g = NSStackViewGravityLeading; g <= NSStackViewGravityTrailing; g++) {
        NSLayoutPriority lowest = NSLayoutPriorityDefaultLow;

        stretchy[g] = -1;
        for (NSInteger i = areas->first[g]; i <= areas->last[g]; i++) {
            NSView *view = ((NSStackViewEntry *) [entries objectAtIndex: i])->view;
            NSLayoutPriority hugging = [view contentHuggingPriorityForOrientation: axis];

            if (hugging < lowest) {
                lowest = hugging;
                stretchy[g] = i;
            }
        }
        any = any || stretchy[g] >= 0;
    }
    if (!any)
        return NO;

    BOOL lead = areas->last[NSStackViewGravityLeading] >= 0, center = areas->last[NSStackViewGravityCenter] >= 0,
         trail = areas->last[NSStackViewGravityTrailing] >= 0;
    CGFloat leadGap = lead ? spacing[areas->last[NSStackViewGravityLeading]] : 0;
    CGFloat centerGap = center ? spacing[areas->last[NSStackViewGravityCenter]] : 0;
    BOOL stretched = NO;

    if (lead && stretchy[NSStackViewGravityLeading] >= 0) {
        CGFloat bound = center ? start[NSStackViewGravityCenter] - leadGap
                               : (trail ? start[NSStackViewGravityTrailing] - leadGap : length);
        CGFloat extra = bound - areas->length[NSStackViewGravityLeading];

        if (extra > 0) {
            lengths[stretchy[NSStackViewGravityLeading]] += extra;
            areas->length[NSStackViewGravityLeading] += extra;
            stretched = YES;
        }
    }
    if (trail && stretchy[NSStackViewGravityTrailing] >= 0) {
        CGFloat bound = center ? start[NSStackViewGravityCenter] + areas->length[NSStackViewGravityCenter] + centerGap
                               : (lead ? areas->length[NSStackViewGravityLeading] + leadGap : 0);
        CGFloat extra = start[NSStackViewGravityTrailing] - bound;

        if (extra > 0) {
            lengths[stretchy[NSStackViewGravityTrailing]] += extra;
            areas->length[NSStackViewGravityTrailing] += extra;
            stretched = YES;
        }
    }
    if (center && stretchy[NSStackViewGravityCenter] >= 0) {
        CGFloat left = start[NSStackViewGravityCenter] - (lead ? areas->length[NSStackViewGravityLeading] + leadGap : 0);
        CGFloat right = (trail ? length - areas->length[NSStackViewGravityTrailing] - centerGap : length) -
                        (start[NSStackViewGravityCenter] + areas->length[NSStackViewGravityCenter]);
        CGFloat extra = MIN(left, right);

        if (extra > 0) {
            lengths[stretchy[NSStackViewGravityCenter]] += 2 * extra;
            areas->length[NSStackViewGravityCenter] += 2 * extra;
            stretched = YES;
        }
    }
    return stretched;
}

// Offsets along the stacking axis, measured from the leading (left or top) edge.
- (void) _computeOffsets: (CGFloat *) offsets
                 lengths: (CGFloat *) lengths
              forEntries: (NSArray *) entries
                  length: (CGFloat) length
{
    NSUInteger i, count = [entries count];
    CGFloat sum = 0, gaps = 0;
    CGFloat spacing[count];

    for (i = 0; i < count; i++) {
        spacing[i] = [self _spacingAfter: [entries objectAtIndex: i]];
        sum += lengths[i];
        if (i + 1 < count)
            gaps += spacing[i];
    }

    switch (_distribution) {
    case NSStackViewDistributionFill: {
        NSLayoutConstraintOrientation axis = [self _isVertical]
                ? NSLayoutConstraintOrientationVertical
                : NSLayoutConstraintOrientationHorizontal;
        NSUInteger flexible = 0;

        // The view that hugs its content least absorbs the extra or missing space. Among equals,
        // views with an intrinsic size give it to the first and the others to the last.
        for (i = 1; i < count; i++) {
            NSView *view = ((NSStackViewEntry *) [entries objectAtIndex: i])->view;
            NSView *chosen = ((NSStackViewEntry *) [entries objectAtIndex: flexible])->view;
            NSLayoutPriority hugging = [view contentHuggingPriorityForOrientation: axis];
            NSLayoutPriority chosenHugging = [chosen contentHuggingPriorityForOrientation: axis];
            NSSize intrinsic = [chosen intrinsicContentSize];

            if (hugging < chosenHugging ||
                (hugging == chosenHugging &&
                 (axis == NSLayoutConstraintOrientationVertical ? intrinsic.height : intrinsic.width) ==
                         NSViewNoIntrinsicMetric))
                flexible = i;
        }
        lengths[flexible] = MAX(0, lengths[flexible] + length - sum - gaps);
        break;
    }
    case NSStackViewDistributionFillEqually:
        for (i = 0; i < count; i++)
            lengths[i] = MAX(0, (length - gaps) / count);
        break;
    case NSStackViewDistributionFillProportionally:
        for (i = 0; i < count; i++)
            lengths[i] = MAX(0, sum > 0 ? lengths[i] / sum * (length - gaps)
                                        : (length - gaps) / count);
        break;
    case NSStackViewDistributionEqualSpacing:
        for (i = 0; i + 1 < count; i++)
            spacing[i] = MAX(spacing[i], (length - sum) / (count - 1));
        break;
    default:
        break;
    }

    if (_distribution == NSStackViewDistributionEqualCentering && count > 1) {
        CGFloat step = (length - lengths[0] / 2 - lengths[count - 1] / 2) / (count - 1);

        offsets[0] = 0;
        for (i = 1; i < count; i++)
            offsets[i] = MAX(lengths[0] / 2 + i * step - lengths[i] / 2,
                             offsets[i - 1] + lengths[i - 1] + spacing[i - 1]);
        return;
    }

    if (_distribution == NSStackViewDistributionGravityAreas) {
        GravityAreas areas = [self _gravityAreasOfEntries: entries lengths: lengths spacings: spacing];
        NSLayoutConstraintOrientation axis = [self _isVertical] ? NSLayoutConstraintOrientationVertical
                                                                : NSLayoutConstraintOrientationHorizontal;
        CGFloat insetStart = [self _isVertical] ? _edgeInsets.top : _edgeInsets.left;
        CGFloat insetEnd = [self _isVertical] ? _edgeInsets.bottom : _edgeInsets.right;
        CGFloat start[4], end;
        NSStackViewGravity g, previous = 0;

        // The center area is centered in the whole stack view, which the insets may off-center in
        // the room the views have, and stays so unless that would crowd a neighbouring area.
        for (int pass = 0; pass < 2; pass++) {
            start[NSStackViewGravityLeading] = 0;
            start[NSStackViewGravityTrailing] = length - areas.length[NSStackViewGravityTrailing];
            start[NSStackViewGravityCenter] = (length - areas.length[NSStackViewGravityCenter] + insetEnd - insetStart) / 2;
            if (areas.last[NSStackViewGravityCenter] >= 0 && areas.last[NSStackViewGravityTrailing] >= 0)
                start[NSStackViewGravityCenter] = MIN(start[NSStackViewGravityCenter],
                        start[NSStackViewGravityTrailing] - spacing[areas.last[NSStackViewGravityCenter]] -
                                areas.length[NSStackViewGravityCenter]);
            // Stretching changes the areas' lengths, so the second pass places them again.
            if (pass == 1 || ![self _stretchGravityAreas: &areas start: start entries: entries lengths: lengths
                                                 spacings: spacing length: length axis: axis])
                break;
        }

        end = 0;
        for (g = NSStackViewGravityLeading; g <= NSStackViewGravityTrailing; g++) {
            CGFloat position;

            if (areas.last[g] < 0)
                continue;
            position = previous ? MAX(start[g], end + spacing[areas.last[previous]]) : start[g];
            for (i = areas.first[g]; (NSInteger) i <= areas.last[g]; i++) {
                offsets[i] = position;
                position += lengths[i] + spacing[i];
            }
            end = offsets[areas.last[g]] + lengths[areas.last[g]];
            previous = g;
        }
        return;
    }

    offsets[0] = 0;
    for (i = 1; i < count; i++)
        offsets[i] = offsets[i - 1] + lengths[i - 1] + spacing[i - 1];
}

// Every change to the stack view's views or settings ends here.
- (void) _arrangeViews {
    _keepsDecodedFrames = NO;
    // Detaching or reattaching views for lack of room arranges the views again.
    if ([self _updateDroppedViews])
        return;

    NSArray *attached = [self _attachedEntries];
    NSUInteger i, count = [attached count];

    if (count == 0)
        return;
    if ([self _constraintArrangementIsActive]) {
        [self setNeedsUpdateConstraints: YES];
        return;
    }

    NSRect bounds = [self bounds];
    BOOL vertical = [self _isVertical], flipped = [self isFlipped];
    CGFloat mainLength, crossLength, crossStart;
    CGFloat offsets[count], lengths[count], crosses[count];
    NSLayoutAttribute alignment = [self alignment];

    if (vertical) {
        mainLength = NSHeight(bounds) - _edgeInsets.top - _edgeInsets.bottom;
        crossLength = NSWidth(bounds) - _edgeInsets.left - _edgeInsets.right;
        crossStart = NSMinX(bounds) + _edgeInsets.left;
        if ([self _alignmentIsVertical: alignment])
            alignment = NSLayoutAttributeCenterX;
    } else {
        mainLength = NSWidth(bounds) - _edgeInsets.left - _edgeInsets.right;
        crossLength = NSHeight(bounds) - _edgeInsets.top - _edgeInsets.bottom;
        crossStart = NSMinY(bounds) + (flipped ? _edgeInsets.top : _edgeInsets.bottom);
        if (![self _alignmentIsVertical: alignment])
            alignment = NSLayoutAttributeCenterY;
    }

    for (i = 0; i < count; i++) {
        StackSize size = [self _naturalSizeOfEntry: [attached objectAtIndex: i]];

        lengths[i] = size.main;
        crosses[i] = size.cross;
    }
    [self _computeOffsets: offsets lengths: lengths forEntries: attached length: mainLength];

    for (i = 0; i < count; i++) {
        NSStackViewEntry *entry = [attached objectAtIndex: i];
        CGFloat cross = crosses[i], crossOffset;
        NSRect frame;

        // Baselines are not tracked; first and last baseline align like top and bottom.
        switch (alignment) {
        case NSLayoutAttributeWidth:
        case NSLayoutAttributeHeight:
            cross = MAX(0, crossLength);
            crossOffset = 0;
            break;
        case NSLayoutAttributeLeading:
        case NSLayoutAttributeLeft:
            crossOffset = 0;
            break;
        case NSLayoutAttributeTrailing:
        case NSLayoutAttributeRight:
            crossOffset = crossLength - cross;
            break;
        case NSLayoutAttributeTop:
        case NSLayoutAttributeFirstBaseline:
            crossOffset = flipped ? 0 : crossLength - cross;
            break;
        case NSLayoutAttributeBottom:
        case NSLayoutAttributeBaseline:
            crossOffset = flipped ? crossLength - cross : 0;
            break;
        default:
            crossOffset = (crossLength - cross) / 2;
            break;
        }

        if (vertical) {
            CGFloat y = flipped ? NSMinY(bounds) + _edgeInsets.top + offsets[i]
                                : NSMaxY(bounds) - _edgeInsets.top - offsets[i] - lengths[i];
            frame = NSMakeRect(crossStart + crossOffset, y, cross, lengths[i]);
        } else {
            frame = NSMakeRect(NSMinX(bounds) + _edgeInsets.left + offsets[i],
                               crossStart + crossOffset, lengths[i], cross);
        }
        [entry->view setFrame: [self _frameAlignedToPixels: frame]];
        entry->assignedSize = [entry->view frame].size;
    }
    [self setNeedsDisplay: YES];
}

// Frames that Auto Layout computes are rounded to whole device pixels at the edges, so a view
// of the same size can come out one pixel wider than its neighbour. Not documented. Evidence:
// black-box observation of NSStackView frames on macOS 10.14.4 and 26.7.3 (tier 2): equal
// spacing of three views in 300 points puts the middle one at 93, not at 93.33.
// Test: appkit-stack-view-gravity-areas.m (test_quirk_pixel_aligned_frames)
- (NSRect) _frameAlignedToPixels: (NSRect) frame {
    CGFloat scale = [[self window] backingScaleFactor];
    CGFloat left, right, bottom, top;

    if (scale < 1)
        scale = 1;
    left = floor(NSMinX(frame) * scale + 0.5) / scale;
    right = floor(NSMaxX(frame) * scale + 0.5) / scale;
    bottom = floor(NSMinY(frame) * scale + 0.5) / scale;
    top = floor(NSMaxY(frame) * scale + 0.5) / scale;
    return NSMakeRect(left, bottom, right - left, top - bottom);
}

#pragma mark - Visibility priorities and the room for views

// QUIRK: a stack view whose clipping resistance (in its stacking direction) is below that of a
// view's compression resistance, 750, and is too small for its views, detaches the views whose
// visibility priority is below MustHold, the lowest priority first and the views of equal priority
// together, until what is left fits or only MustHold views are left. It reattaches them when there
// is room again. The delegate is told as for any detaching. The detached views stay as they are
// (macOS 26.7.3 also hides them). With the default clipping resistance the views are compressed
// instead, which this stack view does not do. Not documented. Evidence: black-box observation of
// NSStackView on macOS 10.14.4 and 26.7.3 (tier 2), probe mac-probes/stackview-gravity-layout.m
// of the research notes. Test: appkit-stack-view-gravity-areas.m (test_quirk_visibility_priority_drop)
// Returns whether the views detached or reattached changed.
- (BOOL) _updateDroppedViews {
    NSLayoutConstraintOrientation axis = [self _isVertical] ? NSLayoutConstraintOrientationVertical
                                                            : NSLayoutConstraintOrientationHorizontal;
    NSSize size = [self bounds].size;
    CGFloat available = [self _isVertical] ? size.height : size.width;
    NSMutableArray *candidates = [NSMutableArray array];
    BOOL changed = NO;

    if (_keepsDecodedFrames)
        return NO;
    // A stack view that has no size yet has not been laid out; nothing is too big for it.
    if (available > 0 && [self clippingResistancePriorityForOrientation: axis] < NSLayoutPriorityDefaultHigh) {
        for (NSStackViewEntry *entry in _entries)
            if (![self _isDetachedByState: entry])
                [candidates addObject: entry];
        while ([self _fittingMainLengthForEntries: candidates] > available) {
            NSStackViewVisibilityPriority lowest = NSStackViewVisibilityPriorityMustHold;

            for (NSStackViewEntry *entry in candidates)
                lowest = MIN(lowest, entry->visibilityPriority);
            if (lowest >= NSStackViewVisibilityPriorityMustHold)
                break;
            for (NSStackViewEntry *entry in [[candidates copy] autorelease])
                if (entry->visibilityPriority == lowest)
                    [candidates removeObjectIdenticalTo: entry];
        }
    } else {
        for (NSStackViewEntry *entry in _entries)
            if (![self _isDetachedByState: entry])
                [candidates addObject: entry];
    }

    for (NSStackViewEntry *entry in _entries) {
        BOOL dropped = ![self _isDetachedByState: entry] && ![candidates containsObject: entry];

        if (entry->dropped != dropped) {
            entry->dropped = dropped;
            changed = YES;
        }
    }
    if (changed)
        [self _updateAttachment];
    return changed;
}

// Arranged views are placed by the stack view, not by their autoresizing masks.
// Decoded views keep their autoresizing until the stack view first changes.
- (void) resizeSubviewsWithOldSize: (NSSize) oldSize {
    if (_keepsDecodedFrames) {
        [super resizeSubviewsWithOldSize: oldSize];
        return;
    }
    for (NSView *view in [self subviews])
        if ([self _entryForView: view] == nil)
            [view resizeWithOldSuperviewSize: oldSize];
    // The arrangement constraints do not depend on the stack view's size.
    if (![self _constraintArrangementIsActive])
        [self _arrangeViews];
}

// An arranged view whose content changed has another natural size; the arrangement is redone at the
// next layout pass, and the stack's own intrinsic size changes with it. The arrangement constraints
// depend on the natural sizes, so they are made again.
- (void) _subviewIntrinsicContentSizeDidChange: (NSView *) subview {
    if (_changingViews || [self _entryForView: subview] == nil)
        return;
    if ([self _constraintArrangementIsActive])
        [self setNeedsUpdateConstraints: YES];
    [self setNeedsLayout: YES];
    [self invalidateIntrinsicContentSize];
}

// A view that hugs its content differently takes the room left over in another way.
- (void) _subviewContentHuggingPriorityDidChange: (NSView *) subview {
    if (_changingViews || [self _entryForView: subview] == nil)
        return;
    [self setNeedsLayout: YES];
    if ([self _constraintArrangementIsActive])
        [self setNeedsUpdateConstraints: YES];
}

- (void) layout {
    // Views arranged by constraints are placed by the layout engine; it only has to be told when
    // views no longer fit. Asking for new constraints on every pass would start another layout
    // pass after each one, so the dropped views only change what is attached when they change.
    if (!_keepsDecodedFrames && [self _constraintArrangementIsActive])
        [self _updateDroppedViews];
    else if (!_keepsDecodedFrames)
        [self _arrangeViews];
    [super layout];
}

#pragma mark - Constraint-based arrangement

static const char arrangementConstraintsKey;
static const char constraintModeKey;

// When an arranged view takes part in Auto Layout (it has constraints of its
// own, or the client turned its autoresizing translation off), the stack view
// arranges all its views with constraints, as the engine would otherwise pin
// the frames this stack view set and report the view's own constraints as
// unsatisfiable. A stack view whose arranged views are all frame-based keeps
// arranging them by frames.
- (BOOL) _entryTakesPartInAutoLayout: (NSStackViewEntry *) entry {
    NSView *view = entry->view;

    if (![view translatesAutoresizingMaskIntoConstraints] && !entry->tamicSetByStack)
        return YES;
    return [[view constraints] count] != 0;
}

- (BOOL) _constraintArrangementIsActive {
    if (_keepsDecodedFrames)
        return NO;
    // A stack view that Auto Layout places is laid out by constraints throughout: on macOS its
    // views are arranged by constraints, and with equal hugging priorities the first view of a
    // fill distribution stretches there, while a stack view laid out by frames stretches the last
    // (observed on macOS 26.7.3 and 10.14.4; tests appkit-stack-view-constraint-arrangement and
    // appkit-stack-view-layout).
    if (![self translatesAutoresizingMaskIntoConstraints] && [_entries count] != 0)
        return YES;
    for (NSStackViewEntry *entry in _entries)
        if (!entry->detached && [self _entryTakesPartInAutoLayout: entry])
            return YES;
    return NO;
}

// Arranged views of a constraint-arranged stack view are placed by constraints,
// so their autoresizing translation is turned off; it is turned back on for
// the views this stack view changed when it returns to frame arrangement.
- (void) _applyArrangementMode: (BOOL) active {
    for (NSStackViewEntry *entry in _entries) {
        if (active && !entry->detached && [entry->view translatesAutoresizingMaskIntoConstraints]) {
            [entry->view setTranslatesAutoresizingMaskIntoConstraints: NO];
            entry->tamicSetByStack = YES;
        } else if (!active && entry->tamicSetByStack) {
            [entry->view setTranslatesAutoresizingMaskIntoConstraints: YES];
            entry->tamicSetByStack = NO;
        }
    }
    objc_setAssociatedObject(self, &constraintModeKey, active ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// The constraints of an arranged view can change without telling the stack view.
- (void) updateConstraintsForSubtreeIfNeeded {
    BOOL active = [self _constraintArrangementIsActive];
    BOOL was = objc_getAssociatedObject(self, &constraintModeKey) != nil;

    if (active != was)
        [self setNeedsUpdateConstraints: YES];
    [super updateConstraintsForSubtreeIfNeeded];
}

static NSLayoutConstraint *arrangeConstraint(id item, NSLayoutAttribute attribute, NSLayoutRelation relation,
                                             id other, NSLayoutAttribute otherAttribute,
                                             CGFloat constant, NSLayoutPriority priority) {
    NSLayoutConstraint *constraint = [NSLayoutConstraint constraintWithItem: item attribute: attribute relatedBy: relation
                                                                     toItem: other attribute: otherAttribute
                                                                 multiplier: 1 constant: constant];

    [constraint setPriority: priority];
    return constraint;
}

// Priorities of the constraints this stack view creates. Edge containment and
// fixed spacing are high but not required, so a view that insists on a size
// the stack cannot give breaks a stack constraint instead of making the whole
// window's layout unsatisfiable.
static const NSLayoutPriority HighPriority = NSLayoutPriorityRequired - 1;
static const NSLayoutPriority GravityEdgePriority = 750;
static const NSLayoutPriority GravitySpacingPriority = 749.99;
static const NSLayoutPriority GravityCenterPriority = 748;
// Just below the default content hugging priority.
static const NSLayoutPriority GravityAreaGapPriority = 249.5;
static const NSLayoutPriority CrossAlignmentPriority = 260;
// Below the default content hugging priority, so a stack view that is larger
// than its views does not stretch views that hug their content.
static const NSLayoutPriority SizingPriority = 249;

- (CGFloat) _mainSizeForConstraints: (NSView *) view {
    NSSize intrinsic = [view intrinsicContentSize];
    CGFloat size = [self _isVertical] ? intrinsic.height : intrinsic.width;

    return size != NSViewNoIntrinsicMetric ? size : -1;
}

- (NSArray *) _arrangementConstraintsForEntries: (NSArray *) entries {
    NSMutableArray *created = [NSMutableArray array];
    NSUInteger i, count = [entries count];
    BOOL vertical = [self _isVertical];
    NSLayoutAttribute start = vertical ? NSLayoutAttributeTop : NSLayoutAttributeLeading;
    NSLayoutAttribute end = vertical ? NSLayoutAttributeBottom : NSLayoutAttributeTrailing;
    NSLayoutAttribute length = vertical ? NSLayoutAttributeHeight : NSLayoutAttributeWidth;
    NSLayoutAttribute crossStart = vertical ? NSLayoutAttributeLeading : NSLayoutAttributeTop;
    NSLayoutAttribute crossEnd = vertical ? NSLayoutAttributeTrailing : NSLayoutAttributeBottom;
    NSLayoutAttribute crossCenter = vertical ? NSLayoutAttributeCenterX : NSLayoutAttributeCenterY;
    CGFloat insetStart = vertical ? _edgeInsets.top : _edgeInsets.left;
    CGFloat insetEnd = vertical ? _edgeInsets.bottom : _edgeInsets.right;
    CGFloat insetCrossStart = vertical ? _edgeInsets.left : _edgeInsets.top;
    CGFloat insetCrossEnd = vertical ? _edgeInsets.right : _edgeInsets.bottom;
    NSLayoutConstraintOrientation axis = vertical ? NSLayoutConstraintOrientationVertical
                                                  : NSLayoutConstraintOrientationHorizontal;
    BOOL gravityAreas = _distribution == NSStackViewDistributionGravityAreas;
    NSLayoutAttribute alignment = [self alignment];

    // An alignment for the other axis is ignored, as when frames are used.
    if ([self _alignmentIsVertical: alignment] == vertical)
        alignment = crossCenter;
    switch (alignment) {
    case NSLayoutAttributeLeft: alignment = NSLayoutAttributeLeading; break;
    case NSLayoutAttributeRight: alignment = NSLayoutAttributeTrailing; break;
    case NSLayoutAttributeFirstBaseline: alignment = NSLayoutAttributeTop; break;
    case NSLayoutAttributeBaseline: alignment = NSLayoutAttributeBottom; break;
    // Width and height are not alignments of a stack view; the views end up at the far edge.
    case NSLayoutAttributeWidth:
    case NSLayoutAttributeHeight: alignment = crossEnd; break;
    default: break;
    }

    // Cross axis: contained in the stack view, aligned, and wrapped by it when
    // the stack view has no size of its own.
    for (i = 0; i < count; i++) {
        NSView *view = ((NSStackViewEntry *) [entries objectAtIndex: i])->view;

        [created addObject: arrangeConstraint(view, crossStart, NSLayoutRelationGreaterThanOrEqual, self, crossStart, insetCrossStart, HighPriority)];
        [created addObject: arrangeConstraint(view, crossEnd, NSLayoutRelationLessThanOrEqual, self, crossEnd, -insetCrossEnd, HighPriority)];
        [created addObject: arrangeConstraint(view, crossStart, NSLayoutRelationEqual, self, crossStart, insetCrossStart, SizingPriority)];
        [created addObject: arrangeConstraint(view, crossEnd, NSLayoutRelationEqual, self, crossEnd, -insetCrossEnd, SizingPriority)];
        if (alignment == crossStart)
            [created addObject: arrangeConstraint(view, crossStart, NSLayoutRelationEqual, self, crossStart, insetCrossStart, HighPriority)];
        if (alignment == crossEnd)
            [created addObject: arrangeConstraint(view, crossEnd, NSLayoutRelationEqual, self, crossEnd, -insetCrossEnd, HighPriority)];
        if (alignment == crossCenter)
            [created addObject: arrangeConstraint(view, crossCenter, NSLayoutRelationEqual, self, crossCenter, 0, CrossAlignmentPriority)];
    }

    // Main axis: the ends, and the gap after each view but the last.
    NSStackViewEntry *first = [entries objectAtIndex: 0], *last = [entries lastObject];

    // The stack view's clipping resistance is how strongly it holds its views inside; below the
    // views' own resistance to compression they overflow instead of shrinking.
    NSLayoutPriority holdPriority = MIN(HighPriority, [self clippingResistancePriorityForOrientation: axis]);

    [created addObject: arrangeConstraint(first->view, start, NSLayoutRelationGreaterThanOrEqual, self, start, insetStart, holdPriority)];
    [created addObject: arrangeConstraint(last->view, end, NSLayoutRelationLessThanOrEqual, self, end, -insetEnd, holdPriority)];
    if (gravityAreas) {
        [created addObject: arrangeConstraint(first->view, start, NSLayoutRelationEqual, self, start, insetStart,
                                              first->gravity == NSStackViewGravityLeading ? GravityEdgePriority : SizingPriority)];
        [created addObject: arrangeConstraint(last->view, end, NSLayoutRelationEqual, self, end, -insetEnd,
                                              last->gravity == NSStackViewGravityTrailing ? GravityEdgePriority : SizingPriority)];
    } else {
        [created addObject: arrangeConstraint(first->view, start, NSLayoutRelationEqual, self, start, insetStart, HighPriority)];
        [created addObject: arrangeConstraint(last->view, end, NSLayoutRelationEqual, self, end, -insetEnd, HighPriority)];
    }

    for (i = 0; i + 1 < count; i++) {
        NSStackViewEntry *entry = [entries objectAtIndex: i], *next = [entries objectAtIndex: i + 1];
        CGFloat gap = [self _spacingAfter: entry];

        [created addObject: arrangeConstraint(next->view, start, NSLayoutRelationGreaterThanOrEqual, entry->view, end, gap, HighPriority)];
        if (!gravityAreas)
            // Equal spacing and equal centering are arranged like fill here: the
            // constraint engine has no layout guides to space the views evenly.
            [created addObject: arrangeConstraint(next->view, start, NSLayoutRelationEqual, entry->view, end, gap, HighPriority)];
        else if (entry->gravity == next->gravity)
            [created addObject: arrangeConstraint(next->view, start, NSLayoutRelationEqual, entry->view, end, gap, GravitySpacingPriority)];
        else
            // The room between two areas is taken by a view that hugs below the default priority
            // (see -_stretchGravityAreas:...), and by nothing that hugs at it or above.
            [created addObject: arrangeConstraint(next->view, start, NSLayoutRelationEqual, entry->view, end, gap, GravityAreaGapPriority)];
    }

    if (gravityAreas) {
        // The center area is centered in the stack view, from the sizes its views have now.
        NSInteger firstCenter = -1, lastCenter = -1;
        CGFloat groupLength = 0;

        for (i = 0; i < count; i++) {
            NSStackViewEntry *entry = [entries objectAtIndex: i];
            CGFloat size = [self _mainSizeForConstraints: entry->view];

            if (entry->gravity != NSStackViewGravityCenter)
                continue;
            if (firstCenter < 0)
                firstCenter = i;
            else
                groupLength += [self _spacingAfter: [entries objectAtIndex: lastCenter]];
            lastCenter = i;
            groupLength += size >= 0 ? size : (vertical ? NSHeight([entry->view frame]) : NSWidth([entry->view frame]));
        }
        if (firstCenter >= 0)
            [created addObject: arrangeConstraint(((NSStackViewEntry *) [entries objectAtIndex: firstCenter])->view, start,
                                                  NSLayoutRelationEqual, self, vertical ? NSLayoutAttributeCenterY : NSLayoutAttributeCenterX,
                                                  -groupLength / 2, GravityCenterPriority)];
    } else {
        // Views that hug their content least take the space the stack view has
        // to spare. With equal priorities the earlier view takes it: the later
        // views get a slightly stronger hold on their size.
        for (i = 1; i < count; i++) {
            NSView *view = ((NSStackViewEntry *) [entries objectAtIndex: i])->view;
            CGFloat size = [self _mainSizeForConstraints: view];

            if (size >= 0)
                [created addObject: arrangeConstraint(view, length, NSLayoutRelationLessThanOrEqual, nil, NSLayoutAttributeNotAnAttribute,
                                                      size, MIN(HighPriority, [view contentHuggingPriorityForOrientation: axis] + 0.5))];
        }

        if (_distribution == NSStackViewDistributionFillEqually || _distribution == NSStackViewDistributionFillProportionally) {
            NSView *base = first->view;
            CGFloat baseSize = [self _mainSizeForConstraints: base];

            for (i = 1; i < count; i++) {
                NSView *view = ((NSStackViewEntry *) [entries objectAtIndex: i])->view;
                CGFloat size = [self _mainSizeForConstraints: view];
                CGFloat multiplier = 1;
                NSLayoutConstraint *equal;

                if (_distribution == NSStackViewDistributionFillProportionally && baseSize > 0 && size > 0)
                    multiplier = size / baseSize;
                equal = [NSLayoutConstraint constraintWithItem: view attribute: length relatedBy: NSLayoutRelationEqual
                                                        toItem: base attribute: length multiplier: multiplier constant: 0];
                [equal setPriority: HighPriority];
                [created addObject: equal];
            }
        }
    }
    return created;
}

- (void) updateConstraints {
    NSArray *old = objc_getAssociatedObject(self, &arrangementConstraintsKey);

    if (old != nil) {
        [[old retain] autorelease];
        objc_setAssociatedObject(self, &arrangementConstraintsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self removeConstraints: old];
    }

    BOOL active = [self _constraintArrangementIsActive];

    [self _applyArrangementMode: active];
    // Without arranged views (all of them detached) there is nothing to constrain.
    if (active && [[self _attachedEntries] count] != 0) {
        NSArray *created = [self _arrangementConstraintsForEntries: [self _attachedEntries]];

        [self addConstraints: created];
        objc_setAssociatedObject(self, &arrangementConstraintsKey, created, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [super updateConstraints];
}

@end
