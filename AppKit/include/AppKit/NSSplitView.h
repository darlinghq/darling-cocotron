/* Copyright (c) 2006-2007 Christopher J. W. Lloyd

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

#import <AppKit/AppKitIvarLayout.h>
#import <AppKit/NSView.h>
#import <AppKit/NSLayoutConstraint.h>

@class NSView, NSColor;

NS_ASSUME_NONNULL_BEGIN

APPKIT_EXPORT NSString *const NSSplitViewDidResizeSubviewsNotification;
APPKIT_EXPORT NSString *const NSSplitViewWillResizeSubviewsNotification;

typedef NS_ENUM(NSInteger, NSSplitViewDividerStyle) {
    NSSplitViewDividerStyleThick = 1,
    NSSplitViewDividerStyleThin,
    NSSplitViewDividerStylePaneSplitter,
};

// Legacy ObjC ABI (i386): instance size must stay 0x54, Apple's; the ivars
// before the extras sit at Apple's offsets. Add new state to the extra
// struct, never as an ivar.
@interface NSSplitView : NSView {
    NS_EXTRA_IVARS_BEGIN(NSSplitView)
        id _delegate;
        BOOL _isVertical;
        NSSplitViewDividerStyle _dividerStyle;
        NSString *_autosaveName;
        NSMutableArray *_explicitArranged;
        BOOL _arrangesOnlyExplicit;
    NS_EXTRA_IVARS_END(NSSplitView)
}

@property(null_unspecified, nonatomic, assign) id delegate;
@property(nonatomic, getter=isVertical) BOOL vertical;


@property(readonly, copy) NSArray<__kindof NSView *> *arrangedSubviews;
@property BOOL arrangesAllSubviews;

- (void) addArrangedSubview: (NSView *) view;
- (void) insertArrangedSubview: (NSView *) view atIndex: (NSInteger) index;
- (void) removeArrangedSubview: (NSView *) view;

- (NSLayoutPriority) holdingPriorityForSubviewAtIndex: (NSInteger) subviewIndex;
- (void) setHoldingPriority: (NSLayoutPriority) priority forSubviewAtIndex: (NSInteger) subviewIndex;

- (void) adjustSubviews;

- (CGFloat) dividerThickness;
@property(readonly, copy) NSColor *dividerColor;
- (void) drawDividerInRect: (NSRect) rect;

- (BOOL) isSubviewCollapsed: (NSView *) subview;

@property(nonatomic) NSSplitViewDividerStyle dividerStyle;

@property(null_unspecified, nonatomic, copy) NSString *autosaveName;

/* Get the minimum or maximum possible position of a divider */
- (CGFloat) minPossiblePositionOfDividerAtIndex: (int) index;
- (CGFloat) maxPossiblePositionOfDividerAtIndex: (int) index;

/** Set the position of a divider */
- (void) setPosition: (CGFloat) position ofDividerAtIndex: (int) index;

@end

// nb. it looks like the API for this is changed in MacOS X, replacing
// splitView:constrainMix:max:ofSubviewAt with two individual methods for each.
@protocol NSSplitViewDelegate <NSObject>
- (BOOL) splitView: (NSSplitView *) splitView
        canCollapseSubview: (NSView *) subview;
- (BOOL) splitView: (NSSplitView *) splitView
                 shouldCollapseSubview: (NSView *) subview
        forDoubleClickOnDividerAtIndex: (int) index;
- (CGFloat) splitView: (NSSplitView *) splitView
        constrainMinCoordinate: (CGFloat) proposedMinimumPosition
                   ofSubviewAt: (int) index;
- (CGFloat) splitView: (NSSplitView *) splitView
        constrainMaxCoordinate: (CGFloat) proposedMaximumPosition
                   ofSubviewAt: (int) index;

- (void) splitView: (null_unspecified NSSplitView *) splitView
        constrainMinCoordinate: (null_unspecified CGFloat *) min
                 maxCoordinate: (null_unspecified CGFloat *) max
                   ofSubviewAt: (int) index;
- (CGFloat) splitView: (NSSplitView *) splitView
        constrainSplitPosition: (CGFloat) pos
                   ofSubviewAt: (int) index;
- (void) splitView: (NSSplitView *) splitView
        resizeSubviewsWithOldSize: (NSSize) size;

- (BOOL) splitView: (NSSplitView *) splitView
        shouldAdjustSizeOfSubview: (NSView *) view;
- (BOOL) splitView: (NSSplitView *) splitView
        shouldHideDividerAtIndex: (int) index;

- (NSRect) splitView: (NSSplitView *) splitView
           effectiveRect: (NSRect) proposedEffectiveRect
            forDrawnRect: (NSRect) drawnRect
        ofDividerAtIndex: (int) index;
- (NSRect) splitView: (NSSplitView *) splitView
        additionalEffectiveRectOfDividerAtIndex: (NSInteger) index;

- (void) splitViewDidResizeSubviews: (NSNotification *) note;
- (void) splitViewWillResizeSubviews: (NSNotification *) note;
@end

NS_ASSUME_NONNULL_END
