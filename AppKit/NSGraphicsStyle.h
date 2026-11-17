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
   NSOffState, NSOnState or NSMixedState (radio buttons have no mixed look). */
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
/* A rounded white bezel (a 4 point radius for a search field, a capsule for a rounded text field). */
- (void) drawRoundedTextFieldBezelInRect: (NSRect) rect radius: (CGFloat) radius;
/* The magnifying glass and the cancel button of a search field. */
- (void) drawSearchGlyphInRect: (NSRect) rect;
- (void) drawSearchCancelGlyphInRect: (NSRect) rect;
@end

@interface NSGraphicsStyle (NSSliderAqua)
/* The track of a slider: 3 points thick, blue from its start to the knob (gray when the window is not active or
   the control is disabled) and light after the knob; and the round white knob. */
- (void) drawAquaSliderTrackInRect: (NSRect) rect
                          vertical: (BOOL) vertical
                           knobRect: (NSRect) knobRect
                           enabled: (BOOL) enabled
                            active: (BOOL) active
                           flipped: (BOOL) flipped;
- (void) drawAquaSliderKnobInRect: (NSRect) rect controlSize: (NSControlSize) controlSize enabled: (BOOL) enabled;
@end

@interface NSGraphicsStyle (NSStepperAqua)
/* The whole stepper: one white capsule with an up and a down chevron. rect is the capsule including its
   one point shadow below. */
- (void) drawAquaStepperInRect: (NSRect) rect
                       enabled: (BOOL) enabled
                 upHighlighted: (BOOL) upHighlighted
               downHighlighted: (BOOL) downHighlighted;
@end

