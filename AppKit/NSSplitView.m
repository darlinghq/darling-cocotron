/* Copyright (c) 2006-2007 Christopher J. W. Lloyd
                 2009 Markus Hitter <mah@jump-ing.de>

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <AppKit/NSColor.h>
#import <AppKit/NSCursor.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSRaise.h>
#import <AppKit/NSSplitView.h>
#import <AppKit/NSWindow.h>
#import <Foundation/NSKeyedArchiver.h>
#import <Foundation/NSRaise.h>
#import <Foundation/NSUserDefaults.h>
#import <AppKit/NSLayoutConstraint.h>
#import <objc/runtime.h>

NSString *const NSSplitViewDidResizeSubviewsNotification =
        @"NSSplitViewDidResizeSubviewsNotification";
NSString *const NSSplitViewWillResizeSubviewsNotification =
        @"NSSplitViewWillResizeSubviewsNotification";

@implementation NSSplitView

- (void) encodeWithCoder: (NSCoder *) coder {
    NSUnimplementedMethod();
}

- initWithCoder: (NSCoder *) coder {
    [super initWithCoder: coder];

    if ([coder allowsKeyedCoding]) {
        NSKeyedUnarchiver *keyed = (NSKeyedUnarchiver *) coder;

        NS_EXTRA(NSSplitView, self)->_isVertical = [keyed decodeBoolForKey: @"NSIsVertical"];
        // The divider thickness in the nib may not be the same as ours
        [self resizeSubviewsWithOldSize: [self bounds].size];
    } else {
        // The delegate (a one-object group up to version 16), and from version 348 a
        // byte whose bit 0 is the vertical flag (its other bits do not change the
        // divider style: that is not archived).
        NSInteger version = [coder versionForClassName: @"NSSplitView"];
        id delegate = nil;
        char flags = 0;

        if (version <= 16) {
            [coder decodeValuesOfObjCTypes: "@", &delegate];
            [delegate autorelease];
        } else {
            delegate = [coder decodeObject];
        }
        if (version >= 348) {
            [coder decodeValueOfObjCType: @encode(char) at: &flags];
        }
        NS_EXTRA(NSSplitView, self)->_isVertical = (flags & 1) ? YES : NO;
        [self setDelegate: delegate];
    }

    return self;
}

- (void) dealloc {
    [NS_EXTRA(NSSplitView, self)->_autosaveName release];
    [NS_EXTRA(NSSplitView, self)->_explicitArranged release];
    NS_EXTRA_FREE(NSSplitView, self);
    [super dealloc];
}

- (id) delegate {
    return NS_EXTRA(NSSplitView, self)->_delegate;
}

- (BOOL) isVertical {
    return NS_EXTRA(NSSplitView, self)->_isVertical;
}

- (void) _postNoteWillResize {
    [[NSNotificationCenter defaultCenter]
            postNotificationName: NSSplitViewWillResizeSubviewsNotification
                          object: self];
}

- (void) _postNoteDidResize {
    [[NSNotificationCenter defaultCenter]
            postNotificationName: NSSplitViewDidResizeSubviewsNotification
                          object: self];
}

- (void) setDelegate: (id) delegate {
    if ([NS_EXTRA(NSSplitView, self)->_delegate respondsToSelector: @selector(splitViewDidResizeSubviews:)])
        [[NSNotificationCenter defaultCenter]
                removeObserver: NS_EXTRA(NSSplitView, self)->_delegate
                          name: NSSplitViewDidResizeSubviewsNotification
                        object: self];
    if ([NS_EXTRA(NSSplitView, self)->_delegate respondsToSelector: @selector(splitViewWillResizeSubviews:)])
        [[NSNotificationCenter defaultCenter]
                removeObserver: NS_EXTRA(NSSplitView, self)->_delegate
                          name: NSSplitViewWillResizeSubviewsNotification
                        object: self];

    NS_EXTRA(NSSplitView, self)->_delegate = delegate;

    if ([NS_EXTRA(NSSplitView, self)->_delegate respondsToSelector: @selector(splitViewDidResizeSubviews:)])
        [[NSNotificationCenter defaultCenter]
                addObserver: NS_EXTRA(NSSplitView, self)->_delegate
                   selector: @selector(splitViewDidResizeSubviews:)
                       name: NSSplitViewDidResizeSubviewsNotification
                     object: self];
    if ([NS_EXTRA(NSSplitView, self)->_delegate respondsToSelector: @selector(splitViewWillResizeSubviews:)])
        [[NSNotificationCenter defaultCenter]
                addObserver: NS_EXTRA(NSSplitView, self)->_delegate
                   selector: @selector(splitViewWillResizeSubviews:)
                       name: NSSplitViewWillResizeSubviewsNotification
                     object: self];
}

- (void) setVertical: (BOOL) flag {
    if (NS_EXTRA(NSSplitView, self)->_isVertical == flag) {
        // Don't do unneccessary work
        return;
    }
    NS_EXTRA(NSSplitView, self)->_isVertical = flag;
    [self setNeedsUpdateConstraints: YES];

    // Now get the split axis sorted
    [self adjustSubviews];
}

- (BOOL) isFlipped {
    return YES;
}

- (BOOL) isSubviewCollapsed: (NSView *) subview {

    /* From Apple's header comments:
     * Collapsed subviews are hidden but retained by the split view.
     * Collapsing of a subview will not change its bounds, but may set its frame
     * to zero pixels high (in horizontal split views) or zero pixels wide
     * (vertical).
     */
    return [subview isHidden];
}

