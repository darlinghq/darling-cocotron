/* Copyright (c) 2007 Christopher J. W. Lloyd

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
#import <AppKit/NSSliderCell.h>
#import <AppKit/NSView.h>
#import <Foundation/NSGeometry.h>
#import <Foundation/NSObject.h>

@class NSImage, NSColor;

typedef struct _Margins {
    CGFloat left;
    CGFloat right;
    CGFloat top;
    CGFloat bottom;
} Margins;

@interface NSGraphicsStyle : NSObject {
    NSView *_view;
}

@end

@interface NSGraphicsStyle (NSMenu)
- (NSSize) menuItemSeparatorSize;
- (NSSize) menuItemBranchArrowSize;
- (NSSize) menuItemCheckMarkSize;
- (NSSize) menuItemGutterSize;
- (NSSize) menuItemTextSize: (NSString *) title;
- (NSSize) menuItemAttributedTextSize: (NSAttributedString *) title;
- (CGFloat) menuBarHeight;
- (CGFloat) menuItemGutterGap;

- (Margins) menuItemBranchArrowMargins;
- (Margins) menuItemGutterMargins;
- (Margins) menuItemTextMargins;

- (void) drawMenuSeparatorInRect: (NSRect) rect;
- (void) drawMenuGutterInRect: (NSRect) rect;
- (void) drawMenuCheckmarkInRect: (NSRect) rect
                         enabled: (BOOL) enabled
                        selected: (BOOL) selected;
- (void) drawMenuStateImage: (NSImage *) image
                    inRect: (NSRect) rect
                   enabled: (BOOL) enabled
                  selected: (BOOL) selected;
- (void) drawMenuItemText: (NSString *) string
                   inRect: (NSRect) rect
                  enabled: (BOOL) enabled
                 selected: (BOOL) selected;
- (void) drawAttributedMenuItemText: (NSAttributedString *) string
                             inRect: (NSRect) rect
                            enabled: (BOOL) enabled
                           selected: (BOOL) selected;
- (void) drawMenuBranchArrowInRect: (NSRect) rect
                           enabled: (BOOL) enabled
                          selected: (BOOL) selected;
- (void) drawMenuWindowBackgroundInRect: (NSRect) rect;
- (void) drawMenuBarBackgroundInRect: (NSRect) rect;
- (void) drawMenuSelectionInRect: (NSRect) rect enabled: (BOOL) enabled;
- (void) drawMenuBarItemBorderInRect: (NSRect) rect
                               hover: (BOOL) hovering
                            selected: (BOOL) selected;

@end

@interface NSGraphicsStyle (NSButton)
- (void) drawUnborderedButtonInRect: (NSRect) rect defaulted: (BOOL) defaulted;
- (void) drawPushButtonNormalInRect: (NSRect) rect defaulted: (BOOL) defaulted;
- (void) drawPushButtonPressedInRect: (NSRect) rect;
- (void) drawPushButtonHighlightedInRect: (NSRect) rect;
- (NSSize) sizeOfButtonImage: (NSImage *) image
                     enabled: (BOOL) enabled
                       mixed: (BOOL) mixed;
- (void) drawButtonImage: (NSImage *) image
                  inRect: (NSRect) rect
                 enabled: (BOOL) enabled
                   mixed: (BOOL) mixed;
@end

@interface NSGraphicsStyle (NSBrowser)
- (void) drawBrowserTitleBackgroundInRect: (NSRect) rect;
- (void) drawBrowserHorizontalScrollerWellInRect: (NSRect) rect
                                        clipRect: (NSRect) clipRect;
@end

@interface NSGraphicsStyle (NSColorWell)
- (NSRect) drawColorWellBorderInRect: (NSRect) rect
                             enabled: (BOOL) enabled
                            bordered: (BOOL) bordered
                              active: (BOOL) active;
@end

@interface NSGraphicsStyle (Buttons)
- (void) drawPopUpButtonWindowBackgroundInRect: (NSRect) rect;
@end

@interface NSGraphicsStyle (NSOutlineView)
- (void) drawOutlineViewGridInRect: (NSRect) rect;
@end

@interface NSGraphicsStyle (NSProgressIndicator)
- (NSRect) drawProgressIndicatorBackground: (NSRect) rect
                                  clipRect: (NSRect) clipRect
                                   bezeled: (BOOL) bezeled;
- (void) drawProgressIndicatorChunk: (NSRect) rect;
- (void) drawProgressIndicatorIndeterminate: (NSRect) rect
                                   clipRect: (NSRect) clipRect
                                    bezeled: (BOOL) bezeled
                                  animation: (double) animation;
- (void) drawProgressIndicatorDeterminate: (NSRect) rect
                                 clipRect: (NSRect) clipRect
                                  bezeled: (BOOL) bezeled
                                    value: (double) value;
@end

@interface NSGraphicsStyle (NSScroller)
- (void) drawScrollerButtonInRect: (NSRect) rect
                          enabled: (BOOL) enabled
                          pressed: (BOOL) pressed
                         vertical: (BOOL) vertical
                         upOrLeft: (BOOL) upOrLeft;
- (void) drawScrollerKnobInRect: (NSRect) rect
                       vertical: (BOOL) vertical
                      highlight: (BOOL) highlight;
- (void) drawScrollerTrackInRect: (NSRect) rect
                        vertical: (BOOL) vertical
                        upOrLeft: (BOOL) upOrLeft;
- (void) drawScrollerTrackInRect: (NSRect) rect vertical: (BOOL) vertical;
/* The knob of an overlay scroller: a dark capsule. rect is the knob rectangle across the full thickness of the
   scroller artwork, in the scroller's flipped coordinates. */
