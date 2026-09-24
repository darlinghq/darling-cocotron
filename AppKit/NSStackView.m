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
#import <Foundation/NSArray.h>
#import <Foundation/NSException.h>
#import <Foundation/NSKeyValueObserving.h>

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
    NSSize naturalSize, assignedSize;
}
@end

@implementation NSStackViewEntry
- (void) dealloc {
    [view release];
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
    _detachesHiddenViews = YES;
    _entries = [[NSMutableArray alloc] init];
}

- (instancetype) initWithFrame: (NSRect) frame {
    if ((self = [super initWithFrame: frame]) != nil)
        [self _setUpStackView];
    return self;
}

// Nib settings and arranged views are not decoded; decoded subviews stay plain subviews.
- (instancetype) initWithCoder: (NSCoder *) coder {
    if ((self = [super initWithCoder: coder]) != nil)
        [self _setUpStackView];
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
    entry = [[NSStackViewEntry alloc] init];
    entry->view = [view retain];
    entry->gravity = gravity;
    entry->spacingAfter = NSStackViewSpacingUseDefault;
    entry->visibilityPriority = NSStackViewVisibilityPriorityMustHold;
    entry->detached = [self _shouldDetach: entry];
    entry->naturalSize = entry->assignedSize = [view frame].size;
    [_entries insertObject: entry atIndex: start + index];
    [entry release];
    [view addObserver: self forKeyPath: @"hidden" options: 0 context: HiddenContext];
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

// Views never detach for lack of space: that needs clipping resistance below
// required, which this stack view does not support.
- (BOOL) _shouldDetach: (NSStackViewEntry *) entry {
    return entry->visibilityPriority == NSStackViewVisibilityPriorityNotVisible ||
           (_detachesHiddenViews && [entry->view isHidden]);
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
    for (NSView *view in reattach) {
        [self _entryForView: view]->detached = NO;
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

- (NSSize) intrinsicContentSize {
    NSArray *attached = [self _attachedEntries];
    NSUInteger i, count = [attached count];
    CGFloat main = 0, cross = 0;

    for (i = 0; i < count; i++) {
        NSStackViewEntry *entry = [attached objectAtIndex: i];
        StackSize size = [self _naturalSizeOfEntry: entry];

        main += size.main + (i + 1 < count ? [self _spacingAfter: entry] : 0);
        cross = MAX(cross, size.cross);
    }
    if ([self _isVertical])
        return NSMakeSize(cross + _edgeInsets.left + _edgeInsets.right,
                          main + _edgeInsets.top + _edgeInsets.bottom);
    return NSMakeSize(main + _edgeInsets.left + _edgeInsets.right,
                      cross + _edgeInsets.top + _edgeInsets.bottom);
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

        // The view that hugs its content least absorbs the extra or missing space.
        for (i = 1; i < count; i++)
            if ([((NSStackViewEntry *) [entries objectAtIndex: i])->view
                        contentHuggingPriorityForOrientation: axis] <=
                [((NSStackViewEntry *) [entries objectAtIndex: flexible])->view
                        contentHuggingPriorityForOrientation: axis])
                flexible = i;
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
        // first[g]..last[g] (inclusive) are gravity g's entries; last[g] < first[g] when empty.
        NSInteger first[4] = {0, 0, 0, 0}, last[4] = {-1, -1, -1, -1};
        CGFloat start[4], groupLength[4] = {0, 0, 0, 0}, end = 0;
        NSStackViewGravity g, previous = 0;

        for (g = NSStackViewGravityLeading; g <= NSStackViewGravityTrailing; g++)
            first[g] = count;
        for (i = 0; i < count; i++) {
            g = ((NSStackViewEntry *) [entries objectAtIndex: i])->gravity;
            first[g] = MIN(first[g], (NSInteger) i);
            last[g] = i;
        }
        for (g = NSStackViewGravityLeading; g <= NSStackViewGravityTrailing; g++)
            for (i = first[g]; (NSInteger) i <= last[g]; i++)
                groupLength[g] += lengths[i] + ((NSInteger) i < last[g] ? spacing[i] : 0);

        start[NSStackViewGravityLeading] = 0;
        start[NSStackViewGravityTrailing] = length - groupLength[NSStackViewGravityTrailing];
        // The center area stays centered unless that would crowd a neighbouring area.
        start[NSStackViewGravityCenter] = (length - groupLength[NSStackViewGravityCenter]) / 2;
        if (last[NSStackViewGravityCenter] >= 0 && last[NSStackViewGravityTrailing] >= 0)
            start[NSStackViewGravityCenter] = MIN(start[NSStackViewGravityCenter],
                    start[NSStackViewGravityTrailing] - spacing[last[NSStackViewGravityCenter]] -
                            groupLength[NSStackViewGravityCenter]);

        for (g = NSStackViewGravityLeading; g <= NSStackViewGravityTrailing; g++) {
            CGFloat position;

            if (last[g] < 0)
                continue;
            position = previous ? MAX(start[g], end + spacing[last[previous]]) : start[g];
            for (i = first[g]; (NSInteger) i <= last[g]; i++) {
                offsets[i] = position;
                position += lengths[i] + spacing[i];
            }
            end = offsets[last[g]] + lengths[last[g]];
            previous = g;
        }
        return;
    }

    offsets[0] = 0;
    for (i = 1; i < count; i++)
        offsets[i] = offsets[i - 1] + lengths[i - 1] + spacing[i - 1];
}

- (void) _arrangeViews {
    NSArray *attached = [self _attachedEntries];
    NSUInteger i, count = [attached count];

    if (count == 0)
        return;

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
        [entry->view setFrame: frame];
        entry->assignedSize = frame.size;
    }
    [self setNeedsDisplay: YES];
}

// Arranged views are placed by the stack view, not by their autoresizing masks.
- (void) resizeSubviewsWithOldSize: (NSSize) oldSize {
    for (NSView *view in [self subviews])
        if ([self _entryForView: view] == nil)
            [view resizeWithOldSuperviewSize: oldSize];
    [self _arrangeViews];
}

- (void) layout {
    [self _arrangeViews];
    [super layout];
}

@end