- (void) setDividerStyle: (NSSplitViewDividerStyle) style {
    NS_EXTRA(NSSplitView, self)->_dividerStyle = style;
    [self setNeedsUpdateConstraints: YES];
    [self setNeedsDisplay: YES];
}

- (NSSplitViewDividerStyle) dividerStyle {
    return NS_EXTRA(NSSplitView, self)->_dividerStyle;
}

// The autosaved layout is this implementation's own format; Apple does not
// document its format and applications only name the layout. A defaults array
// holds, for every divider, the leading subview's length as a fraction of the
// space not taken by dividers.
static NSString *autosaveKey(NSString *name) {
    return [@"NSSplitView Divider Fractions " stringByAppendingString: name];
}

- (CGFloat) _lengthOfSubview: (NSView *) view {
    if ([self isSubviewCollapsed: view])
        return 0;
    return [self isVertical] ? NSWidth([view frame]) : NSHeight([view frame]);
}

- (CGFloat) _spaceForSubviews {
    NSSize size = [self bounds].size;
    CGFloat length = [self isVertical] ? size.width : size.height;

    return length - [self dividerThickness] * ([[self _arrangedList] count] - 1);
}

- (NSString *) autosaveName {
    return NS_EXTRA(NSSplitView, self)->_autosaveName;
}

- (void) setAutosaveName: (NSString *) name {
    if ([name length] == 0)
        name = nil;
    name = [name copy];
    [NS_EXTRA(NSSplitView, self)->_autosaveName release];
    NS_EXTRA(NSSplitView, self)->_autosaveName = name;
    [self _restoreDividerPositions];
}

- (void) _restoreDividerPositions {
    NSUInteger i, count = [[self _arrangedList] count];
    CGFloat space = [self _spaceForSubviews], position = 0;
    NSArray *saved;

    if (NS_EXTRA(NSSplitView, self)->_autosaveName == nil || count < 2 || space <= 0)
        return;
    // Each setPosition: below saves the layout again, replacing this entry.
    saved = [[[[NSUserDefaults standardUserDefaults]
            arrayForKey: autosaveKey(NS_EXTRA(NSSplitView, self)->_autosaveName)] retain] autorelease];
    if ([saved count] != count - 1)
        return;
    for (id fraction in saved)
        if (![fraction isKindOfClass: [NSNumber class]])
            return;

    for (i = 0; i + 1 < count; i++) {
        position += [[saved objectAtIndex: i] doubleValue] * space;
        [self setPosition: position ofDividerAtIndex: i];
        position += [self dividerThickness];
    }
}

- (void) _autosaveSubviewLayoutIfNecessary {
    NSUInteger i, count = [[self _arrangedList] count];
    CGFloat space = [self _spaceForSubviews];
    NSMutableArray *saved;

    if (NS_EXTRA(NSSplitView, self)->_autosaveName == nil || count < 2 || space <= 0)
        return;
    saved = [NSMutableArray array];
    for (i = 0; i + 1 < count; i++)
        [saved addObject: [NSNumber numberWithDouble:
                        [self _lengthOfSubview: [[self _arrangedList] objectAtIndex: i]] / space]];
    [[NSUserDefaults standardUserDefaults] setObject: saved
                                              forKey: autosaveKey(NS_EXTRA(NSSplitView, self)->_autosaveName)];
}

static const char holdingPriorityKey;
static const char preferredLengthKey;

// The length the constraint-based layout keeps for a subview: its length when it
// was arranged, and after that the length the user (or the API) last gave it.
- (CGFloat) _preferredLengthOfSubview: (NSView *) subview {
    NSNumber *length = objc_getAssociatedObject(subview, &preferredLengthKey);

    if (length != nil)
        return [length doubleValue];
    return [self isVertical] ? NSWidth([subview frame]) : NSHeight([subview frame]);
}