- (void) drawOverlayScrollerKnobInRect: (NSRect) rect vertical: (BOOL) vertical;
/* The square between a vertical and a horizontal legacy scroller of a scroll view. */
- (void) drawScrollerCornerInRect: (NSRect) rect flipped: (BOOL) flipped;
@end

@interface NSGraphicsStyle (NSSlider)
- (NSSize) sliderKnobSizeForControlSize: (NSControlSize) controlSize;
- (void) drawSliderKnobInRect: (NSRect) rect
                     vertical: (BOOL) vertical
                  highlighted: (BOOL) highlighted
                 hasTickMarks: (BOOL) hasTickMarks
             tickMarkPosition: (NSTickMarkPosition) tickMarkPosition;
- (void) drawSliderTrackInRect: (NSRect) rect
                      vertical: (BOOL) vertical
                  hasTickMarks: (BOOL) hasTickMarks;
- (void) drawSliderTickInRect: (NSRect) rect;
@end

@interface NSGraphicsStyle (NSStepper)
- (void) drawStepperButtonInRect: (NSRect) rect
                        clipRect: (NSRect) clipRect
                         enabled: (BOOL) enabled
                     highlighted: (BOOL) highlighted
                       upNotDown: (BOOL) upNotDown;
@end

@interface NSGraphicsStyle (NSTableView)
- (void) drawTableViewHeaderInRect: (NSRect) rect
                       highlighted: (BOOL) highlighted;
- (void) drawTableViewCornerInRect: (NSRect) rect;
// An indicator image of a column (-[NSTableView setIndicatorImage:inTableColumn:]) in its header
- (void) drawTableViewHeaderIndicatorImage: (NSImage *) image inRect: (NSRect) rect;
@end

@interface NSGraphicsStyle (NSBox)
- (void) drawBoxWithLineInRect: (NSRect) rect;
- (void) drawBoxWithBezelInRect: (NSRect) rect clipRect: (NSRect) clipRect;
- (void) drawBoxWithGrooveInRect: (NSRect) rect clipRect: (NSRect) clipRect;
@end

@interface NSGraphicsStyle (NSComboBox)
- (void) drawComboBoxButtonInRect: (NSRect) rect
                          enabled: (BOOL) enabled
                         bordered: (BOOL) bordered
                          pressed: (BOOL) pressed;
@end

@interface NSGraphicsStyle (NSTabView)
- (void) drawTabInRect: (NSRect) rect
              clipRect: (NSRect) clipRect
                 color: (NSColor *) color
              selected: (BOOL) selected;
- (void) drawTabPaneInRect: (NSRect) rect;
- (void) drawTabViewBackgroundInRect: (NSRect) rect;
@end

@interface NSGraphicsStyle (NSTextField)
- (void) drawTextFieldBorderInRect: (NSRect) rect
                    bezeledNotLine: (BOOL) bezeledNotLine;
/* The square bezel of a text field: a white rectangle and a one point outline, lighter when disabled. */
- (void) drawTextFieldBorderInRect: (NSRect) rect bezeledNotLine: (BOOL) bezeledNotLine enabled: (BOOL) enabled;
- (void) drawTextViewInsertionPointInRect: (NSRect) rect
                                    color: (NSColor *) color;
@end

@interface NSView (NSGraphicsStyle)
- (NSGraphicsStyle *) graphicsStyle;
@end

@interface NSGraphicsStyle (NSTabViewAqua)
/* The tinted rounded box behind a tab view's content, and the segmented strip of tabs that straddles
   its top edge. All rectangles are in the coordinates of the current context, whatever its
   orientation. */
- (void) drawTabViewBoxInRect: (NSRect) rect;
- (void) drawTabStripInRect: (NSRect) rect;
- (void) drawSelectedTabInRect: (NSRect) rect stripRect: (NSRect) stripRect active: (BOOL) active;
- (void) drawTabDividerInRect: (NSRect) rect;
@end

@interface NSGraphicsStyle (NSButtonAqua)
/* Check boxes and radio buttons. rect is in an unflipped coordinate system; its left edge is the left
   edge of the cell, and the box is placed relative to it and centred vertically in it. state is
   NSOffState, NSOnState or NSMixedState. */
- (void) drawCheckBoxInRect: (NSRect) rect
                      state: (NSInteger) state
                highlighted: (BOOL) highlighted
                    enabled: (BOOL) enabled
                     active: (BOOL) active
                controlSize: (NSControlSize) controlSize;
- (void) drawRadioButtonInRect: (NSRect) rect
                         state: (NSInteger) state
                   highlighted: (BOOL) highlighted
                       enabled: (BOOL) enabled
                        active: (BOOL) active
                   controlSize: (NSControlSize) controlSize;

// The outline of the box of a check box or radio button drawn in the rect (as the draw methods place it), for the
// keyboard focus ring.
- (NSBezierPath *) toggleBoxPathInRect: (NSRect) rect radio: (BOOL) radio controlSize: (NSControlSize) controlSize;
@end

@interface NSGraphicsStyle (NSPushButtonAqua)
/* The bezel of a rounded push button. rect is in an unflipped coordinate system and includes the one
   point shadow below the bezel. A default button is blue in an active window; a pressed one is blue too. */
- (void) drawPushButtonInRect: (NSRect) rect
                    defaulted: (BOOL) defaulted
                      pressed: (BOOL) pressed
                      enabled: (BOOL) enabled
                       active: (BOOL) active;
@end

@interface NSGraphicsStyle (NSPopUpButtonAqua)
/* The bezel of a pop-up or pull-down button: a white bezel with a blue end cap on the right that holds the
   up and down chevrons (a single down chevron for a pull-down). Same rectangle conventions as
   -drawPushButtonInRect:defaulted:pressed:enabled:active:. */
- (void) drawPopUpButtonInRect: (NSRect) rect
                     pullsDown: (BOOL) pullsDown
                       pressed: (BOOL) pressed
                       enabled: (BOOL) enabled
                        active: (BOOL) active
                   controlSize: (NSControlSize) controlSize;
@end

@interface NSGraphicsStyle (NSBoxAqua)
/* The primary and secondary box: a lightly tinted rounded rectangle with a thin outline. */
- (void) drawAquaBoxInRect: (NSRect) rect;
@end

@interface NSGraphicsStyle (NSSearchFieldAqua)
/* A rounded white bezel (a 4 point radius for search fields and rounded text fields). The outline is lighter when
   the field is disabled. */
- (void) drawRoundedTextFieldBezelInRect: (NSRect) rect radius: (CGFloat) radius;
- (void) drawRoundedTextFieldBezelInRect: (NSRect) rect radius: (CGFloat) radius enabled: (BOOL) enabled;
/* The magnifying glass and the cancel button of a search field, sized for the control size. rect is the search or
   cancel button's rectangle, in a flipped or unflipped coordinate system; the handle of the glass points down on
   the screen either way. */
- (void) drawSearchGlyphInRect: (NSRect) rect;
- (void) drawSearchCancelGlyphInRect: (NSRect) rect;
- (void) drawSearchGlyphInRect: (NSRect) rect controlSize: (NSControlSize) controlSize;
- (void) drawSearchCancelGlyphInRect: (NSRect) rect controlSize: (NSControlSize) controlSize;
@end

@interface NSGraphicsStyle (NSTexturedControlsAqua)
/* The bezels of textured (rounded and square), recessed and round-rect buttons, which textured segmented controls
   and pop-up buttons share. rect is the artwork rectangle in an unflipped coordinate system: the bezel and the
   point below it that it leaves free (a textured square bezel leaves one point at the top and the sides and two at
   the bottom). on is the on state of a button or a selected segment; pressed is a button being clicked. */
- (void) drawTexturedBezelInRect: (NSRect) rect
                          square: (BOOL) square
                         pressed: (BOOL) pressed
                              on: (BOOL) on
                     controlSize: (NSControlSize) controlSize;