- (void) _recordPreferredLengthOfSubview: (NSView *) subview {
    CGFloat length = [self isVertical] ? NSWidth([subview frame]) : NSHeight([subview frame]);

    objc_setAssociatedObject(subview, &preferredLengthKey, [NSNumber numberWithDouble: length], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void) _recordPreferredLengths {
    NSView *subview;

    for (subview in [self _arrangedList])
        if (![self isSubviewCollapsed: subview])
            [self _recordPreferredLengthOfSubview: subview];
}

- (NSLayoutPriority) _holdingPriorityOfSubview: (NSView *) subview {
    NSNumber *priority = objc_getAssociatedObject(subview, &holdingPriorityKey);

    return priority != nil ? [priority floatValue] : NSLayoutPriorityDefaultLow;
}

// When the split view changes size and the visible arranged subviews do not
// all hold their size equally, the subviews with the lowest holding priority
// absorb the change first (in proportion to their current lengths), up to the
// point where they are empty; what is left over passes on to the next higher
// priority (only for constraint-based layout, see below). Returns the new length of every visible arranged subview, or nil
// when all of them have the same priority (then the proportional resize
// applies).
- (NSArray *) _lengthsByHoldingPriorityForTotal: (CGFloat) total {
    NSMutableArray *visible = [NSMutableArray array];
    NSView *subview;

    for (subview in [self _arrangedList])
        if (![self isSubviewCollapsed: subview])
            [visible addObject: subview];

    NSUInteger i, count = [visible count];
    BOOL differs = NO;
    BOOL constraintBased = ![self translatesAutoresizingMaskIntoConstraints];

    // QUIRK: holding priorities only count when the split view and its
    // subviews are laid out by constraints; a frame-based split view resizes
    // its subviews proportionally whatever the priorities are. Evidence: black-box
    // observation on macOS 26.7.3 (tier 2), recorded in the V605 section of
    // MAC-EVIDENCE.md. Test: appkit-split-view-holding-priority.m
    // (frame-based part and constraint-based part).
    if (!constraintBased)
        return nil;
    constraintBased = NO;
    for (i = 0; i < count; i++)
        if (![[visible objectAtIndex: i] translatesAutoresizingMaskIntoConstraints])
            constraintBased = YES;
    if (!constraintBased)
        return nil;

    for (i = 1; i < count; i++)
        if ([self _holdingPriorityOfSubview: [visible objectAtIndex: i]] !=
            [self _holdingPriorityOfSubview: [visible objectAtIndex: 0]])
            differs = YES;
    if (!differs)
        return nil;

    CGFloat lengths[count], priorities[count], before = 0;
    BOOL done[count];

    for (i = 0; i < count; i++) {
        NSRect frame = [[visible objectAtIndex: i] frame];

        lengths[i] = [self isVertical] ? NSWidth(frame) : NSHeight(frame);
        priorities[i] = [self _holdingPriorityOfSubview: [visible objectAtIndex: i]];
        done[i] = NO;
        before += lengths[i];
    }

    CGFloat remaining = total - before;

    for (NSUInteger pass = 0; pass < count && fabs(remaining) >= 1; pass++) {
        CGFloat lowest = 0, groupLength = 0;
        BOOL found = NO;

        for (i = 0; i < count; i++)
            if (!done[i] && (!found || priorities[i] < lowest)) {
                lowest = priorities[i];
                found = YES;
            }
        for (i = 0; i < count; i++)
            if (!done[i] && priorities[i] == lowest) {
                groupLength += lengths[i];
                done[i] = YES;
            }
        if (groupLength <= 0)
            continue;

        CGFloat newLength = MAX(0, groupLength + remaining), assigned = 0;
        NSInteger last = -1;

        for (i = 0; i < count; i++)
            if (priorities[i] == lowest) {
                lengths[i] = floor(lengths[i] * newLength / groupLength);
                assigned += lengths[i];
                last = i;
            }
        lengths[last] += newLength - assigned;
        remaining -= newLength - groupLength;
    }

    NSMutableArray *result = [NSMutableArray arrayWithCapacity: count];

    for (i = 0; i < count; i++)
        [result addObject: [NSNumber numberWithDouble: lengths[i]]];
    return result;
}

/** adjust all the non-collapsed subviews so that they are equally spaced
 * horizontally within the splitview */
- (void) _adjustSubviewWidths {
    // Set all the subview heights to the bounds height of the split view
    CGFloat height = NSHeight([self bounds]);

    int i, count = [[self _arrangedList] count];

    CGFloat totalWidthBefore = 0.;
    NSUInteger visibleCount = 0;
    BOOL hasEmptySubview = NO;

    // The available width to the subviews
    CGFloat totalWidthAfter =
            [self bounds].size.width - [self dividerThickness] * (count - 1);

    for (i = 0; i < count; i++) {
        NSView *subview = [[self _arrangedList] objectAtIndex: i];
        if ([self isSubviewCollapsed: subview] == NO) {
            ++visibleCount;
            if (NSWidth([subview frame]) <= 0)
                hasEmptySubview = YES;
            totalWidthBefore += NSWidth([subview frame]);
        }
    }

    if (visibleCount == 0)
        return;
    totalWidthAfter = MAX(0, NSWidth([self bounds]) -
                            [self dividerThickness] * (visibleCount - 1));
    BOOL distributeEqually = hasEmptySubview || totalWidthBefore <= 0;
    CGFloat delta = distributeEqually ? 0 : totalWidthAfter / totalWidthBefore;
    NSUInteger remaining = visibleCount;
    NSArray *held = distributeEqually ? nil : [self _lengthsByHoldingPriorityForTotal: totalWidthAfter];
    NSUInteger visibleIndex = 0;

    NSRect frame = [self bounds];
    for (i = 0; i < count; i++) {
        NSView *subview = [[self _arrangedList] objectAtIndex: i];
        if ([self isSubviewCollapsed: subview] == NO) {
            --remaining;
            CGFloat available = MAX(0, NSMaxX([self bounds]) - frame.origin.x);
            CGFloat proposed = held
                ? [[held objectAtIndex: visibleIndex++] doubleValue]
                : distributeEqually
                ? floor(totalWidthAfter / visibleCount)
                : floor(NSWidth([subview frame]) * delta);
            frame.size.width = remaining == 0 ? available
                : MIN(available, MAX(0, proposed));
            frame.size.height = height;

            NSSize oldSize = [subview frame].size;

            [subview setFrame: frame];

            frame.origin.x = MIN(NSMaxX([self bounds]),
                NSMaxX(frame) + [self dividerThickness]);
        }
    }
}

- (void) _adjustSubviewHeights {
    // Set all the subview widths to the bounds width of the split view
    CGFloat width = NSWidth([self bounds]);

    int i, count = [[self _arrangedList] count];

    // We've got to figure out how much the delta is between the old and new
    // heights and multiply all the heights to the new delta to get them to fit
    // (or something like that...) Apple says They resize proportionally
    CGFloat totalHeightBefore = 0.;
    NSUInteger visibleCount = 0;
    BOOL hasEmptySubview = NO;
    CGFloat totalHeightAfter =
            [self bounds].size.height - [self dividerThickness] * (count - 1);

    for (i = 0; i < count; i++) {
        NSView *subview = [[self _arrangedList] objectAtIndex: i];
        if ([self isSubviewCollapsed: subview] == NO) {
            NSRect subviewFrame = [subview frame];
            ++visibleCount;
            if (NSHeight(subviewFrame) <= 0)
                hasEmptySubview = YES;
            totalHeightBefore += NSHeight(subviewFrame);
        }
    }

    if (visibleCount == 0)
        return;
    totalHeightAfter = MAX(0, NSHeight([self bounds]) -
                             [self dividerThickness] * (visibleCount - 1));
    BOOL distributeEqually = hasEmptySubview || totalHeightBefore <= 0;
    CGFloat delta = distributeEqually ? 0 : totalHeightAfter / totalHeightBefore;
    NSUInteger remaining = visibleCount;
    NSArray *held = distributeEqually ? nil : [self _lengthsByHoldingPriorityForTotal: totalHeightAfter];
    NSUInteger visibleIndex = 0;

    NSRect frame = [self bounds];
    for (i = 0; i < count; i++) {
        NSView *subview = [[self _arrangedList] objectAtIndex: i];
        if ([self isSubviewCollapsed: subview] == NO) {
            --remaining;
            CGFloat available = MAX(0, NSMaxY([self bounds]) - frame.origin.y);
            CGFloat proposed = held
                ? [[held objectAtIndex: visibleIndex++] doubleValue]
                : distributeEqually
                ? floor(totalHeightAfter / visibleCount)
                : floor(NSHeight([subview frame]) * delta);
            frame.size.height = remaining == 0 ? available
                : MIN(available, MAX(0, proposed));
            frame.size.width = width;

            NSSize oldSize = [subview frame].size;

            [subview setFrame: frame];

            frame.origin.y = MIN(NSMaxY([self bounds]),
                NSMaxY(frame) + [self dividerThickness]);
        }
    }
}

/**
 * Apple says this method sets the frames of the split view's subviews so that
 * they, plus the dividers, fill the split view. The default implementation of
 * this method resizes all of the subviews proportionally so that the ratio of
 * heights (in the horizontal split view case) or widths (in the vertical split
 * view case) doesn't change, even though the absolute sizes of the subviews do
 * change. This message should be sent to split views from which subviews have
 * been added or removed, to reestablish the consistency of subview placement.
 */
- (void) adjustSubviews {

    if ([[self _arrangedList] count] == 0) {
        return;
    }

    [self _postNoteWillResize];

    if ([self isVertical]) {
        [self _adjustSubviewWidths];
    } else {
        [self _adjustSubviewHeights];
    }
    [self setNeedsDisplay: YES];
    [self _postNoteDidResize];
}

- (CGFloat) dividerThickness {
    if (NS_EXTRA(NSSplitView, self)->_dividerStyle == NSSplitViewDividerStyleThick) {
        return 10;
    } else {
        return 5;
    }
}

- (NSImage *) dimpleImage {
    if ([self isVertical])
        return [NSImage imageNamed: @"NSSplitViewVDimple"];
    else
        return [NSImage imageNamed: @"NSSplitViewHDimple"];
}

- (void) drawDividerInRect: (NSRect) rect {

    if (NS_EXTRA(NSSplitView, self)->_dividerStyle != NSSplitViewDividerStylePaneSplitter) {
        // Fill in the view - pane splitter means just draw the dimple
        [[NSColor controlColor] setFill];
        NSRectFill(rect);
    }

    NSImage *image = [self dimpleImage];
    NSSize imageSize = [image size];

    NSPoint point = rect.origin;

    if ([self isVertical]) {
        point.x += floor((NSWidth(rect) - imageSize.width) / 2);
        point.y += floor((NSHeight(rect) - imageSize.height) / 2);
    } else {
        point.x += floor((NSWidth(rect) - imageSize.width) / 2);
        point.y += floor((NSHeight(rect) - imageSize.height) / 2);
    }

    [image drawAtPoint: point
              fromRect: NSZeroRect
             operation: NSCompositeSourceOver
              fraction: 1.0];
}

#pragma mark Arranged subviews

// All the subviews are arranged unless -setArrangesAllSubviews: was given NO;
// then only the views added through -addArrangedSubview: and
// -insertArrangedSubview:atIndex: (and those that were arranged when the
// flag was cleared) are laid out.
- (NSArray *) _arrangedList {
    if (NS_EXTRA(NSSplitView, self)->_arrangesOnlyExplicit) {
        NSMutableArray *list = NS_EXTRA(NSSplitView, self)->_explicitArranged;
        NSUInteger i = [list count];

        while (i-- > 0)
            if ([[list objectAtIndex: i] superview] != self)
                [list removeObjectAtIndex: i];
        return list;
    }
    return _subviews;
}

- (NSArray *) arrangedSubviews {
    return [NSArray arrayWithArray: [self _arrangedList]];
}

- (BOOL) arrangesAllSubviews {
    return !NS_EXTRA(NSSplitView, self)->_arrangesOnlyExplicit;
}

- (void) setArrangesAllSubviews: (BOOL) flag {
    if (flag == [self arrangesAllSubviews])
        return;
    if (flag) {
        NS_EXTRA(NSSplitView, self)->_arrangesOnlyExplicit = NO;
        [NS_EXTRA(NSSplitView, self)->_explicitArranged release];
        NS_EXTRA(NSSplitView, self)->_explicitArranged = nil;
    } else {
        NS_EXTRA(NSSplitView, self)->_explicitArranged = [[NSMutableArray alloc] initWithArray: _subviews];
        NS_EXTRA(NSSplitView, self)->_arrangesOnlyExplicit = YES;
    }
}

- (void) insertArrangedSubview: (NSView *) view atIndex: (NSInteger) index {
    NSMutableArray *explicit = NS_EXTRA(NSSplitView, self)->_explicitArranged;
    NSArray *arranged = [self _arrangedList];

    if (index < 0 || (NSUInteger) index > [arranged count])
        [NSException raise: NSRangeException
                    format: @"Index %ld beyond the %lu arranged subviews",
                            (long) index, (unsigned long) [arranged count]];

    // The view goes in front of the subview currently at that index
    NSView *before = (NSUInteger) index < [arranged count] ? [arranged objectAtIndex: index] : nil;

    [self _recordPreferredLengthOfSubview: view];
    if (explicit != nil)
        [explicit removeObjectIdenticalTo: view];
    if (before != nil)
        [super addSubview: view positioned: NSWindowBelow relativeTo: before];
    else
        [super addSubview: view];
    if (explicit != nil)
        [explicit insertObject: view atIndex: MIN((NSUInteger) index, [explicit count])];
    [self setNeedsUpdateConstraints: YES];
    [self adjustSubviews];
}

- (void) addArrangedSubview: (NSView *) view {
    [self insertArrangedSubview: view atIndex: [[self _arrangedList] count]];
}

// Removes the view from the arrangement. With all subviews arranged that
// takes it out of the split view; otherwise it stays a (now unmanaged) subview.
- (void) removeArrangedSubview: (NSView *) view {
    if (![self arrangesAllSubviews]) {
        [NS_EXTRA(NSSplitView, self)->_explicitArranged removeObjectIdenticalTo: view];
        [self setNeedsUpdateConstraints: YES];
        [self adjustSubviews];
    } else if ([view superview] == self) {
        [view removeFromSuperview];
        [self setNeedsUpdateConstraints: YES];
        [self adjustSubviews];
    }
}

// An index outside the arranged subviews reads as the default priority and
// is ignored when setting.
- (NSLayoutPriority) holdingPriorityForSubviewAtIndex: (NSInteger) index {
    NSArray *arranged = [self _arrangedList];

    if (index < 0 || (NSUInteger) index >= [arranged count])
        return NSLayoutPriorityDefaultLow;
    return [self _holdingPriorityOfSubview: [arranged objectAtIndex: index]];
}

- (void) setHoldingPriority: (NSLayoutPriority) priority forSubviewAtIndex: (NSInteger) index {
    NSArray *arranged = [self _arrangedList];

    if (index < 0 || (NSUInteger) index >= [arranged count])
        return;
    objc_setAssociatedObject([arranged objectAtIndex: index], &holdingPriorityKey,
                             [NSNumber numberWithFloat: priority],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self _recordPreferredLengths];
    [self setNeedsUpdateConstraints: YES];
}

- (void) addSubview: (NSView *) view {
    [self _recordPreferredLengthOfSubview: view];
    [super addSubview: view];
    [self setNeedsUpdateConstraints: YES];
    [self adjustSubviews];
}

static const char arrangedConstraintsKey;

// When every visible arranged subview is laid out by constraints, the split view
// provides the constraints that arrange them: the subviews follow one another
// along the split axis separated by the divider thickness, fill the split view
// across it, and keep their current length at their holding priority. The
// subviews with the lowest holding priority are tied to each other in proportion
// to their current lengths and take up what the others do not hold.
- (void) updateConstraints {
    NSArray *old = objc_getAssociatedObject(self, &arrangedConstraintsKey);

    if (old != nil) {
        [self removeConstraints: old];
        objc_setAssociatedObject(self, &arrangedConstraintsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    NSMutableArray *visible = [NSMutableArray array];
    NSView *subview;
    BOOL allConstrained = YES;

    // The split view switches its arranged subviews to constraint-based layout when
    // the split view or any of them takes part in Auto Layout: a subview that
    // already opted out, or one that carries constraints of its own. Otherwise
    // they stay frame-based.
    BOOL constraintBased = ![self translatesAutoresizingMaskIntoConstraints];

    for (subview in [self _arrangedList]) {
        if ([self isSubviewCollapsed: subview])
            continue;
        [visible addObject: subview];
        if (![subview translatesAutoresizingMaskIntoConstraints] || [[subview constraints] count] > 0)
            constraintBased = YES;
    }
    if (constraintBased) {
        for (subview in visible)
            [subview setTranslatesAutoresizingMaskIntoConstraints: NO];
    } else {
        allConstrained = NO;
    }

    NSUInteger i, count = [visible count];

    if (count > 0 && allConstrained) {
        NSMutableArray *created = [NSMutableArray array];
        BOOL vertical = [self isVertical];
        NSLayoutAttribute startEdge = vertical ? NSLayoutAttributeLeft : NSLayoutAttributeTop;
        NSLayoutAttribute endEdge = vertical ? NSLayoutAttributeRight : NSLayoutAttributeBottom;
        NSLayoutAttribute crossStart = vertical ? NSLayoutAttributeTop : NSLayoutAttributeLeft;
        NSLayoutAttribute crossEnd = vertical ? NSLayoutAttributeBottom : NSLayoutAttributeRight;
        NSLayoutAttribute length = vertical ? NSLayoutAttributeWidth : NSLayoutAttributeHeight;
        CGFloat thickness = [self dividerThickness];
        NSLayoutPriority lowest = NSLayoutPriorityRequired;
        NSLayoutPriority tiePriority = NSLayoutPriorityDefaultHigh;
        NSView *tieAnchor = nil;
        CGFloat tieAnchorLength = 0;

        for (subview in visible) {
            NSLayoutPriority priority = [self _holdingPriorityOfSubview: subview];

            if (priority < lowest)
                lowest = priority;
        }

        for (i = 0; i < count; ++i) {
            subview = [visible objectAtIndex: i];
            CGFloat subviewLength = [self _preferredLengthOfSubview: subview];
            NSLayoutPriority priority = [self _holdingPriorityOfSubview: subview];

            [created addObject: [NSLayoutConstraint constraintWithItem: subview attribute: startEdge relatedBy: NSLayoutRelationEqual
                                                                toItem: i == 0 ? (id) self : [visible objectAtIndex: i - 1]
                                                             attribute: i == 0 ? startEdge : endEdge
                                                            multiplier: 1 constant: i == 0 ? 0 : thickness]];
            [created addObject: [NSLayoutConstraint constraintWithItem: subview attribute: crossStart relatedBy: NSLayoutRelationEqual
                                                                toItem: self attribute: crossStart multiplier: 1 constant: 0]];
            [created addObject: [NSLayoutConstraint constraintWithItem: subview attribute: crossEnd relatedBy: NSLayoutRelationEqual
                                                                toItem: self attribute: crossEnd multiplier: 1 constant: 0]];
            if (i == count - 1)
                [created addObject: [NSLayoutConstraint constraintWithItem: subview attribute: endEdge relatedBy: NSLayoutRelationEqual
                                                                    toItem: self attribute: endEdge multiplier: 1 constant: 0]];

            if (priority > lowest) {
                NSLayoutConstraint *hold = [NSLayoutConstraint constraintWithItem: subview attribute: length relatedBy: NSLayoutRelationEqual
                                                                           toItem: nil attribute: NSLayoutAttributeNotAnAttribute
                                                                       multiplier: 1 constant: subviewLength];
                [hold setPriority: priority];
                [created addObject: hold];
            } else if (tieAnchor == nil) {
                tieAnchor = subview;
                tieAnchorLength = subviewLength;
            } else {
                // equal shares when either has no length yet
                CGFloat ratio = tieAnchorLength > 0 && subviewLength > 0 ? subviewLength / tieAnchorLength : 1;
                NSLayoutConstraint *tie = [NSLayoutConstraint constraintWithItem: subview attribute: length relatedBy: NSLayoutRelationEqual
                                                                          toItem: tieAnchor attribute: length
                                                                      multiplier: ratio constant: 0];
                [tie setPriority: tiePriority];
                [created addObject: tie];
            }
        }
        [self addConstraints: created];
        objc_setAssociatedObject(self, &arrangedConstraintsKey, created, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [super updateConstraints];
}

- (void) resizeSubviewsWithOldSize: (NSSize) oldSize {
    NSSize size = [self bounds].size;
    NSPoint origin = [self bounds].origin;
    int i, count = [[self _arrangedList] count];

    if (size.width < 1)
        size.width = 1;
    if (size.height < 1)
        size.height = 1;
    if (oldSize.width < 1)
        oldSize.width = 1;
    if (oldSize.height < 1)
        oldSize.height = 1;

    if ([NS_EXTRA(NSSplitView, self)->_delegate respondsToSelector: @selector(splitView:
                                               resizeSubviewsWithOldSize:)]) {
        [NS_EXTRA(NSSplitView, self)->_delegate splitView: self resizeSubviewsWithOldSize: oldSize];
    } else {

        // Apple docs say just call adjustSubviews
        [self adjustSubviews];
    }
}

- (NSRect) dividerRectAtIndex: (unsigned) index {
    NSRect rect = [[[self _arrangedList] objectAtIndex: index] frame];

    if ([self isVertical]) {
        rect.origin.x = rect.origin.x + rect.size.width;
        rect.size.width = [self dividerThickness];
    } else {
        rect.origin.y = rect.origin.y + rect.size.height;
        rect.size.height = [self dividerThickness];
    }

    return rect;
}

- (void) drawRect: (NSRect) rect {
    int i, count = [[self _arrangedList] count];

    for (i = 0; i < count - 1; i++) {
        if ([self dividerThickness] > 0)
            [self drawDividerInRect: [self dividerRectAtIndex: i]];
    }
}

- (NSUInteger) dividerIndexAtPoint: (NSPoint) point {
    int i, count = [[self _arrangedList] count];

    for (i = 0; i < count - 1; i++) {
        NSRect rect = [self dividerRectAtIndex: i];

        if (NSMouseInRect(point, rect, [self isFlipped]))
            return i;
    }

    return NSNotFound;
}

static CGFloat constrainTo(CGFloat value, CGFloat min, CGFloat max) {
    if (value < min)
        value = min;
    if (value > max)
        value = max;
    return value;
}

- (void) mouseDown: (NSEvent *) event {

    NSPoint firstPoint = [self convertPoint: [event locationInWindow]
                                   fromView: nil];
    NSUInteger divider = [self dividerIndexAtPoint: firstPoint];

    if (divider == NSNotFound) {
        return;
    }

    NSEventType eventType;

    [self _postNoteWillResize];

    do {
        NSAutoreleasePool *pool = [NSAutoreleasePool new];
        NSPoint point;

        event = [[self window] nextEventMatchingMask: NSLeftMouseUpMask |
                                                      NSLeftMouseDraggedMask];
        eventType = [event type];

        point = [self convertPoint: [event locationInWindow] fromView: nil];

        if ([self isVertical]) {
            [self setPosition: point.x ofDividerAtIndex: divider];
        } else {
            [self setPosition: point.y ofDividerAtIndex: divider];
        }

        [pool release];
    } while (eventType != NSLeftMouseUp);

    if ([self dividerThickness] > 0)
        [[self window] invalidateCursorRectsForView: self];

    [self _postNoteDidResize];
}

- (void) resetCursorRects {

    if ([self dividerThickness] <= 0)
        return;

    int i, count = [[self _arrangedList] count];
    NSCursor *cursor;

    if ([self isVertical])
        cursor = [NSCursor resizeLeftRightCursor];
    else
        cursor = [NSCursor resizeUpDownCursor];

    for (i = 0; i < count - 1; i++) {
        NSRect rect = [self dividerRectAtIndex: i];

        // FIX
        // The cursor is activated one pixel past NSMaxY(rect) if we don't do
        // this, not sure where the problem is.
        rect.origin.y -= 1.;

        [self addCursorRect: rect cursor: cursor];
    }
}

// The divider can move until the subview before it is empty (minimum) or the
// subview after it is, leaving only the divider (maximum); a delegate may
// narrow that range.
- (CGFloat) minPossiblePositionOfDividerAtIndex: (int) index {
    NSArray *arranged = [self _arrangedList];

    NSAssert(index >= 0 && index < (NSInteger) [arranged count] - 1,
             @"divider index out of range");

    NSRect frame = [[arranged objectAtIndex: index] frame];
    CGFloat min = [self isVertical] ? NSMinX(frame) : NSMinY(frame);

    if ([NS_EXTRA(NSSplitView, self)->_delegate respondsToSelector: @selector
                   (splitView:constrainMinCoordinate:ofSubviewAt:)])
        min = [NS_EXTRA(NSSplitView, self)->_delegate splitView: self
                    constrainMinCoordinate: min
                               ofSubviewAt: index];
    return min;
}

- (CGFloat) maxPossiblePositionOfDividerAtIndex: (int) index {
    NSArray *arranged = [self _arrangedList];

    NSAssert(index >= 0 && index < (NSInteger) [arranged count] - 1,
             @"divider index out of range");

    NSRect frame = [[arranged objectAtIndex: index + 1] frame];
    CGFloat max = ([self isVertical] ? NSMaxX(frame) : NSMaxY(frame)) - [self dividerThickness];

    if ([NS_EXTRA(NSSplitView, self)->_delegate respondsToSelector: @selector
                   (splitView:constrainMaxCoordinate:ofSubviewAt:)])
        max = [NS_EXTRA(NSSplitView, self)->_delegate splitView: self
                    constrainMaxCoordinate: max
                               ofSubviewAt: index];
    return max;
}

/** adjusts the subviews on either side of the divider while
 * honoring the constraints imposed by the delegate (if any)
 */
- (void) setPosition: (CGFloat) position ofDividerAtIndex: (int) index {
    [self setNeedsUpdateConstraints: YES];
    NSAssert(index >= 0 && index < [[self _arrangedList] count] - 1,
             @"divider index out of range");

    NSView *subview0 = [[self _arrangedList] objectAtIndex: index];
    NSView *subview1 = [[self _arrangedList] objectAtIndex: index + 1];

    BOOL subview0Expanded = [self isSubviewCollapsed: subview0] == NO;
    BOOL subview1Expanded = [self isSubviewCollapsed: subview1] == NO;

    CGFloat minPosition = 0;
    CGFloat maxPosition = 0;

    NSRect frame0 = NSZeroRect;
    NSRect frame1 = NSZeroRect;

    if (subview0Expanded) {
        frame0 = [subview0 frame];
    }

    if (subview1Expanded) {
        frame1 = [subview1 frame];
    }

    // Determine the minimum position
    if (subview0Expanded) {
        if ([self isVertical]) {
            minPosition = NSMinX(frame0);
        } else {
            minPosition = NSMinY(frame0);
        }
    } else {
        NSAssert(subview1Expanded, @"both are collapsed??");
        if ([self isVertical]) {
            minPosition = NSMinX(frame1);
        } else {
            minPosition = NSMinY(frame1);
        }
    }

    // Determine the maximum position
    if (subview1Expanded) {
        if ([self isVertical]) {
            maxPosition = NSMaxX(frame1);
        } else {
            maxPosition = NSMaxY(frame1);
        }
    } else {
        NSAssert(subview0Expanded, @"both are collapsed??");
        if ([self isVertical]) {
            maxPosition = NSMaxX(frame0);
        } else {
            maxPosition = NSMaxY(frame0);
        }
    }

    // Check in with the delegate and see if it wants to tweak the min and max

    if ([NS_EXTRA(NSSplitView, self)->_delegate respondsToSelector: @selector
                   (splitView:constrainMinCoordinate:ofSubviewAt:)] ||
        [NS_EXTRA(NSSplitView, self)->_delegate respondsToSelector: @selector
                   (splitView:constrainMaxCoordinate:ofSubviewAt:)]) {
        // Use the modern API
        if ([NS_EXTRA(NSSplitView, self)->_delegate respondsToSelector: @selector
                       (splitView:constrainMinCoordinate:ofSubviewAt:)]) {
            minPosition = [NS_EXTRA(NSSplitView, self)->_delegate splitView: self
                        constrainMinCoordinate: minPosition
                                   ofSubviewAt: index];
        }
        if ([NS_EXTRA(NSSplitView, self)->_delegate respondsToSelector: @selector
                       (splitView:constrainMaxCoordinate:ofSubviewAt:)]) {
            maxPosition = [NS_EXTRA(NSSplitView, self)->_delegate splitView: self
                        constrainMaxCoordinate: maxPosition
                                   ofSubviewAt: index];
        }
    } else if ([NS_EXTRA(NSSplitView, self)->_delegate respondsToSelector: @selector
                          (splitView:
                                  constrainMinCoordinate:maxCoordinate
                                                        :ofSubviewAt:)]) {
        // Use the deprecated API

        [NS_EXTRA(NSSplitView, self)->_delegate splitView: self
                constrainMinCoordinate: &minPosition
                         maxCoordinate: &maxPosition
                           ofSubviewAt: index];
    }

    // And if it wants to constrain the divider position
    BOOL delegateWantsTrackConstraining = [NS_EXTRA(NSSplitView, self)->_delegate
            respondsToSelector: @selector(splitView:
                                        constrainSplitPosition:ofSubviewAt:)];

    if (delegateWantsTrackConstraining) {
        position = [NS_EXTRA(NSSplitView, self)->_delegate splitView: self
                 constrainSplitPosition: position
                            ofSubviewAt: index];
    }

    // OK we're ready to figure out where the divider can be positioned
    NSRect resize0 = frame0;
    NSRect resize1 = frame1;

    BOOL subviewsWereCollapsedOrExpanded = NO;
    BOOL checkWithDelegateAboutCollapsingViews = [NS_EXTRA(NSSplitView, self)->_delegate
            respondsToSelector: @selector(splitView:canCollapseSubview:)];
    if ([self isVertical]) {

        CGFloat lastPosition = NSMaxX(resize0);

        CGFloat delta = floor(position - lastPosition);

        resize0.size.width += delta;

        resize1.size.width -= delta;

        if (checkWithDelegateAboutCollapsingViews) {
            if (position < minPosition) {
                if ([NS_EXTRA(NSSplitView, self)->_delegate splitView: self canCollapseSubview: subview0]) {
                    [subview0 setHidden: YES];
                    subviewsWereCollapsedOrExpanded = YES;
                }
            } else if (position > maxPosition) {
                if ([NS_EXTRA(NSSplitView, self)->_delegate splitView: self canCollapseSubview: subview1]) {
                    [subview1 setHidden: YES];
                    subviewsWereCollapsedOrExpanded = YES;
                }
            }
        }

        // But make sure collapsed views can reappear
        if (position > minPosition && [subview0 isHidden]) {
            [subview0 setHidden: NO];
            subviewsWereCollapsedOrExpanded = YES;
        } else if (position < maxPosition && [subview1 isHidden]) {
            [subview1 setHidden: NO];
            subviewsWereCollapsedOrExpanded = YES;
        }

        // Figure out the adjusted widths
        resize0.size.width =
                constrainTo(NSWidth(resize0), minPosition, maxPosition);
        resize1.size.width =
                constrainTo(NSWidth(resize1), minPosition, maxPosition);
        resize1.origin.x =
                (NSMinX(frame1) + NSWidth(frame1)) - NSWidth(resize1);
    } else {

        CGFloat lastPosition = NSMaxY(resize0);
        CGFloat delta = floor(position - lastPosition);

        resize0.size.height += delta;

        resize1.size.height -= delta;

        if (checkWithDelegateAboutCollapsingViews) {
            if (position < minPosition) {
                if ([NS_EXTRA(NSSplitView, self)->_delegate splitView: self canCollapseSubview: subview0]) {
                    [subview0 setHidden: YES];
                    subviewsWereCollapsedOrExpanded = YES;
                }
            } else if (position > maxPosition) {
                if ([NS_EXTRA(NSSplitView, self)->_delegate splitView: self canCollapseSubview: subview1]) {
                    [subview1 setHidden: YES];
                    subviewsWereCollapsedOrExpanded = YES;
                }
            }
        }

        // But make sure collapsed views can reappear
        if (position > minPosition && [subview0 isHidden]) {
            [subview0 setHidden: NO];
            subviewsWereCollapsedOrExpanded = YES;
        } else if (position < maxPosition && [subview1 isHidden]) {
            [subview1 setHidden: NO];
            subviewsWereCollapsedOrExpanded = YES;
        }

        // Figure out the adjusted heights
        resize0.size.height =
                constrainTo(NSHeight(resize0), minPosition, maxPosition);
        resize1.size.height =
                constrainTo(NSHeight(resize1), minPosition, maxPosition);
        resize1.origin.y =
                (NSMinY(frame1) + NSHeight(frame1)) - NSHeight(resize1);
    }

    if (subviewsWereCollapsedOrExpanded) {
        // It doesn't really matter what happened with the divider because we
        // need to get the views re-laid out - so fall back to adjustSubviews
        // and bail
        [self adjustSubviews];
        return;
    }

    // Nothing special happened so just resize the subviews as expected
    if ([subview0 isHidden] == NO) {
        [subview0 setFrame: resize0];
        // Tell the view to redisplay otherwise there are drawing artifacts
        [subview0 setNeedsDisplay: YES];
    }

    if ([subview1 isHidden] == NO) {
        [subview1 setFrame: resize1];
        // Tell the view to redisplay otherwise there are drawing artifacts
        [subview1 setNeedsDisplay: YES];
    }

    [self _recordPreferredLengths];
    [self setNeedsDisplay: YES];
    [self _autosaveSubviewLayoutIfNecessary];
}

@end