/* The bezel's area between its top and bottom outline lines, which segment separators span. */
- (NSRect) texturedBezelInteriorForRect: (NSRect) rect square: (BOOL) square;
/* A one point separator between two segments, or along an edge of a selected one. */
- (void) drawTexturedSegmentSeparatorInRect: (NSRect) rect;
/* A recessed button: a translucent dark rounded rectangle, darker when on or pressed. */
- (void) drawRecessedBezelInRect: (NSRect) rect
                         pressed: (BOOL) pressed
                              on: (BOOL) on
                     controlSize: (NSControlSize) controlSize;
/* A round-rect button: a thin outline, with a light tint inside when on or pressed. */
- (void) drawRoundRectBezelInRect: (NSRect) rect filled: (BOOL) filled enabled: (BOOL) enabled;
/* The up and down chevrons of a textured pop-up button (one down chevron for a pull-down), near the right edge of
   the artwork rectangle rect, in an unflipped coordinate system. */
- (void) drawTexturedPopUpArrowsInRect: (NSRect) rect
                             pullsDown: (BOOL) pullsDown
                               enabled: (BOOL) enabled
                           controlSize: (NSControlSize) controlSize;
@end

@interface NSGraphicsStyle (NSSliderAqua)
/* The parts of a linear slider. Every rectangle is in the coordinates of the current context and on whole
   points; flipped tells whether that context is flipped. The track is 3 points thick and rounded; fillRect is
   the blue part of it (empty for none). */
- (void) drawAquaSliderTrackInRect: (NSRect) rect
                          fillRect: (NSRect) fillRect
                           enabled: (BOOL) enabled
                            active: (BOOL) active;
/* The knob: rect is its white body. pointing is -1 for a round knob, otherwise the screen direction its point
   faces: NSMinYEdge for down, NSMaxYEdge for up, NSMinXEdge for left and NSMaxXEdge for right. */
- (void) drawAquaSliderKnobInRect: (NSRect) rect
                         pointing: (NSInteger) pointing
                          enabled: (BOOL) enabled
                          flipped: (BOOL) flipped;
- (void) drawAquaSliderTickInRect: (NSRect) rect;
/* A circular slider: the white disc in rect and the dark knob in knobRect. */
- (void) drawAquaCircularSliderInRect: (NSRect) rect knobRect: (NSRect) knobRect enabled: (BOOL) enabled flipped: (BOOL) flipped;
@end

@interface NSGraphicsStyle (NSStepperAqua)
/* The whole stepper: one white capsule with an up and a down chevron. rect is the capsule without its shadow,
   which is drawn below it. A pressed half is blue with a white chevron. */
- (void) drawAquaStepperInRect: (NSRect) rect
                   controlSize: (NSControlSize) controlSize
                       enabled: (BOOL) enabled
                 upHighlighted: (BOOL) upHighlighted
               downHighlighted: (BOOL) downHighlighted;
@end

@interface NSGraphicsStyle (NSProgressIndicatorAqua)
/* The spinning style: 12 spokes in the square rect, the one at the top (phase 0) the darkest. */
- (void) drawSpinningProgressIndicatorInRect: (NSRect) rect phase: (NSInteger) phase;
/* The determinate spinning style: a ring with a wedge for the value (0 to 1), clockwise from the top. */
- (void) drawSpinningProgressPieInRect: (NSRect) rect value: (double) value flipped: (BOOL) flipped;
@end

@interface NSGraphicsStyle (NSLevelIndicatorAqua)
/* A capacity bar or one segment of it: a rounded rectangle, empty (a light track) or filled with color. */
- (void) drawLevelIndicatorTrackInRect: (NSRect) rect;
- (void) drawLevelIndicatorFillInRect: (NSRect) rect clipRect: (NSRect) clipRect color: (NSColor *) color;
- (void) drawLevelIndicatorTickInRect: (NSRect) rect major: (BOOL) major;
@end

@interface NSGraphicsStyle (NSSplitViewAqua)
/* The round dimple in the middle of a thick or pane splitter divider; rect is the dimple's own square. flipped
   tells whether the current coordinate system is flipped, so that the dimple is shaded from the top of the screen. */
- (void) drawSplitViewDimpleInRect: (NSRect) rect flipped: (BOOL) flipped;
/* The background of a pane splitter divider: a light gradient between two gray edge lines. */
- (void) drawSplitViewPaneSplitterInRect: (NSRect) rect vertical: (BOOL) vertical flipped: (BOOL) flipped;
@end

